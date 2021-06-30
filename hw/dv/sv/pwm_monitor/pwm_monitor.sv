// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class pwm_monitor #(
  parameter int NumPwmChannels = 6
) extends dv_base_monitor #(
  .CFG_T  (pwm_monitor_cfg#(NumPwmChannels)),
  .ITEM_T (pwm_item)
);

  `uvm_component_param_utils(pwm_monitor#(NumPwmChannels))
  `uvm_component_new

  uvm_analysis_port #(pwm_item) item_port[NumPwmChannels];
  local bit reset_asserted = 1'b0;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    for (uint i = 0; i < NumPwmChannels; i++) begin
      item_port[i] = new($sformatf("item_port[%0d]", i), this);
    end
    // get vif handle
    if (!uvm_config_db#(virtual pwm_if#(NumPwmChannels))::get(this, "", "vif", cfg.vif)) begin
      `uvm_fatal(`gfn, "\n  mon: failed to get vif handle from uvm_config_db")
    end
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    //wait(cfg.vif.rst_n);
    collect_trans(phase);
  endtask : run_phase

  virtual protected task collect_trans(uvm_phase phase);
    fork
      for (uint i = 0; i < NumPwmChannels; i++) begin
        fork
          automatic uint channel = i;
          collect_channel_trans(channel);
        join_none
      end
      reset_thread();
    join
  endtask : collect_trans

  virtual task collect_channel_trans(int channel);
    pwm_item item;
    int item_index;
    int filter_index;
    bit channel_start;
    bit is_blink;

    forever begin
      wait(cfg.en_monitor);
      fork
        begin : isolation_thread
          fork
            // channel start
            begin
              channel_start = 1'b0;
              is_blink = 1'b0;
              @(posedge cfg.vif.clk && cfg.pwm_en[channel] && cfg.cntr_en);
              `uvm_info(`gfn, $sformatf("\n  mon: channel %0d is enabled", channel), UVM_LOW)
              case (cfg.pwm_mode[channel])
                Blinking: filter_index = cfg.blink_param_x[channel] + 1;
                default:  filter_index = 1;
              endcase
              // ignore the first pulse which might be incompletely generated
              get_pulse_edge(channel);
              item_index = 1;
              `uvm_info(`gfn, $sformatf("\n  mon: channel %0d: ignore the first edge",
                  channel), UVM_LOW)
              @(negedge cfg.vif.clk); // let duty_cycle_counting thread start after the first edge
              channel_start = 1'b1;
              fork
                begin : duty_cycle_counting
                  `uvm_info(`gfn, $sformatf("\n  mon: channel %0d: start capturing pulses",
                      channel), UVM_HIGH)
                  // calculate pulse duty
                  while (cfg.pwm_en[channel]) begin
                    // use negedge for counting duty to avoid metastability with posedge
                    @(negedge cfg.vif.clk);
                    item.duty_high += (cfg.vif.pwm[channel] == 1'b1);
                    item.duty_low  += (cfg.vif.pwm[channel] == 1'b0);
                  end : duty_cycle_counting
                  `uvm_info(`gfn, $sformatf("\n  mon: channel %0d stops, channel_start %b",
                      channel, channel_start), UVM_HIGH)
                end : duty_cycle_counting
                begin : capture_item
                  while (channel_start) begin
                    item = pwm_item::type_id::create("mon_item");
                    get_pulse_edge(channel);
                    item.index = item_index;
                    `uvm_info(`gfn, $sformatf("\n  mon: get pulse edge, index = %0d",
                        item.index), UVM_LOW)
                    if (!check_invalid_item(channel, item, is_blink, filter_index)) begin
                      item_port[channel].write(item);
                      `uvm_info(`gfn, $sformatf("\n--> mon: send item of channel %0d\n%s",
                          channel, item.sprint()), UVM_LOW)
                    end
                    item_index++;
                  end
                end : capture_item
              join
            end
            // do until channel stop
            begin : check_channel_stop
              @(negedge channel_start & !cfg.cntr_en);
              `uvm_info(`gfn, $sformatf("\n  mon: stop channel %0d", channel), UVM_LOW)
            end : check_channel_stop
            // handle reset
            @(posedge reset_asserted);
          join_any
          disable fork;
        end : isolation_thread
      join
    end
  endtask : collect_channel_trans

  virtual task get_pulse_edge(int channel);
    if (cfg.invert[channel]) begin
      if (is_pulse_wrapped(channel) == PulseWrapped) @(negedge cfg.vif.pwm[channel]);
      else                                           @(posedge cfg.vif.pwm[channel]);
    end else begin
      if (is_pulse_wrapped(channel) == PulseWrapped) @(negedge cfg.vif.pwm[channel]);
      else                                           @(posedge cfg.vif.pwm[channel]);
    end
  endtask : get_pulse_edge

  virtual function pwm_pulse_wrap_e is_pulse_wrapped(int channel);
    int pulse_start = cfg.phase_delay[channel] + (cfg.duty_cycle_a[channel] % cfg.pulse_cycle);
    if (pulse_start >= cfg.pulse_cycle) return PulseWrapped;
    else                                return PulseNoWrapped;
  endfunction : is_pulse_wrapped

  virtual task reset_thread();
    forever begin
      @(negedge cfg.vif.rst_n);
      reset_asserted = 1'b1;
      @(posedge cfg.vif.rst_n);
      reset_asserted = 1'b0;
    end
  endtask : reset_thread

  virtual task monitor_ready_to_end();
    forever begin
      @(cfg.vif.pwm);
      ok_to_end = (cfg.vif.pwm === '0) && (cfg.pwm_en == '0) ;
    end
  endtask : monitor_ready_to_end

  virtual function int check_invalid_item(int channel, pwm_item item, 
                                        ref bit blink, ref int index);


    // first and 2 last pulses are ignored (same as monitor)
    bit fist_last_item = (item.index == 1) | (item.index >= cfg.num_pulses - 1);
    unique case (cfg.pwm_mode[channel])
      Heartbeat: begin
        // TODO
        return 1'b0;
      end
      Blinking: begin
        // when blinking happens, the last pulses with duty_cycle_a and the first pulse
        // with duty_cycle_b migh have incomplete shapes so they are also ignored
        bit invalid_item = fist_last_item |
                           (item.index inside {1, [index : index + 1]});
        `uvm_info(`gfn, $sformatf("\n  mon: range [%0d : %0d]", index, index + 1), UVM_LOW);
        if (item.index == index + 1) begin  // blinking occurs in next pulse
          blink = ~blink;
          index += (blink) ? cfg.blink_param_y[channel] + 1 : cfg.blink_param_x[channel] + 1;
        end
        return invalid_item;
      end
      Standard: begin
        return fist_last_item;
      end
    endcase
  endfunction : check_invalid_item

endclass : pwm_monitor
