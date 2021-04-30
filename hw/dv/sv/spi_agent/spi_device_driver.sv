// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class spi_device_driver extends spi_driver;
  `uvm_component_utils(spi_device_driver)
  `uvm_component_new

  virtual task reset_signals();
    forever begin
      @(negedge cfg.vif.rst_n);
      `uvm_info(`gfn, "\n  dev_drv: in reset progress", UVM_DEBUG)
      under_reset = 1'b1;
      @(posedge cfg.vif.rst_n);
      under_reset = 1'b0;
      `uvm_info(`gfn, "\n  dev_drv: out of reset", UVM_DEBUG)
    end
  endtask

  virtual task get_and_drive();
    spi_item req, rsp;

    forever begin
      wait(!under_reset && !cfg.vif.csb[int'(cfg.csid)]);
      seq_item_port.get_next_item(req);
      `uvm_info(`gfn, $sformatf("\n  dev_drv: sequence type %s, mode %s, direction %s",
          req.item_type.name(), cfg.spi_mode.name(), cfg.direction.name()), UVM_LOW)
      fork
        begin: iso_fork
          fork
            fork
              get_tx_item(req);
              send_rx_item(req);
              get_dummy_item(req);
            join
            drive_bus_to_highz();
            driver_bus_for_reset();
          join_any
          disable fork;
        end: iso_fork
      join
      seq_item_port.item_done();
      `uvm_info(`gfn, "\n  dev_drv: item done", UVM_LOW)
    end
  endtask : get_and_drive

  virtual task get_dummy_item(spi_item item);
    if (cfg.direction inside {Dummy}) begin
      uint max_sampling_edges = cfg.get_num_sck_edges();
      for (int i = 0; i < max_sampling_edges; i++) begin
        cfg.wait_sck_edge(SamplingEdge);
      end
      `uvm_info(`gfn, $sformatf("\n  dev_drv: wait %0d dummy cycles",
          max_sampling_edges), UVM_DEBUG)
    end
  endtask : get_dummy_item

  virtual task get_tx_item(spi_item item);
    if (cfg.direction inside {TxOnly, Bidir}) begin
      bit sio_bits[];
      bit bits_q[$];
      spi_item wr_item;
      uint max_sampling_edges = cfg.get_num_sck_edges();

      `downcast(wr_item, item.clone());
      `uvm_info(`gfn, $sformatf("\n  dev_drv: get_tx_item, expect receiving %0d bits from dut",
          max_sampling_edges), UVM_LOW)
      for (int i = 0; i < max_sampling_edges; i++) begin
        `uvm_info(`gfn, $sformatf("\n  dev_drv: iteration %0d/%0d",
            i + 1, max_sampling_edges), UVM_LOW)
        cfg.wait_sck_edge(SamplingEdge);
        sio_bits.delete();
        cfg.vif.get_data_from_sio(cfg.spi_mode, sio_bits);
        `uvm_info(`gfn, $sformatf("\n  dev_drv: sample data bit[%0d] %b",
            max_sampling_edges-1-i, sio_bits[0]), UVM_LOW)
        bits_q = {>> {bits_q, sio_bits}};
      end
      wr_item.data.delete();
      wr_item.data = {>> 8 {bits_q}};
      `uvm_info(`gfn, $sformatf("\n  dev_drv: get item from dut \n%0s",
          wr_item.sprint()), UVM_LOW)
    end
  endtask : get_tx_item

  virtual task send_rx_item(spi_item item);
    if (cfg.direction inside {RxOnly, Bidir}) begin
      logic [3:0] sio_bits;
      bit bits_q[$];
      int max_tx_bits;

      if (cfg.byte_order) cfg.swap_byte_order(item.data);
      bits_q = {>> 1 {item.data}};
      max_tx_bits = cfg.get_sio_size();
      `uvm_info(`gfn, $sformatf("\n  dev_drv: send_rx_item, return %0d bits to dut",
          bits_q.size()), UVM_DEBUG)
      while (bits_q.size() > 0) begin
        for (int i = 0; i < 4; i++) begin
          sio_bits[i] = (i < max_tx_bits) ? bits_q.pop_front() : 1'bz;
        end
        send_data_to_sio(cfg.spi_mode, sio_bits); // driver data early
        `uvm_info(`gfn, $sformatf("\n  dev_drv: assert data bit[%0d] %b",
            bits_q.size(), sio_bits[0]), UVM_DEBUG)
        if (bits_q.size() > 0) cfg.wait_sck_edge(DrivingEdge);
      end
      `uvm_info(`gfn, $sformatf("\n  dev_drv: send item to dut \n%0s", item.sprint()), UVM_DEBUG)
    end
  endtask : send_rx_item

  virtual task send_data_to_sio(ref spi_mode_e mode, input logic [3:0] sio_bits);
    unique case (mode)
      Standard: cfg.vif.sio[1]   <= sio_bits[0];
      Dual:     cfg.vif.sio[1:0] <= sio_bits[1:0];
      Quad:     cfg.vif.sio      <= sio_bits;
    endcase
  endtask : send_data_to_sio
  
  virtual task drive_bus_to_highz();
    @(posedge cfg.vif.csb[int'(cfg.csid)]);
    case (cfg.spi_mode)
      Standard: cfg.vif.sio[1]   = 1'bz;
      Dual:     cfg.vif.sio[1:0] = 2'bz;
      default:  cfg.vif.sio      = 4'bzzzz;   // including Quad SPI mode
    endcase
    `uvm_info(`gfn, "\n  dev_drv: drive_bus_to_highz is done", UVM_DEBUG)
  endtask : drive_bus_to_highz

  virtual task driver_bus_for_reset();
    @(negedge cfg.vif.rst_n);
    cfg.vif.sio = 4'bzzzz;
    `uvm_info(`gfn, "\n  dev_drv: driver_bus_for_reset is done", UVM_DEBUG)
  endtask : driver_bus_for_reset
  
endclass : spi_device_driver
