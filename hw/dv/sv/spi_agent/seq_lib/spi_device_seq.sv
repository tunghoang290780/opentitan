// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// --------------------
// Device sequence
// --------------------
class spi_device_seq extends spi_base_seq;
  `uvm_object_utils(spi_device_seq)
  `uvm_object_new

  spi_trans_type_e item_type;
  uint byte_len = 0;

  virtual task body();
    if (item_type inside {SpiTransWrite, SpiTransRead, SpiTransIdle} && byte_len > 0) begin
      // if mode = Dual/Quad then adopting re-active slave agent (half duplex)
      `uvm_info(`gfn, $sformatf("\n  spi_device_seq: spi_mode %s",   cfg.spi_mode.name()), UVM_LOW)
      `uvm_info(`gfn, $sformatf("\n  spi_device_seq: item_type %s",  item_type.name()), UVM_LOW)
      `uvm_info(`gfn, $sformatf("\n  spi_device_seq: byte_len %0d", byte_len), UVM_LOW)
      `uvm_info(`gfn, $sformatf("\n    full duplex: %s",  cfg.spi_mode.name()), UVM_LOW)
      req = spi_item::type_id::create("req");
      `uvm_info(`gfn, $sformatf("\n    req_item created"), UVM_LOW)
      start_item(req);
      `uvm_info(`gfn, $sformatf("\n    req_item started"), UVM_LOW)
      `DV_CHECK_RANDOMIZE_WITH_FATAL(req,
                                       item_type   == local::item_type;
                                       byte_len    == local::byte_len;
                                       data.size() == local::byte_len;
                                    )
      `uvm_info(`gfn, $sformatf("\n    req_item is sent to device driver \n%0s", req.sprint()), UVM_LOW)
      finish_item(req);
      `uvm_info(`gfn, $sformatf("\n    req_item finished"), UVM_LOW)
      get_response(rsp);
    end
  endtask : body
  
endclass : spi_device_seq