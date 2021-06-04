// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class pwm_scoreboard extends cip_base_scoreboard #(
    .CFG_T(pwm_env_cfg),
    .RAL_T(pwm_reg_block),
    .COV_T(pwm_env_cov)
  );
  `uvm_component_utils(pwm_scoreboard)
  `uvm_component_new

  // TLM agent fifos
  uvm_tlm_analysis_fifo #(pwm_item) item_fifo[PWM_NUM_CHANNELS];

  local pwm_regs_t scb_pwm_regs;
  local pwm_item exp_item_q[PWM_NUM_CHANNELS][$];

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    for (int i = 0; i < PWM_NUM_CHANNELS; i++) begin
      item_fifo[i] = new($sformatf("item_fifo[%0d]", i), this);
    end
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      `DV_SPINWAIT_EXIT(
        for (int i = 0; i < PWM_NUM_CHANNELS; i++) begin
          fork
            automatic int channel = i;
            compare_trans(channel);
          join_none
        end
        wait fork;,
        @(negedge cfg.clk_rst_vif.rst_n),
      )
    end
  endtask : run_phase

  virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);
    uvm_reg csr;
    bit [TL_DW-1:0] reg_value;
    bit do_read_check = 1'b1;
    bit write = item.is_write();
    uvm_reg_addr_t csr_addr = ral.get_word_aligned_addr(item.a_addr);

    bit addr_phase_write = (write && channel  == AddrChannel);
    bit data_phase_read  = (!write && channel == DataChannel);

    // if access was to a valid csr, get the csr handle
    if (csr_addr inside {cfg.ral_models[ral_name].csr_addrs}) begin
      csr = ral.default_map.get_reg_by_offset(csr_addr);
      `DV_CHECK_NE_FATAL(csr, null)
    end
    else begin
      //`uvm_fatal(`gfn, $sformatf("Access unexpected addr 0x%0h", csr_addr))
    end

    if (addr_phase_write) begin
      string csr_name = csr.get_name();

      // if incoming access is a write to a valid csr, then make updates right away
      void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));

      // process the csr req
      // for write, update local variable and fifo at address phase
      // for read, update predication at address phase and compare at data phase
      case (csr_name)
        "cfg": begin
          reg_value = ral.cfg.get_mirrored_value();
          scb_pwm_regs.clk_div = get_field_val(ral.cfg.clk_div, reg_value);
          scb_pwm_regs.dc_resn = get_field_val(ral.cfg.dc_resn, reg_value);
          scb_pwm_regs.beat_cycle  = scb_pwm_regs.clk_div + 1;
          scb_pwm_regs.pulse_cycle = 2**(scb_pwm_regs.dc_resn + 1);
        end
        "invert": begin
          scb_pwm_regs.invert = ral.invert.get_mirrored_value();
          `uvm_info(`gfn, $sformatf("\n  scb: channels invert %b", scb_pwm_regs.invert), UVM_LOW)
        end
        "pwm_en": begin
          scb_pwm_regs.en = ral.pwm_en.get_mirrored_value();
          `uvm_info(`gfn, $sformatf("\n  scb: channels status %b", scb_pwm_regs.en), UVM_LOW)
          for (int channel = 0; channel < PWM_NUM_CHANNELS; channel++) begin
            if (scb_pwm_regs.en[channel]) begin
              scb_pwm_regs.num_pulses = cfg.num_pulses;
              cfg.print_pwm_regs("scb", scb_pwm_regs, channel);
              generate_exp_items(channel);
            end
          end
        end
        "pwm_param_0", "pwm_param_1", "pwm_param_2",
        "pwm_param_3", "pwm_param_4", "pwm_param_5": begin
          int channel = get_reg_index(csr_name, 10);
          scb_pwm_regs.blink_en[channel]    = item.a_data[31];
          scb_pwm_regs.htbt_en[channel]     = item.a_data[30];
          scb_pwm_regs.phase_delay[channel] = item.a_data[15:0];
          scb_pwm_regs.pwm_mode[channel]    = get_pwm_mode({scb_pwm_regs.blink_en[channel],
                                                            scb_pwm_regs.htbt_en[channel]});
          `uvm_info(`gfn, $sformatf("\n  scb: channel %0d, data %b, pwm_mode %s, phase_delay %0d",
              channel, item.a_data, scb_pwm_regs.pwm_mode[channel].name(),
              scb_pwm_regs.phase_delay[channel]), UVM_DEBUG)
        end
        "duty_cycle_0", "duty_cycle_1", "duty_cycle_2",
        "duty_cycle_3", "duty_cycle_4", "duty_cycle_5": begin
          int channel = get_reg_index(csr_name, 11);
          {scb_pwm_regs.duty_cycle_b[channel], scb_pwm_regs.duty_cycle_a[channel]} = item.a_data;
          `uvm_info(`gfn, $sformatf("\n  scb: channel %0d, duty_cycle_b %0d, duty_cycle_a %0d",
              channel, scb_pwm_regs.duty_cycle_b, scb_pwm_regs.duty_cycle_a), UVM_LOW)
        end
        "blink_param_0", "blink_param_1", "blink_param_2",
        "blink_param_3", "blink_param_4", "blink_param_5": begin
          int channel = get_reg_index(csr_name, 12);
          {scb_pwm_regs.blink_param_y[channel], scb_pwm_regs.blink_param_x[channel]} = item.a_data;
          `uvm_info(`gfn, $sformatf("\n  scb: channel %0d, blink_param_y %0d, blink_param_x %0d",
              channel, scb_pwm_regs.blink_param_y[channel],
              scb_pwm_regs.blink_param_x[channel]), UVM_DEBUG)
        end
        default: begin
          `uvm_fatal(`gfn, $sformatf("\n  scb: invalid csr: %0s", csr.get_full_name()))
        end
      endcase
    end

    // On reads, if do_read_check, is set, then check mirrored_value against item.d_data
    if (data_phase_read) begin
      if (do_read_check) begin
        `DV_CHECK_EQ(csr.get_mirrored_value(), item.d_data,
                     $sformatf("reg name: %0s", csr.get_full_name()))
      end
      void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));
    end
  endtask

  virtual task compare_trans(int channel);
    pwm_item exp_item;
    pwm_item dut_item;

    forever begin
      item_fifo[channel].get(dut_item);
      wait(exp_item_q[channel].size() > 0);
      exp_item = exp_item_q[channel].pop_front();

      if (!compare_items(exp_item, dut_item)) begin
        //cfg.print_pwm_regs("scb", scb_pwm_regs, channel);
        `uvm_error(`gfn, $sformatf("\n--> channel %0d item mismatch!\n--> EXP:\n%s\--> DUT:\n%s",
            channel, exp_item.sprint(), dut_item.sprint()))
      end else begin
        `uvm_info(`gfn, $sformatf("\n--> channel %0d item match!\n--> EXP:\n%s\--> DUT:\n%s",
            channel, exp_item.sprint(), dut_item.sprint()), UVM_DEBUG)
      end
    end
  endtask : compare_trans

  virtual function void generate_exp_items(uint channel);
    pwm_item exp_item;
    uint beat_cycle  = uint'(scb_pwm_regs.beat_cycle);
    uint pulse_cycle = uint'(scb_pwm_regs.pulse_cycle);

    exp_item = pwm_item::type_id::create("exp_item");
    exp_item.en_cycles  = cfg.num_pulses * beat_cycle * pulse_cycle;
    if (scb_pwm_regs.en[channel]) begin
      case (scb_pwm_regs.pwm_mode[channel])
        Heartbeat: begin
          scb_pwm_regs.pwm_mode[channel] = Heartbeat;
          // TODO: get the duty_cycle for the Heartbeat mode
        end
        Blinking: begin
          uint pulse_duty_a = scb_pwm_regs.duty_cycle_a[channel] % pulse_cycle;
          uint pulse_duty_b = scb_pwm_regs.duty_cycle_b[channel] % pulse_cycle;
          scb_pwm_regs.pwm_mode[channel] = Blinking;
          // pulse_duty is switched between duty_cycle_a and duty_cycle_b
          exp_item.duty_cycle = beat_cycle * (
                                pulse_duty_a * (scb_pwm_regs.blink_param_x[channel] + 1) +
                                pulse_duty_b * (scb_pwm_regs.blink_param_y[channel] + 1));
        end
        default: begin  // Standard mode
          uint pulse_duty = scb_pwm_regs.duty_cycle_a[channel] % pulse_cycle;
          scb_pwm_regs.pwm_mode[channel] = Standard;
          // pulse_duty depends on duty_cycle_a is only
          exp_item.duty_cycle = beat_cycle * cfg.num_pulses * pulse_duty;
        end
      endcase
    end
    exp_item_q[channel].push_back(exp_item);
    `uvm_info(`gfn, $sformatf("\n--> scb: get exp_item for channel %0d\n%s",
        channel, exp_item.sprint()), UVM_DEBUG)
  endfunction : generate_exp_items

  virtual function int compare_items(pwm_item exp, pwm_item dut);
    int en_cycles_diff  = $unsigned(exp.en_cycles   - dut.en_cycles);
    int duty_cycle_diff = $unsigned(exp.duty_cycle - dut.duty_cycle);

    return (en_cycles_diff <= 2 &&  duty_cycle_diff <= 2) ? 1 : 0;
  endfunction : compare_items

  virtual function int get_reg_index(string csr_name, int pos);
    return csr_name.substr(pos, pos).atoi();
  endfunction : get_reg_index

  virtual function void reset(string kind = "HARD");
    super.reset(kind);
    for (int i = 0; i < PWM_NUM_CHANNELS; i++) begin
      item_fifo[i].flush();
      exp_item_q[i].delete();
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    for (int i = 0; i < PWM_NUM_CHANNELS; i++) begin
      `DV_EOT_PRINT_Q_CONTENTS(pwm_item, exp_item_q[i])
      `DV_EOT_PRINT_TLM_FIFO_CONTENTS(pwm_item, item_fifo[i])
    end
  endfunction

endclass : pwm_scoreboard