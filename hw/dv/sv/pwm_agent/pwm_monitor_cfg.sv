// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class pwm_monitor_cfg #(
  parameter int NumPwmChannels = 6
) extends dv_base_agent_cfg;

  // interface handle used by driver, monitor & the sequencer, via cfg handle
  virtual pwm_if#(NumPwmChannels) vif;

  bit en_monitor   = 1'b1;          // enable  monitor

  bit [NumPwmChannels-1:0] invert;  // invert pulse
  bit [NumPwmChannels-1:0] pwm_en;  // enable/disable channel

  `uvm_object_param_utils_begin(pwm_monitor_cfg#(NumPwmChannels))
    `uvm_field_int(invert, UVM_DEFAULT)
    `uvm_field_int(pwm_en, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : pwm_monitor_cfg
