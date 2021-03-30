// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_agent_cfg extends dv_base_agent_cfg;

  bit en_monitor = 1'b1; // enable monitor

  // num of trans. sent by Host agent to Target dut, configured by test
  uint num_trans;

  i2c_target_addr_mode_e target_addr_mode = Addr7BitMode;
  bit [Addr7BitMode-1:0] target_addr0 = 'h0;
  bit [Addr7BitMode-1:0] target_addr1 = 'h0;
  bit [Addr7BitMode-1:0] target_mask0 = 'h0;
  bit [Addr7BitMode-1:0] target_mask1 = 'h0;

  timing_cfg_t    timing_cfg;

  virtual i2c_if  vif;

  `uvm_object_utils_begin(i2c_agent_cfg)
    `uvm_field_int(en_monitor,                                UVM_DEFAULT)
    `uvm_field_enum(i2c_target_addr_mode_e, target_addr_mode, UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSetupStart,                    UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tHoldStart,                     UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tClockStart,                    UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tClockLow,                      UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSetupBit,                      UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tClockPulse,                    UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tHoldBit,                       UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tClockStop,                     UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSetupStop,                     UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tHoldStop,                      UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tTimeOut,                       UVM_DEFAULT)
    `uvm_field_int(timing_cfg.enbTimeOut,                     UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tStretchHostClock,              UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSdaUnstable,                   UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSdaInterference,               UVM_DEFAULT)
    `uvm_field_int(timing_cfg.tSclInterference,               UVM_DEFAULT)

    `uvm_field_int(target_addr0, UVM_DEFAULT)
    `uvm_field_int(target_addr1, UVM_DEFAULT)
    `uvm_field_int(target_mask0, UVM_DEFAULT)
    `uvm_field_int(target_mask1, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

  function print_agent_regs(bit do_print = 1'b1);
    if (do_print) begin
      string str;

      str = "\nAgent registers\n";
      str = {str, $sformatf("  tSetupStart       %d\n", timing_cfg.tSetupStart)};
      str = {str, $sformatf("  tHoldStart        %d\n", timing_cfg.tHoldStart)};
      str = {str, $sformatf("  tClockStart       %d\n", timing_cfg.tClockStart)};
      str = {str, $sformatf("  tClockLow         %d\n", timing_cfg.tClockLow)};
      str = {str, $sformatf("  tSetupBit         %d\n", timing_cfg.tSetupBit)};
      str = {str, $sformatf("  tClockPulse       %d\n", timing_cfg.tClockPulse)};
      str = {str, $sformatf("  tHoldBit          %d\n", timing_cfg.tHoldBit)};
      str = {str, $sformatf("  tClockStop        %d\n", timing_cfg.tClockStop)};
      str = {str, $sformatf("  tSetupStop        %d\n", timing_cfg.tSetupStop)};
      str = {str, $sformatf("  tHoldStop         %d\n", timing_cfg.tHoldStop)};
      str = {str, $sformatf("  tTimeOut          %d\n", timing_cfg.tTimeOut)};
      str = {str, $sformatf("  enbTimeOut        %0d\n", timing_cfg.enbTimeOut)};
      str = {str, $sformatf("  tSdaUnstable      %d\n", timing_cfg.tSdaUnstable)};
      str = {str, $sformatf("  tSdaInterference  %d\n", timing_cfg.tSdaInterference)};
      str = {str, $sformatf("  tSclInterference  %d\n", timing_cfg.tSclInterference)};
      `uvm_info(`gfn, $sformatf("%s", str), UVM_LOW)
    end
  endfunction : print_agent_regs

endclass : i2c_agent_cfg
