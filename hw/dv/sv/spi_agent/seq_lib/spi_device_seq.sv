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
  spi_dir_e        direction;
  spi_mode_e       spi_mode;
  uint             byte_len = 0;

  virtual task body();
    if (item_type == SpiTransNormal && byte_len > 0) begin
      req = spi_item::type_id::create("req");
      start_item(req);
      `DV_CHECK_RANDOMIZE_WITH_FATAL(req,
                                      item_type   == local::item_type;
                                      data.size() == local::byte_len;
                                    )
      req.direction = direction;
      req.spi_mode  = spi_mode;
      finish_item(req);
      `uvm_info(`gfn, $sformatf("\n  spi_device_seq: finish req \n%0s", req.sprint()), UVM_LOW)
    end
  endtask : body
  
endclass : spi_device_seq