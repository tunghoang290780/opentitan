// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_base_seq extends dv_base_seq #(
    .REQ         (i2c_item),
    .CFG_T       (i2c_agent_cfg),
    .SEQUENCER_T (i2c_sequencer)
  );
  `uvm_object_utils(i2c_base_seq)
  `uvm_object_new

  // queue monitor requests which ask the re-active driver to response host dut
  i2c_item req_q[$];

  rand bit [7:0] data_q[$];
  rand bit [7:0] rd_data;
  rand bit       do_stretch_clk;
  rand bit       start_flag, stop_flag;

  constraint data_size_c {
    data_q.size() inside {[1:32]};
  }
  constraint do_stretch_clk_c { do_stretch_clk dist { 1 :/ 1, 0 :/ 4}; }

  virtual task body();
    if (cfg.if_mode == Device) begin
      // get seq for agent running in Device mode
      fork
        forever begin
          p_sequencer.req_analysis_fifo.get(req);
          req_q.push_back(req);
        end
        forever begin
          wait(req_q.size > 0);
          req = req_q.pop_front();
          `DV_CHECK_RANDOMIZE_WITH_FATAL(req,
                                           do_stretch_clk == local::do_stretch_clk;
                                           rd_data == local::rd_data;
                                        )
          start_item(req);
          finish_item(req);
          get_response(rsp);
        end
      join
    end else begin
      // get seq for agent running in Host mode
      req = i2c_item::type_id::create("req");
      start_item(req);
      `DV_CHECK_RANDOMIZE_WITH_FATAL(req,
                                       addr dist { cfg.target_addr0 :/ 1, cfg.target_addr1 :/ 1 };
                                       data_q.size() == local::data_q.size();
                                       foreach (data_q[i]) { data_q[i] == local::data_q[i]; }
                                       start == local::start_flag;
                                       stop == local::stop_flag;
                                     )
      finish_item(req);
      get_response(rsp);
    end
  endtask : body

endclass : i2c_base_seq
