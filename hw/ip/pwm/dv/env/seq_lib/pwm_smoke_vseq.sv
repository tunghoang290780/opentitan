// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// smoke test vseq: accessing a major datapath within the pwm
class pwm_smoke_vseq extends pwm_rx_tx_vseq;
  `uvm_object_utils(pwm_smoke_vseq)
  `uvm_object_new

  constraint num_trans_c { num_trans == 4; }

  virtual task pre_start();
    super.pre_start();
    // TODO: currently, only Standard mode is verified in the smoke test for all channels
    cfg.seq_cfg.pwm_run_mode = Blinking;
    cfg.seq_cfg.pwm_run_channel = 1;
  endtask : pre_start

endclass : pwm_smoke_vseq
