// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_driver extends dv_base_driver #(i2c_item, i2c_agent_cfg);
  `uvm_component_utils(i2c_driver)
  `uvm_component_new

  local bit pre_stop = 1'b0;

  virtual task reset_signals();
    forever begin
      @(negedge cfg.vif.rst_ni);
      `uvm_info(`gfn, "\n  driver in reset progress", UVM_DEBUG)
      cfg.vif.control_bus();
      @(posedge cfg.vif.rst_ni);
      `uvm_info(`gfn, "\n  driver out of reset", UVM_LOW)
    end
  endtask : reset_signals

  virtual task get_and_drive();
    forever begin
      cfg.vif.control_bus(.do_assert(1'b1));
      // driver drives bus per mode
      seq_item_port.get_next_item(req);
      `uvm_info(`gfn, $sformatf("\n  get request \n%s", req.sprint()), UVM_LOW)
      $cast(rsp, req.clone());
      rsp.set_id_info(req);
      fork
        begin: iso_fork
          fork
            begin
              if (cfg.if_mode == Device) drive_device_item(req);
              else                       drive_host_item(req);
            end // handle on-the-fly reset
            begin
              process_reset();
              req.clear_all();
            end
          join_any
          disable fork;
        end: iso_fork
      join
      seq_item_port.item_done(rsp);
    end
  endtask : get_and_drive

  virtual task drive_host_item(i2c_item req);
    uint trans = 0;

    cfg.print_agent_regs();
    `uvm_info(`gfn, $sformatf("\n  drive_host_item trans %0d/%0d",
        trans, cfg.num_trans), UVM_LOW)
    `DV_CHECK_EQ((req.start | req.rstart), 1'b0)
    if (req.start) begin
      cfg.vif.host_control_bus(cfg.timing_cfg, HostStart, 1'b0);
      `uvm_info(`gfn, $sformatf("\n  drive_host_item sends START bit"), UVM_LOW)
    end else begin
      cfg.vif.host_control_bus(cfg.timing_cfg, HostStopOrRStart, 1'b0);
      `uvm_info(`gfn, $sformatf("\n  drive_host_item sends RSTART bit"), UVM_LOW)
    end
    `uvm_info(`gfn, $sformatf("\n  drive_host_item sends ADDRESS bits 0x%0x", req.addr), UVM_LOW)
    for (int i = cfg.target_addr_mode-1; i >= 0; i--) begin
      cfg.vif.host_control_bus(cfg.timing_cfg, HostData, req.addr[i]);
      `uvm_info(`gfn, $sformatf("\n  addr[%0d]  %0b", i, req.addr[i]), UVM_LOW)
    end
    `uvm_info(`gfn, $sformatf("\n  drive_host_item sends R/Q bits %s",
        req.bus_op.name()), UVM_LOW)
    cfg.vif.host_control_bus(cfg.timing_cfg, HostData, req.bus_op);

    `uvm_info(`gfn, $sformatf("\n  drive_host_item wait device ACK"), UVM_LOW)
    cfg.vif.wait_for_device_ack(cfg.timing_cfg);  // target ack for address byte
    if (req.bus_op == BusOpWrite) begin
      bit [7:0] wr_data;
      while (req.data_q.size() > 0) begin
        wr_data = req.data_q.pop_front();
        for (int i = 7; i >= 0; i--) begin
          cfg.vif.host_control_bus(cfg.timing_cfg, HostData, wr_data[i]);
        end
        cfg.vif.wait_for_device_ack(cfg.timing_cfg); // target ack for wr_data bytes
      end
    end else begin
      // TODO
    end
    if (req.stop) begin  // issue stop
      cfg.vif.host_control_bus(cfg.timing_cfg, HostStopOrRStart, 1'b1);
      `uvm_info(`gfn, $sformatf("\n  drive_host_item sends STOP bit"), UVM_LOW)
    end

  endtask : drive_host_item

  virtual task drive_device_item(i2c_item req);
    bit [7:0] data;

    unique case (req.drv_type)
      DevAck: begin
        cfg.timing_cfg.tStretchHostClock = gen_num_stretch_host_clks(cfg.timing_cfg);
        fork
          // host clock stretching allows a high-speed host to communicate
          // with a low-speed device by setting TIMEOUT_CTRL.EN bit
          // the device asks host stretching its scl_i by pulling down scl_o
          // the host clock pulse is extended until device scl_o is pulled up
          // once scl_o is pulled down longer than TIMEOUT_CTRL.VAL field,
          // intr_stretch_timeout_o is asserted (ref. https://www.i2c-bus.org/clock-stretching)
          cfg.vif.device_stretch_host_clk(cfg.timing_cfg);
          cfg.vif.device_send_ack(cfg.timing_cfg);
        join
      end
      RdData: begin
        // device can randomly pulled down scl_device2host, connected to dut,
        // for certain number of clocks that asks host stretching scl_host2device
        // (e.g. if it could not send more data)
        if (req.do_stretch_clk) begin
          cfg.timing_cfg.tStretchHostClock = $urandom_range(0, cfg.timing_cfg.tTimeOut);
          cfg.vif.device_stretch_host_clk(cfg.timing_cfg, 1'b0);
        end
        // once clock stretch is cleared by device agent (scl_device2host is pulled up)
        // then agent can keep sending read data to the host dut
        for (int i = 7; i >= 0; i--) begin
          cfg.vif.device_send_bit(cfg.timing_cfg, req.rd_data[i]);
        end
        `uvm_info(`gfn, $sformatf("\n  drive_device_item, trans %0d, byte %0d  %0x",
            req.tran_id, req.num_data + 1, req.rd_data), UVM_DEBUG)
      end
      WrData:
        for (int i = 7; i >= 0; i--) begin
          cfg.vif.get_bit_data("host", cfg.timing_cfg, data[i]);
        end
      default: begin
        `uvm_fatal(`gfn, $sformatf("\n  drive_device_item, received invalid request"))
      end
    endcase
  endtask : drive_device_item

  function int gen_num_stretch_host_clks(ref timing_cfg_t tc);
    // By randomly pulling down scl_o "offset" within [0:2*tc.tTimeOut],
    // intr_stretch_timeout_o interrupt would be generated uniformly
    // To test this feature more regressive, there might need a dedicated vseq (V2)
    // in which TIMEOUT_CTRL.EN is always set.
    return $urandom_range(tc.tClockPulse, tc.tClockPulse + 2*tc.tTimeOut);
  endfunction : gen_num_stretch_host_clks

  virtual task process_reset();
    @(negedge cfg.vif.rst_ni);
    cfg.vif.control_bus(.do_assert(1'b1));
    `uvm_info(`gfn, "\n  driver is reset", UVM_DEBUG)
  endtask : process_reset



endclass : i2c_driver
