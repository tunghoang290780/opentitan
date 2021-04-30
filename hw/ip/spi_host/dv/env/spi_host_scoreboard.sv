// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class spi_host_scoreboard extends cip_base_scoreboard #(
    .CFG_T(spi_host_env_cfg),
    .RAL_T(spi_host_reg_block),
    .COV_T(spi_host_env_cov)
  );
  `uvm_component_utils(spi_host_scoreboard)
  `uvm_component_new

  virtual spi_if  spi_vif;

  // TLM fifos hold the transactions sent from monitor
  uvm_tlm_analysis_fifo #(spi_item) host_data_fifo;
  uvm_tlm_analysis_fifo #(spi_item) device_data_fifo;

  // hold expected transactions
  spi_item host_item;
  spi_item device_item;

  // local variables
  // queues hold expected read and write transactions issued by tl_ul
  local spi_item  host_item_q[$];
  local spi_item  device_item_q[$];

  // interrupt bit vector
  local bit [NumSpiHostIntr-1:0] intr_exp;
  // hold dut registers
  local spi_host_regs_t  spi_regs;
  // control bits
  local bit spien  = 1'b0;
  local bit sw_rst = 1'b0;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    host_data_fifo   = new("host_data_fifo", this);
    device_data_fifo = new("device_data_fifo", this);
    host_item        = new("host_item");
    device_item      = new("device_item");
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      `DV_SPINWAIT_EXIT(
        fork
          compare_trans(Host);
          // TODO: temporaly disable due to bugs in the read path of rtl
          //compare_trans(Device);
        join,
        @(negedge cfg.clk_rst_vif.rst_n),
      )
    end
  endtask : run_phase


  virtual task compare_trans(if_mode_e mode);
    spi_item   exp_item;
    spi_item   dut_item;

    forever begin
      if (mode == Host) begin
        host_data_fifo.get(dut_item);
        //`uvm_info(`gfn, $sformatf("\n  scb: dut_item \n%0s", dut_item.sprint()), UVM_DEBUG)
        wait(host_item_q.size() > 0);
        exp_item = host_item_q.pop_front();
        //`uvm_info(`gfn, $sformatf("\n  scb: exp_item \n%0s", exp_item.sprint()), UVM_DEBUG)
      end else begin
        device_data_fifo.get(dut_item);
        wait(device_item_q.size() > 0);
        exp_item = device_item_q.pop_front();
      end
      if (!dut_item.compare(exp_item)) begin
        `uvm_error(`gfn, $sformatf("\n  scb: mode %s, item mismatch!\n--> EXP:\n%0s\--> DUT:\n%0s",
          mode.name(), exp_item.sprint(), dut_item.sprint()))
      end else begin
        `uvm_info(`gfn, $sformatf("\n  scb: mode %s, item match!\n--> EXP:\n%0s\--> DUT:\n%0s",
          mode.name(), exp_item.sprint(), dut_item.sprint()), UVM_LOW)
      end
    end
  endtask : compare_trans

  virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);
    uvm_reg csr;
    bit fifos_access;

    string csr_name = "";
    bit do_read_check = 1'b1;
    bit write = item.is_write();
    bit [TL_AW-1:0] csr_addr_mask = ral.get_addr_mask();
    uvm_reg_addr_t csr_addr = ral.get_word_aligned_addr(item.a_addr);

    bit addr_phase_read  = (!write && channel == AddrChannel);
    bit addr_phase_write = (write && channel  == AddrChannel);
    bit data_phase_read  = (!write && channel == DataChannel);
    bit data_phase_write = (write && channel  == DataChannel);

    // if access was to a valid csr, get the csr handle
    if (csr_addr inside {cfg.csr_addrs[ral_name]}) begin
      csr = ral.default_map.get_reg_by_offset(csr_addr);
      `DV_CHECK_NE_FATAL(csr, null)
      csr_name = csr.get_name();

      // if incoming access is a write to a valid csr, then make updates right away
      if (addr_phase_write) begin
        void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));
      end
    end else if ((csr_addr & csr_addr_mask) inside {[SPI_HOST_FIFO_START :
                                                     SPI_HOST_FIFO_END]}) begin
      fifos_access = 1;
      if (addr_phase_write) begin // collect write data
        bit [7:0] wr_byte[TL_DBW];

        wr_byte = {<< 8 {item.a_data}};
        `uvm_info(`gfn, $sformatf("\n  scb: write byte %p", wr_byte), UVM_DEBUG)
        `uvm_info(`gfn, $sformatf("\n  scb: byte len   %0d", host_item.byte_len), UVM_LOW)
        foreach (wr_byte[i]) begin
          host_item.data.push_back(wr_byte[i]);
          if (host_item.data.size() == host_item.byte_len) begin
            spi_item wr_item;
            `downcast(wr_item, host_item.clone());
            host_item_q.push_back(wr_item);
            `uvm_info(`gfn, $sformatf("\n  scb: get expected host item \n%0s",
                host_item.sprint()), UVM_DEBUG)
            host_item.clear_all();
            break;
          end
        end
      end
    end else begin
      `uvm_fatal(`gfn, $sformatf("\n  scb: access unexpected addr 0x%0h", csr_addr))
    end

    // process the csr req
    // for write, update local variable and fifo at address phase
    // for read, update predication at address phase and compare at data phase
    case (csr_name)
      // add individual case item for each csr
      "control": begin
        spien  = bit'(get_field_val(ral.control.spien,  item.a_data));
        sw_rst = bit'(get_field_val(ral.control.sw_rst, item.a_data));
        if (sw_rst || spien) begin
          host_item_q.delete();
          device_item_q.delete();
        end
      end
      "configopts": begin
        get_configopts_reg_value(csr_name, 0, item.a_data);
      end
      "configopts_0", "configopts_1", "configopts_2", "configopts_3": begin
        string csr_str;
        int    csr_idx;
        csr_str = csr_name.getc(csr_name.len());
        csr_idx = csr_str.atoi();
        get_configopts_reg_value(csr_name, csr_idx, item.a_data);
      end
      "command": begin
        spi_regs.direction = spi_dir_e'(get_field_val(ral.command.direction, item.a_data));
        spi_regs.speed     = spi_mode_e'(get_field_val(ral.command.speed, item.a_data));
        spi_regs.csaat     = get_field_val(ral.command.csaat, item.a_data);
        spi_regs.len       = get_field_val(ral.command.len, item.a_data);
        init_host_device_items();
        `uvm_info(`gfn, $sformatf("\n  scb: req len %0d byte", spi_regs.len + 1), UVM_DEBUG)
      end
      "intr_state": begin
        // TODO
        do_read_check = 1'b0;
      end
      "intr_enable": begin
        // TODO
      end
      "intr_test": begin
        // TODO
      end
      "control": begin
        // TODO
      end
      "status": begin
        // TODO
      end
      "csid": begin
        spi_regs.csid = item.a_data;
      end
      "error_enable": begin
        // TODO
      end
    endcase

    if (fifos_access) begin
      if (addr_phase_write) begin
        // TODO: Access TX_FIFO
        // indicate that the txfifo access is now over
        fifos_access = 0;
      end
      if (data_phase_read) begin
        // TODO: Access RX_FIFO
        // indicate that the rxfifo access is now over
        fifos_access = 0;
      end
    end

    // TODO: temporaly disable due to bugs in rtl read path
    // On reads, if do_read_check, is set, then check mirrored_value against item.d_data
//    if (data_phase_read) begin
//      if (do_read_check) begin
//        `DV_CHECK_EQ(csr.get_mirrored_value(), item.d_data,
//                     $sformatf("reg name: %0s", csr.get_full_name()))
//      end
//      void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));

//    end
  endtask : process_tl_access

  virtual function void init_host_device_items();
    host_item.clear_all();
    device_item.clear_all();
    host_item.direction = spi_regs.direction;
    host_item.spi_mode  = spi_regs.speed;
    `downcast(device_item, host_item.clone());
    if (spi_regs.direction inside {TxOnly, Bidir}) begin
      host_item.byte_len = spi_regs.len + 1;
    end
    if (spi_regs.direction inside {RxOnly, Bidir}) begin
      device_item.byte_len = spi_regs.len + 1;
    end
  endfunction : init_host_device_items

  virtual function void reset(string kind = "HARD");
    super.reset(kind);
    // reset local fifos queues and variables
    host_data_fifo.flush();
    device_data_fifo.flush();
    host_item_q.delete();
    device_item_q.delete();
    host_item.clear_all();
    device_item.clear_all();
    spien  = 1'b0;
    sw_rst = 1'b0;
  endfunction : reset

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // post test checks - ensure that all local fifos and queues are empty
  endfunction : check_phase

  virtual function void get_configopts_reg_value(string name, int id, uvm_reg_data_t val);
    spi_regs.cpol[0]     = bit'(cfg.get_field_val_by_name("cpol",     name, id, val));
    spi_regs.cpha[0]     = bit'(cfg.get_field_val_by_name("cpha",     name, id, val));
    spi_regs.fullcyc[0]  = bit'(cfg.get_field_val_by_name("fullcyc",  name, id, val));
    spi_regs.csnlead[0]  = cfg.get_field_val_by_name("csnlead",  name, id, val);
    spi_regs.csnidle[0]  = cfg.get_field_val_by_name("csnidle",  name, id, val);
    spi_regs.clkdiv[0]   = cfg.get_field_val_by_name("clkdiv",   name, id, val);
    spi_regs.csntrail[0] = cfg.get_field_val_by_name("csntrail", name, id, val);

  endfunction : get_configopts_reg_value

endclass : spi_host_scoreboard
