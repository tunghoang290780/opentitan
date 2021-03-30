// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "uvm_macros.svh"

import i2c_agent_pkg::*;
import dv_utils_pkg::*;

interface i2c_if;
  logic clk_i;
  logic rst_ni;

  // standard i2c interface pins
  logic scl_i;
  logic sda_i;
  logic scl_o;
  logic sda_o;

  // muxes routes signals from vif to monitor depending on the operated mode of agent
  if_mode_e if_mode;
  logic mscl_i;
  logic msda_i;
  logic mscl_o;
  logic msda_o;

  always_comb begin
    // agent in device mode (default)
    {mscl_i, msda_i} = {scl_i, sda_i};      // DUT   (host)   req
    {mscl_o, msda_o} = {scl_o, sda_o};      // Agent (device) rsp
    if (if_mode == Host) begin
      // agent in Host mode
      {mscl_i, msda_i} = {scl_o, sda_o};    // DUT   (target) rsp
      {mscl_o, msda_o} = {scl_i, sda_i};    // Agent (host)   req
    end
  end
  //---------------------------------
  // common tasks
  //---------------------------------
  task automatic wait_for_dly(int dly);
    repeat (dly) @(posedge clk_i);
  endtask : wait_for_dly

  task automatic control_bus(bit do_assert = 1'b1);
    if (do_assert) begin
      scl_o = 1'b1;
      sda_o = 1'b1;
    end else begin
      scl_o = 1'b0;
      sda_o = 1'b0;
    end
  endtask : control_bus

  task automatic wait_for_host_start(ref timing_cfg_t tc);
    forever begin
      @(negedge msda_i);
      wait_for_dly(tc.tHoldStart);
      @(negedge mscl_i);
      wait_for_dly(tc.tClockStart);
      break;
    end
  endtask: wait_for_host_start

  task automatic wait_for_host_rstart(ref timing_cfg_t tc,
                                      output bit rstart);
    rstart = 1'b0;
    forever begin
      @(posedge mscl_i && msda_i);
      wait_for_dly(tc.tSetupStart);
      @(negedge msda_i);
      if (mscl_i) begin
        wait_for_dly(tc.tHoldStart);
        @(negedge mscl_i) begin
          rstart = 1'b1;
          break;
        end
      end
    end
  endtask: wait_for_host_rstart

  task automatic wait_for_host_stop(ref timing_cfg_t tc,
                                    output bit stop);
    stop = 1'b0;
    forever begin
      @(posedge mscl_i);
      @(posedge msda_i);
      if (mscl_i) begin
        stop = 1'b1;
        break;
      end
    end
    wait_for_dly(tc.tHoldStop);
  endtask: wait_for_host_stop

  task automatic wait_for_host_stop_or_rstart(timing_cfg_t tc,
                                              output bit   rstart,
                                              output bit   stop);
    fork
      begin : iso_fork
        fork
          wait_for_host_stop(tc, stop);
          wait_for_host_rstart(tc, rstart);
        join_any
        disable fork;
      end : iso_fork
    join
  endtask: wait_for_host_stop_or_rstart

  task automatic wait_for_host_ack(ref timing_cfg_t tc);
    @(negedge msda_i);
    wait_for_dly(tc.tClockLow + tc.tSetupBit);
    forever begin
      @(posedge mscl_i);
      if (!msda_i) begin
        wait_for_dly(tc.tClockPulse);
        break;
      end
    end
    wait_for_dly(tc.tHoldBit);
  endtask: wait_for_host_ack

  task automatic wait_for_host_nack(ref timing_cfg_t tc);
    @(negedge msda_i);
    wait_for_dly(tc.tClockLow + tc.tSetupBit);
    forever begin
      @(posedge mscl_i);
      if (msda_i) begin
        wait_for_dly(tc.tClockPulse);
        break;
      end
    end
    wait_for_dly(tc.tHoldBit);
  endtask: wait_for_host_nack

  task automatic wait_for_host_ack_or_nack(timing_cfg_t tc,
                                           output bit   ack,
                                           output bit   nack);
    ack = 1'b0;
    nack = 1'b0;
    fork
      begin : iso_fork
        fork
          begin
            wait_for_host_ack(tc);
            ack = 1'b1;
          end
          begin
            wait_for_host_nack(tc);
            nack = 1'b1;
          end
        join_any
        disable fork;
      end : iso_fork
    join
  endtask: wait_for_host_ack_or_nack

  task automatic wait_for_device_ack(ref timing_cfg_t tc);
    @(negedge msda_o && mscl_o);
    wait_for_dly(tc.tSetupBit);
    forever begin
      @(posedge mscl_i);
      if (!msda_o) begin
        wait_for_dly(tc.tClockPulse);
        break;
      end
    end
    wait_for_dly(tc.tHoldBit);
  endtask: wait_for_device_ack

  // the `sda_unstable` interrupt is asserted if, when receiving data or ,
  // ack pulse (device_send_ack) the value of the target sda signal does not
  // remain constant over the duration of the scl pulse.
  task automatic device_send_bit(ref timing_cfg_t tc,
                                 input bit bit_i);
    sda_o = 1'b1;
    wait_for_dly(tc.tClockLow);
    sda_o = bit_i;
    wait_for_dly(tc.tSetupBit);
    @(posedge mscl_i);
    // flip sda_target2host during the clock pulse of scl_host2target causes sda_unstable irq
    sda_o = ~sda_o;
    wait_for_dly(tc.tSdaUnstable);
    sda_o = ~sda_o;
    wait_for_dly(tc.tClockPulse + tc.tHoldBit - tc.tSdaUnstable);
    // not release/change sda_o until host clock stretch passes
    if (tc.enbTimeOut) wait(!mscl_i);
    sda_o = 1'b1;
  endtask: device_send_bit

  task automatic device_send_ack(ref timing_cfg_t tc);
    device_send_bit(tc, 1'b0); // special case
  endtask: device_send_ack

  // when the I2C module is in transmit mode, `scl_interference` interrupt
  // will be asserted if the IP identifies that some other device (host or target) on the bus
  // is forcing scl low and interfering with the transmission.
  task automatic device_stretch_host_clk(ref timing_cfg_t tc,
                                         input bit en_interference = 1'b1);
    if (en_interference && tc.enbTimeOut && tc.tTimeOut > 0) begin
      wait_for_dly(tc.tClockLow + tc.tSetupBit + tc.tSclInterference - 1);
      scl_o = 1'b0;
      wait_for_dly(tc.tStretchHostClock - tc.tSclInterference + 1);
      scl_o = 1'b1;
    end else begin
      scl_o = 1'b0;
      wait_for_dly(tc.tStretchHostClock);
      scl_o = 1'b1;
    end
  endtask : device_stretch_host_clk

  // when the I2C module is in transmit mode, `msda_interference` interrupt
  // will be asserted if the IP identifies that some other device (host or target) on the bus
  // is forcing sda low and interfering with the transmission.
  task automatic get_bit_data(string src = "host",
                              ref timing_cfg_t tc,
                              output bit bit_o);
    wait_for_dly(tc.tClockLow + tc.tSetupBit);
    @(posedge mscl_i);
    if (src == "host") begin // host transmits data (addr/wr_data)
      bit_o = msda_i;
      // force sda_target2host low during the clock pulse of scl_host2target
      sda_o = 1'b0;
      wait_for_dly(tc.tSdaInterference);
      sda_o = 1'b1;
      wait_for_dly(tc.tClockPulse + tc.tHoldBit - tc.tSdaInterference);
    end else begin // target transmits data (rd_data)
      bit_o = sda_o;
      wait_for_dly(tc.tClockPulse + tc.tHoldBit);
    end
  endtask: get_bit_data

  //----------------------------------------------------------
  // TODO: tasks support agent operating in Host mode
  //----------------------------------------------------------
  task automatic host_control_bus(ref timing_cfg_t tc,
                                  input drv_type_e drv_type,
                                  input bit bit_i);
    case (drv_type)
      HostStart: begin
        scl_o = 1'b1;
        sda_o = 1'b1;
        wait_for_dly(tc.tSetupStart);
        sda_o = 1'b0;
        wait_for_dly(tc.tHoldStart);
        scl_o = 1'b0;
        wait_for_dly(tc.tClockStart);
      end
      HostAckOrNoAck: begin
        // bit_i = 0/1: Ack/NoAck
        control_bus(.do_assert(1'b0));
        wait_for_dly(tc.tSetupBit);
        sda_o = bit_i;
        wait_for_dly(tc.tClockPulse);
        scl_o = 1'b1;
        wait_for_dly(tc.tHoldBit);
        scl_o = 1'b0;
      end
      HostStopOrRStart: begin
        // bit_i = 0/1: RStart/Stop
        control_bus(.do_assert(1'b0));
        wait_for_dly(tc.tClockStop);
        scl_o = 1'b1;
        wait_for_dly(tc.tSetupStop);
        sda_o = bit_i;
        if (bit_i) begin
          wait_for_dly(tc.tHoldStop);
        end
      end
      HostData: begin
        // also used for address bits and r/w bit
        scl_o = 1'b0;
        wait_for_dly(tc.tClockLow);
        sda_o = bit_i;
        `uvm_info("i2c_if", $sformatf("\n  end of tClockLow, sda_o %b", sda_o), UVM_LOW)
        wait_for_dly(tc.tSetupBit);
        scl_o = 1'b1;
        wait_for_dly(tc.tClockPulse);
        scl_o = 1'b0;
        wait_for_dly(tc.tHoldBit);
      end
    endcase
  endtask : host_control_bus

endinterface : i2c_if
