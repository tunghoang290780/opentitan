// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package spi_agent_pkg;
  // dep packages
  import uvm_pkg::*;
  import dv_utils_pkg::*;
  import dv_lib_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // parameter
  parameter uint MAX_CS = 4;      // set to the maximum valid value
  parameter uint BYTE_ORDER = 1;  // must be same as ByteOrder defined in spi_host_reg_pkg

  // transaction type
  typedef enum {
    SpiTransNormal,    // normal SPI trans
    SpiTransSckNoCsb,  // bad SPI trans with clk but no sb
    SpiTransCsbNoScb   // bad SPI trans with csb but no clk
  } spi_trans_type_e;

  // sck edge type - used by driver and monitor
  // to wait for the right edge based on CPOL / CPHA
  typedef enum {
    LeadingEdge,
    DrivingEdge,
    SamplingEdge
  } sck_edge_type_e;

  // spi mode
  typedef enum logic [1:0] {
    Standard = 2'b00,  // Full duplex, tx: sio[0], rx: sio[1]
    Dual     = 2'b01,  // Half duplex, tx and rx: sio[1:0]
    Quad     = 2'b10,  // Half duplex, tx and rx: sio[3:0]
    RsvdSpd  = 2'b11   // RFU
  } spi_mode_e;

  // spi direction
  typedef enum logic [1:0] {
    Dummy    = 2'b00,
    RxOnly   = 2'b01,
    TxOnly   = 2'b10,
    Bidir    = 2'b11
  } spi_dir_e;

  // forward declare classes to allow typedefs below
  typedef class spi_item;
  typedef class spi_agent_cfg;

  // package sources
  `include "spi_agent_cfg.sv"
  `include "spi_agent_cov.sv"
  `include "spi_item.sv"
  `include "spi_monitor.sv"
  `include "spi_driver.sv"
  `include "spi_host_driver.sv"
  `include "spi_device_driver.sv"
  `include "spi_sequencer.sv"
  `include "spi_agent.sv"
  `include "seq_lib/spi_seq_list.sv"

endpackage: spi_agent_pkg
