// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package spi_host_env_pkg;
  // dep packages
  import uvm_pkg::*;
  import top_pkg::*;
  import dv_utils_pkg::*;
  import csr_utils_pkg::*;
  import dv_lib_pkg::*;
  import tl_agent_pkg::*;
  import spi_agent_pkg::*;
  import cip_base_pkg::*;
  import dv_base_reg_pkg::*;
  import spi_host_ral_pkg::*;

  // parameters
  parameter uint SPI_HOST_NUM_CS      = spi_host_reg_pkg::NumCS;
  parameter uint SPI_HOST_TX_DEPTH    = spi_host_reg_pkg::TxDepth;
  parameter uint SPI_HOST_RX_DEPTH    = spi_host_reg_pkg::RxDepth;
  parameter bit  SPI_HOST_BYTEORDER   = spi_host_reg_pkg::ByteOrder;
  parameter uint SPI_HOST_BLOCK_AW    = spi_host_reg_pkg::BlockAw;
  parameter uint SPI_HOST_FIFO_BASE   = spi_host_reg_pkg::SPI_HOST_DATA_OFFSET;
  parameter uint SPI_HOST_FIFO_END    = (SPI_HOST_FIFO_BASE - 1) +
                                        spi_host_reg_pkg::SPI_HOST_DATA_SIZE;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // types
  typedef enum int {
    SpiHostError     = 0,
    SpiHostEvent     = 1,
    NumSpiHostIntr   = 2
  } spi_host_intr_e;

  typedef enum int {
    TxFifo   = 0,
    RxFifo   = 1,
    AllFifos = 2
  } spi_host_fifo_e;

  // spi config
  typedef struct {
    // csid register
    rand bit [31:0] csid;
    // control register fields
    rand bit [8:0]  tx_watermark;
    rand bit [6:0]  rx_watermark;
    rand bit        passthru;
    // configopts register fields
    rand bit        cpol[SPI_HOST_NUM_CS-1:0];
    rand bit        cpha[SPI_HOST_NUM_CS-1:0];
    rand bit        fullcyc[SPI_HOST_NUM_CS-1:0];
    rand bit [3:0]  csnlead[SPI_HOST_NUM_CS-1:0];
    rand bit [3:0]  csntrail[SPI_HOST_NUM_CS-1:0];
    rand bit [3:0]  csnidle[SPI_HOST_NUM_CS-1:0];
    rand bit [15:0] clkdiv[SPI_HOST_NUM_CS-1:0];
    // command register fields
    rand spi_dir_e  direction;
    rand spi_mode_e speed;
    rand bit        csaat;
    rand bit [8:0]  len;
  } spi_regs_t;

  // functions

  // package sources
  `include "spi_host_seq_cfg.sv"
  `include "spi_host_env_cfg.sv"
  `include "spi_host_env_cov.sv"
  `include "spi_host_virtual_sequencer.sv"
  `include "spi_host_scoreboard.sv"
  `include "spi_host_env.sv"
  `include "spi_host_vseq_list.sv"

endpackage : spi_host_env_pkg
