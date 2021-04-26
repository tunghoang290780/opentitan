// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class spi_device_driver extends spi_driver;
  `uvm_component_utils(spi_device_driver)
  `uvm_component_new

  bit rx_data_q[4][$];

  virtual task reset_signals();
    forever begin
      @(negedge cfg.vif.rst_n);
      `uvm_info(`gfn, "\n  spi_device_driver: in reset progress", UVM_LOW)
      under_reset = 1'b1;
      for (int i = 0; i < 4; i++) rx_data_q[i].delete();
      @(posedge cfg.vif.rst_n);
      under_reset = 1'b0;
      `uvm_info(`gfn, "\n  spi_device_driver: out of reset", UVM_LOW)
    end
  endtask

  virtual task get_and_drive();
    spi_item req, rsp;

    forever begin
      wait(!under_reset);
      seq_item_port.get_next_item(req);
      $cast(rsp, req.clone());
      rsp.set_id_info(req);
      `uvm_info(`gfn, $sformatf("\n  spi_device_driver: get req_item:\n%0s",
          req.sprint()), UVM_LOW)
      fork
        drive_rx_item(req);
        drive_tx_item(req);
      join
      `uvm_info(`gfn, "\n  spi_device_driver: item done, send rsp_item", UVM_LOW)
      seq_item_port.item_done(rsp);
    end
  endtask : get_and_drive

  virtual task drive_rx_item(spi_item item);
    bit [3:0] rx_data;
    uint max_bits = get_bit_len_per_channel(cfg.spi_mode, item.byte_len);
    for (int nbits = 0; nbits < max_bits; nbits++) begin
      cfg.wait_sck_edge(SamplingEdge);
      `uvm_info(`gfn, $sformatf("\n  spi_device_driver: get SamplingEdge"), UVM_LOW)
      get_rx_sio(cfg.spi_mode, rx_data);
      `uvm_info(`gfn, $sformatf("\n  spi_device_driver: rx_data %b", rx_data), UVM_LOW)
    end
  endtask : drive_rx_item

  virtual task drive_tx_item(spi_item item);
    bit [7:0] tx_data;
    uint max_bits = get_bit_len_per_channel(cfg.spi_mode, item.byte_len);

    for (int nbits = 0; nbits < max_bits; nbits++) begin
      cfg.wait_sck_edge(SamplingEdge);
      tx_data = item.data.pop_front();
      `uvm_info(`gfn, $sformatf("\n  spi_device_driver: get SamplingEdge"), UVM_LOW)
      send_tx_sio(cfg.spi_mode, tx_data);
      `uvm_info(`gfn, $sformatf("\n  spi_device_driver: rx_data %b", rx_data), UVM_LOW)
    end
  endtask : drive_tx_item

  virtual task send_tx_sio(spi_mode_e mode, input bit [3:0] tx_data);
    unique case (mode)
      Standard: begin
        cfg.vif.sio[1] = tx_data[1];
      end
      Dual: begin
        cfg.vif.sio[1:0] = tx_data[1:0];
      end
      Quad: begin
        cfg.vif.sio = tx_data;
      end
      RsvdSpd: begin
        cfg.vif.sio = 4'bzzzz;
      end
    endcase
  endtask : send_tx_sio

  virtual task get_rx_sio(spi_mode_e mode, output bit [3:0] rx_data);
    unique case (mode)
      Standard: begin
        rx_data[3:1] = 3'bzz;
        rx_data[0]   = cfg.vif.sio[1];
      end
      Dual: begin
        rx_data[3:2] = 2'bzz;
        rx_data[1:0] = cfg.vif.sio[1:0];
      end
      Quad: begin
        rx_data = cfg.vif.sio;
      end
      RsvdSpd: begin
        rx_data = 4'bzzzz;
      end
    endcase
    for (int i = 0; i < 4;  i++) begin
      rx_data_q[i].push_back(rx_data[i]);
      if (rx_data_q[i].size() == 8) begin
        `uvm_info(`gfn, $sformatf("\n  spi_device_driver: channel %0d, rx_data %p",
            i, rx_data_q[i]), UVM_LOW)
        rx_data_q[i].delete();
      end
    end
  endtask : get_rx_sio

  function int get_bit_len_per_channel(spi_mode_e mode, uint byte_len);
    uint bit_len;
    case (mode)
      Standard: bit_len = byte_len*8;
      Dual:     bit_len = byte_len*4;
      Quad:     bit_len = byte_len*2;
      default:  bit_len = 0;
    endcase
    return bit_len;
  endfunction : get_bit_len_per_channel

endclass : spi_device_driver
