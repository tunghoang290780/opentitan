// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class spi_host_base_vseq extends cip_base_vseq #(
    .RAL_T               (spi_host_reg_block),
    .CFG_T               (spi_host_env_cfg),
    .COV_T               (spi_host_env_cov),
    .VIRTUAL_SEQUENCER_T (spi_host_virtual_sequencer)
  );
  `uvm_object_utils(spi_host_base_vseq)
  `uvm_object_new

  // local variables
  local dv_base_reg     base_reg;
  // spi registers
  rand spi_regs_t       spi_regs;
  // random variables
  rand uint             num_runs;
  rand uint             num_wr_bytes;
  rand uint             num_rd_bytes;
  rand uint             tx_fifo_access_dly;
  rand uint             rx_fifo_access_dly;
  rand uint             clear_intr_dly;
  // FIFO: address used to access fifos
  rand bit [TL_AW:0]    fifo_baddr;
  rand bit [7:0]        data_q[$];

  semaphore             rxtx_atomic = new(1);

  // constraints for simulation loops
  constraint num_trans_c {
    num_trans inside {[cfg.seq_cfg.host_spi_min_trans : cfg.seq_cfg.host_spi_max_trans]};
  }
  constraint num_runs_c {
    num_runs inside {[cfg.seq_cfg.host_spi_min_runs : cfg.seq_cfg.host_spi_max_runs]};
  }
  constraint num_wr_bytes_c {
    num_wr_bytes inside {[cfg.seq_cfg.host_spi_min_num_wr_bytes :
                          cfg.seq_cfg.host_spi_max_num_wr_bytes]};
  }
  constraint num_rd_bytes_c {
    num_rd_bytes inside {[cfg.seq_cfg.host_spi_min_num_rd_bytes :
                          cfg.seq_cfg.host_spi_max_num_rd_bytes]};
  }
  // contraints for fifos
  constraint fifo_baddr_c {
    fifo_baddr inside {[SPI_HOST_FIFO_BASE : SPI_HOST_FIFO_END]};
  }

  constraint intr_dly_c {
    clear_intr_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
  }
  constraint fifo_dly_c {
    rx_fifo_access_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
    tx_fifo_access_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
  }
  constraint spi_regs_c {
    // csid reg
      spi_regs.csid inside {[0 : SPI_HOST_NUM_CS-1]};
    // control reg
      spi_regs.tx_watermark dist {
        [0:7]   :/ 1,
        [8:15]  :/ 3,
        [16:31] :/ 2,
        [32:cfg.seq_cfg.host_spi_max_txwm] :/ 1
      };
      spi_regs.rx_watermark dist {
        [0:7]   :/ 1,
        [8:15]  :/ 3,
        [16:31] :/ 2,
        [32:cfg.seq_cfg.host_spi_max_rxwm] :/ 1
      };
      spi_regs.passthru dist {
        1'b0 :/ 1,
        1'b1 :/ 0   // TODO: currently disable passthru mode until specification is updated
      };
    // configopts regs
      foreach (spi_regs.cpol[i]) {
        spi_regs.cpol[i] dist {
          1'b0 :/ 1,     // TODO: hardcode for debug
          1'b1 :/ 0
        };
      }
      foreach (spi_regs.cpha[i]) {
        spi_regs.cpha[i] dist {
          1'b0 :/ 1,     // TODO: hardcode for debug
          1'b1 :/ 0
        };
      }
      foreach (spi_regs.csnlead[i]) {
        spi_regs.csnlead[i] inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                     cfg.seq_cfg.host_spi_max_csn_latency]};
      }
      foreach (spi_regs.csntrail[i]) {
        spi_regs.csntrail[i] inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                      cfg.seq_cfg.host_spi_max_csn_latency]};
      }
      foreach (spi_regs.csnidle[i]) {
        spi_regs.csnidle[i] inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                     cfg.seq_cfg.host_spi_max_csn_latency]};
      }
      foreach (spi_regs.clkdiv[i]) {
        spi_regs.clkdiv[i] inside {[cfg.seq_cfg.host_spi_min_clkdiv :
                                    cfg.seq_cfg.host_spi_max_clkdiv]};
      }
    // command reg
      spi_regs.len inside {[cfg.seq_cfg.host_spi_min_len : cfg.seq_cfg.host_spi_max_len]};
      spi_regs.speed dist {
        Standard :/ 2,
        Dual     :/ 0,  // TODO: hardcode Dual=0 for debug
        Quad     :/ 0   // TODO: hardcode Dual=0 for debug
      };
      if (spi_regs.speed == Standard) {
        spi_regs.direction dist {Dummy :/ 0, Bidir :/ 4}; // TODO: hardcode Dummy=0 for debug
      } else {
        spi_regs.direction dist {Dummy :/ 0, TxOnly :/ 4, RxOnly :/ 4};
      }
  }

  virtual task body();
    initialization();
    `DV_CHECK_RANDOMIZE_FATAL(this)
    program_spi_host_regs();
    print_spi_host_regs();
    activate_spi_host();
    `uvm_info(`gfn, "\n  base_vseq, active spi_host channels, start rx/tx", UVM_LOW)
    write_tx_data();
  endtask : body

  virtual task bk_body();
    initialization();

    rxtx_atomic = new(1);
    for (int trans = 0; trans < num_trans; trans++) begin
      `uvm_info(`gfn, $sformatf("\n--> running tran. %0d/%0d", trans, num_trans), UVM_LOW)
      `DV_CHECK_RANDOMIZE_FATAL(this)
      program_spi_host_regs();
      print_spi_host_regs();
      activate_spi_host();
      `uvm_info(`gfn, "\n  base_vseq, active spi_host channels, start rx/tx", UVM_LOW)
      fork
        begin
          //rxtx_atomic.get(1);
          write_tx_data();
          //rxtx_atomic.put(1);
        end
        begin
          //rxtx_atomic.get(1);
          //read_rx_data();
          //cfg.clk_rst_vif.wait_clks(10);
          //rxtx_atomic.put(1);
        end
      join
      wait_for_fifos_empty();
    end
  endtask : bk_body

  virtual task pre_start();
    // sync monitor and scoreboard setting
    cfg.m_spi_agent_cfg.en_monitor_checks = cfg.en_scb;
    `uvm_info(`gfn, $sformatf("\n  base_vseq, %s monitor and scoreboard",
        cfg.en_scb ? "enable" : "disable"), UVM_DEBUG)
    num_runs.rand_mode(0);
    num_trans_c.constraint_mode(0);
    super.pre_start();
  endtask : pre_start

  virtual task initialization();
    wait(cfg.m_spi_agent_cfg.vif.rst_n);
    `uvm_info(`gfn, "\n  base_vseq, out of reset", UVM_LOW)
    spi_host_init();
    spi_agent_init();
    `uvm_info(`gfn, "\n  base_vseq, initialization is completed", UVM_LOW)
  endtask : initialization

  // setup basic spi_host features
  virtual task spi_host_init();
    bit [TL_DW-1:0] intr_state;

    // reset spit_host dut
    ral.control.sw_rst.set(1'b1);
    csr_update(ral.control);
    // make sure data completely drained from fifo then release reset
    wait_for_fifos_empty();
    ral.control.sw_rst.set(1'b0);
    csr_update(ral.control);
    // enable then clear interrupts
    csr_wr(.ptr(ral.intr_enable), .value({TL_DW{1'b1}}));
    csr_rd(.ptr(ral.intr_state), .value(intr_state));
    csr_wr(.ptr(ral.intr_state), .value(intr_state));
  endtask : spi_host_init

  virtual task spi_agent_init();
    // spi_agent is configured in the Denive mode
    spi_device_seq m_spi_device_seq;
    m_spi_device_seq = spi_device_seq::type_id::create("m_spi_device_seq");
    `uvm_info(`gfn, "\n  base_vseq, start spi_device_seq", UVM_LOW)
    fork
      m_spi_device_seq.start(p_sequencer.spi_host_sequencer_h);
    join_none
  endtask : spi_agent_init

  virtual task activate_spi_host();
    // update spi_agent regs
    update_spi_agent_regs();
  endtask : activate_spi_host

  virtual task program_spi_host_regs();
    // IMPORTANT: configopt regs must be programmed before command reg
    program_configopt_regs();
    program_command_reg();
    program_control_reg();
  endtask : program_spi_host_regs

  virtual task program_csid_reg();
    // enable one of CS lines
    csr_wr(.ptr(ral.csid), .value(spi_regs.csid));
  endtask : program_csid_reg

  virtual task program_control_reg();
    ral.control.tx_watermark.set(spi_regs.tx_watermark);
    ral.control.rx_watermark.set(spi_regs.rx_watermark);
    ral.control.passthru.set(spi_regs.passthru);
    // activate spi_host dut
    ral.control.spien.set(1'b1);
    csr_update(ral.control);
  endtask : program_control_reg

  virtual task program_configopt_regs();
    // CONFIGOPTS register fields
    base_reg = get_dv_base_reg_by_name("configopts");
    for (int i = 0; i < SPI_HOST_NUM_CS; i++) begin
      set_dv_base_reg_field_by_name(base_reg, "cpol",     spi_regs.cpol[i], i);
      set_dv_base_reg_field_by_name(base_reg, "cpha",     spi_regs.cpha[i], i);
      set_dv_base_reg_field_by_name(base_reg, "fullcyc",  spi_regs.fullcyc[i], i);
      set_dv_base_reg_field_by_name(base_reg, "csnlead",  spi_regs.csnlead[i], i);
      set_dv_base_reg_field_by_name(base_reg, "csntrail", spi_regs.csntrail[i], i);
      set_dv_base_reg_field_by_name(base_reg, "csnidle",  spi_regs.csnidle[i], i);
      set_dv_base_reg_field_by_name(base_reg, "clkdiv",   spi_regs.clkdiv[i], i);
      csr_update(base_reg);
    end
  endtask : program_configopt_regs

  virtual task program_command_reg();
    // COMMAND register fields
    ral.command.direction.set(spi_regs.direction);
    ral.command.speed.set(spi_regs.speed);
    ral.command.csaat.set(spi_regs.csaat);
    ral.command.len.set(spi_regs.len);
    csr_update(ral.command);
  endtask : program_command_reg

  virtual task write_tx_data();
    int byte_len = 0;
    bit [TL_DW-1:0] tx_wdata;
    bit [TL_AW-1:0] fifo_waddr;
    int nbytes;

    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(fifo_baddr)
    fifo_waddr = ral.get_addr_from_offset(fifo_baddr);
    `uvm_info(`gfn, $sformatf("\n  base_vseq, tx_byte_addr: 0x%0x", fifo_baddr), UVM_LOW)
    `uvm_info(`gfn, $sformatf("\n  base_vseq, tx_word_addr: 0x%0x", fifo_waddr), UVM_LOW)
    `DV_CHECK_MEMBER_RANDOMIZE_WITH_FATAL(data_q,
                                          data_q.size() == spi_regs.len + 1;
                                         )
    `uvm_info(`gfn, $sformatf("\n  base_vseq, write %0d bytes to tx_fifo",
        data_q.size()), UVM_LOW)
    if (!SPI_HOST_BYTEORDER) swap_array_byte_order(data_q);

    // iterate through the data_q and pop off words to write to tx_fifo
    while (data_q.size() > 0) begin
      wait_for_fifos_available(TxFifo);
      tx_wdata = '0;
      // get a word data which is programm to the data register
      for (nbytes = 0; nbytes < TL_DBW; nbytes++) begin
        if (data_q.size() > 0) begin
          tx_wdata[8*nbytes +: 8] = data_q.pop_front();
          byte_len++;
        end
      end
      send_tl_access(.addr(fifo_waddr), .data(tx_wdata), .write(1'b1), .blocking(1'b0));
      // issue seq for spi write transaction
      send_spi_seq(.bus_op(BusOpWrite), .byte_len(byte_len));
      byte_len = 0;
      `DV_CHECK_MEMBER_RANDOMIZE_FATAL(tx_fifo_access_dly)
      cfg.clk_rst_vif.wait_clks(tx_fifo_access_dly);
    end
    // wait for all accesses to complete
    wait_no_outstanding_access();
    // read out status/intr_state CSRs to check
    check_status_and_clear_intrs();
  endtask : write_tx_data

  virtual task send_tl_access(bit [TL_AW-1:0]  addr,
                              bit [TL_DW-1:0]  data,
                              bit              write,
                              bit [TL_DBW-1:0] mask = {TL_DBW{1'b1}},
                              bit              blocking = $urandom_range(0, 1));
    tl_access(.addr(addr), .write(write), .data(data), .mask(mask), .blocking(blocking));
    `uvm_info(`gfn, "\n  base_vseq, send_tl_access", UVM_LOW)
    `uvm_info(`gfn, $sformatf("\n    %s to addr 0x%0x, data: 0x%0x, mask %b, blocking %b",
        write ? "write" : "read", addr, data, mask, blocking), UVM_LOW)
  endtask : send_tl_access

  virtual task send_spi_seq(bus_op_e bus_op, int byte_len);
    spi_device_seq m_spi_device_seq;

    if (bus_op == BusOpWrite) begin
      `uvm_create_on(m_spi_device_seq, p_sequencer.spi_host_sequencer_h)
      `uvm_info(`gfn, $sformatf("\n  base_vseq: create m_spi_device_seq"), UVM_LOW)
      m_spi_device_seq.item_type = SpiTransWrite;
      m_spi_device_seq.byte_len = byte_len;
      `uvm_info(`gfn, $sformatf("\n  base_vseq: item_type %s",
          m_spi_device_seq.item_type.name()), UVM_LOW)
      `uvm_info(`gfn, $sformatf("\n  base_vseq: byte_len %0d",
          m_spi_device_seq.item_type), UVM_LOW)
      `uvm_send(m_spi_device_seq);
    end
  endtask : send_spi_seq
  
  virtual task read_rx_data();
    bit [TL_DW-1:0] rx_data;
    bit [TL_AW-1:0] fifo_waddr;
    uint cnt_rx_bytes = 0;

    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(fifo_baddr)
    fifo_waddr = ral.get_addr_from_offset(fifo_baddr);
    `uvm_info(`gfn, $sformatf("\n  base_vseq, rx_byte_addr 0x%0x", fifo_baddr), UVM_LOW)
    `uvm_info(`gfn, $sformatf("\n  base_vseq, rx_word_addr 0x%0x", fifo_waddr), UVM_LOW)
    while (cnt_rx_bytes < num_rd_bytes) begin
      send_tl_access(.addr(fifo_waddr), .data(rx_data), .write(1'b0));
      cnt_rx_bytes += 4;
      `DV_CHECK_MEMBER_RANDOMIZE_FATAL(rx_fifo_access_dly)
      cfg.clk_rst_vif.wait_clks(rx_fifo_access_dly);
    end
    // wait for all accesses to complete
    wait_no_outstanding_access();
    // read out status/intr_state CSRs to check
    check_status_and_clear_intrs();
  endtask : read_rx_data

  // read interrupts and randomly clear interrupts if set
  virtual task process_interrupts();
    bit [TL_DW-1:0] intr_state, intr_clear;

    // read interrupt
    csr_rd(.ptr(ral.intr_state), .value(intr_state));
    // clear interrupt if it is set
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(intr_clear,
                                       foreach (intr_clear[i]) {
                                         intr_state[i] -> intr_clear[i] == 1;
                                       })
    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(clear_intr_dly)
    cfg.clk_rst_vif.wait_clks(clear_intr_dly);
    csr_wr(.ptr(ral.intr_state), .value(intr_clear));
  endtask : process_interrupts

  // override apply_reset to handle core_reset domain
  virtual task apply_reset(string kind = "HARD");
    fork
      super.apply_reset(kind);
      begin
        if (kind == "HARD") begin
          cfg.clk_rst_core_vif.apply_reset();
        end
      end
    join
  endtask : apply_reset

  // override wait_for_reset to to handle core_reset domain
  virtual task wait_for_reset(string reset_kind = "HARD",
                              bit wait_for_assert = 1'b1,
                              bit wait_for_deassert = 1'b1);

    fork
      super.wait_for_reset(reset_kind, wait_for_assert, wait_for_deassert);
      begin
        if (wait_for_assert) begin
          `uvm_info(`gfn, "\n  base_vseq, waiting for core rst_n assertion...", UVM_MEDIUM)
          @(negedge cfg.clk_rst_core_vif.rst_n);
        end
        if (wait_for_deassert) begin
          `uvm_info(`gfn, "\n  base_vseq, waiting for core rst_n de-assertion...", UVM_MEDIUM)
          @(posedge cfg.clk_rst_core_vif.rst_n);
        end
        `uvm_info(`gfn, "\n  base_vseq, core wait_for_reset done", UVM_LOW)
      end
    join
  endtask : wait_for_reset

  // wait until fifos empty
  virtual task wait_for_fifos_empty(spi_host_fifo_e fifo = AllFifos);
    if (fifo == TxFifo || TxFifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.txempty), .exp_data(1'b1));
    end
    if (fifo == RxFifo || TxFifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.rxempty), .exp_data(1'b1));
    end
  endtask : wait_for_fifos_empty

  // reads out the STATUS and INTR_STATE csrs so scb can check the status
  virtual task check_status_and_clear_intrs();
    bit [TL_DW-1:0] data;

    // read then clear interrupts
    csr_rd(.ptr(ral.intr_state), .value(data));
    csr_wr(.ptr(ral.intr_state), .value(data));
    // read status register
    csr_rd(.ptr(ral.status), .value(data));
  endtask : check_status_and_clear_intrs

  // wait until fifos has available entries to read/write
  virtual task wait_for_fifos_available(spi_host_fifo_e fifo = AllFifos);
    if (fifo == TxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.txfull), .exp_data(1'b0));
      `uvm_info(`gfn, $sformatf("\n  base_vseq: tx_fifo is not full",), UVM_LOW)
    end
    if (fifo == RxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.rxfull), .exp_data(1'b0));
      `uvm_info(`gfn, $sformatf("\n  base_vseq: rx_fifo is not full",), UVM_LOW)
    end
  endtask

  // update spi_agent registers
  virtual function void update_spi_agent_regs();
    for (int i = 0; i < SPI_HOST_NUM_CS; i++) begin
      cfg.m_spi_agent_cfg.sck_polarity[i] = spi_regs.cpol[i];
      cfg.m_spi_agent_cfg.sck_phase[i]    = spi_regs.cpha[i];
      cfg.m_spi_agent_cfg.fullcyc[i]      = spi_regs.fullcyc[i];
      cfg.m_spi_agent_cfg.csnlead[i]      = spi_regs.csnlead[i];
    end
    cfg.m_spi_agent_cfg.csid              = spi_regs.csid;
    cfg.m_spi_agent_cfg.direction         = spi_regs.direction;
    cfg.m_spi_agent_cfg.spi_mode          = spi_regs.speed;
    cfg.m_spi_agent_cfg.csaat             = spi_regs.csaat;
    cfg.m_spi_agent_cfg.len               = spi_regs.len;
  endfunction : update_spi_agent_regs

  // print the content of spi_regs[channel]
  virtual function void print_spi_host_regs(uint en_print = 1);
    if (en_print) begin
      string str = "";

      str = {str, "\n  base_vseq, channel infor:"};
      str = {str, $sformatf("\n    csid         %0d", spi_regs.csid)};
      str = {str, $sformatf("\n    speed        %s",  spi_regs.speed.name())};
      str = {str, $sformatf("\n    direction    %s",  spi_regs.direction.name())};
      str = {str, $sformatf("\n    csaat        %b",  spi_regs.csaat)};
      str = {str, $sformatf("\n    len          %0d", spi_regs.len)};
      for (int i = 0; i < SPI_HOST_NUM_CS; i++) begin
        str = {str, $sformatf("\n    config[%0d]", i)};
        str = {str, $sformatf("\n      cpol       %b", spi_regs.cpol[i])};
        str = {str, $sformatf("\n      cpha       %b", spi_regs.cpha[i])};
        str = {str, $sformatf("\n      fullcyc    %b", spi_regs.fullcyc[i])};
        str = {str, $sformatf("\n      csnlead    %0d", spi_regs.csnlead[i])};
        str = {str, $sformatf("\n      csntrail   %0d", spi_regs.csntrail[i])};
        str = {str, $sformatf("\n      csnidle    %0d", spi_regs.csnidle[i])};
        str = {str, $sformatf("\n      clkdiv     %0d\n", spi_regs.clkdiv[i])};
      end

      `uvm_info(`gfn, str, UVM_LOW)
    end
  endfunction : print_spi_host_regs
  
  // set reg/mreg using name and index
  virtual function dv_base_reg get_dv_base_reg_by_name(string csr_name,
                                               int    csr_idx = -1);
    string  reg_name;
    uvm_reg reg_uvm;

    reg_name = (csr_idx == -1) ? csr_name : $sformatf("%s_%0d", csr_name, csr_idx);
    reg_uvm  = ral.get_reg_by_name(reg_name);
    `DV_CHECK_NE_FATAL(reg_uvm, null, reg_name)
    `downcast(get_dv_base_reg_by_name, reg_uvm)
  endfunction

  // set field of reg/mreg using name and index, need to call csr_update after setting
  virtual function void set_dv_base_reg_field_by_name(dv_base_reg csr_reg,
                                                      string      csr_field,
                                                      uint        value,
                                                      int         csr_idx = -1);
    uvm_reg_field reg_field;
    string reg_name;

    reg_name = (csr_idx == -1) ? csr_field : $sformatf("%s_%0d", csr_field, csr_idx);
    reg_field = csr_reg.get_field_by_name(reg_name);
    `DV_CHECK_NE_FATAL(reg_field, null, reg_name)
    reg_field.set(value);
  endfunction

  virtual function void swap_array_byte_order(ref bit [7:0] data[$]);
    bit [7:0] data_arr[];
    data_arr = data;
    `uvm_info(`gfn, $sformatf("\n  base_vseq, data_q_baseline: %0p", data), UVM_LOW)
    dv_utils_pkg::endian_swap_byte_arr(data_arr);
    data = data_arr;
    `uvm_info(`gfn, $sformatf("\n  base_vseq, data_q_swapped:  %0p", data), UVM_LOW)
  endfunction : swap_array_byte_order

  // phase alignment for resets signal of core and bus domain
  virtual task do_phase_align_reset(bit en_phase_align_reset = 1'b0);
    if (en_phase_align_reset) begin
      fork
        cfg.clk_rst_vif.wait_clks($urandom_range(5, 10));
        cfg.clk_rst_core_vif.wait_clks($urandom_range(5, 10));
      join
    end
  endtask : do_phase_align_reset

endclass : spi_host_base_vseq
