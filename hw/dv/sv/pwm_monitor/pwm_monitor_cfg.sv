// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class pwm_monitor_cfg #(
  parameter int NumPwmChannels = 6
) extends dv_base_agent_cfg;

  bit en_monitor   = 1'b1;                      // enable  monitor
  bit [NumPwmChannels-1:0]           invert;    // invert pulse
  bit [NumPwmChannels-1:0]           pwm_en;    // enable/disable channel
  bit                                cntr_en;   // enable/disable counters

  // duty_cycle multireg
  bit [NumPwmChannels-1:0][15:0]     duty_cycle_a;
  bit [NumPwmChannels-1:0][15:0]     duty_cycle_b;
  // blink_param multireg
  bit [NumPwmChannels-1:0][15:0]     blink_param_x;
  bit [NumPwmChannels-1:0][15:0]     blink_param_y;

  pwm_mode_e [NumPwmChannels-1:0]    pwm_mode;
  bit [NumPwmChannels-1:0][15:0]     phase_delay;
  bit [16:0]                         pulse_cycle;
  int                                num_pulses;

  // interface handle used by monitor
  virtual pwm_if#(NumPwmChannels) vif;

  `uvm_object_param_utils_begin(pwm_monitor_cfg#(NumPwmChannels))
    `uvm_field_int(pwm_en,        UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(invert,        UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(duty_cycle_a,  UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(duty_cycle_b,  UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(blink_param_x, UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(blink_param_y, UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(phase_delay,   UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
    `uvm_field_int(pulse_cycle,   UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE | UVM_NOPACK)
  `uvm_object_utils_end

  `uvm_object_new

  virtual function string convert2string();
    string str = "";
    super.convert2string();
    str = $sformatf("\n>>> pwm_monitor_cfg");
    str = {str, $sformatf("\n  pwm_en   %b", pwm_en)};
    str = {str, $sformatf("\n  cntr_en  %b",  cntr_en)};
    str = {str, $sformatf("\n  invert   %b",  invert)};
    return str;
  endfunction : convert2string

endclass : pwm_monitor_cfg
