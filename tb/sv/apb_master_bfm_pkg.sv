/**
 * File    : apb_master_bfm_pkg.sv
 * License : MIT license
 * Brief   : APB4 master BFM. Drives write/read transactions on behalf of the
 *           test. Supports idle insertion (gap before the SETUP phase) and
 *           backpressure injection (extra SETUP-to-ACCESS stall), both using
 *           the cycle_pause pattern [1,1,1,0] -> a 3-cycle gap, matching the
 *           AXI master BFM throttling knobs.
 *
 * Usage:
 *   apb_master_bfm bfm = new(apb_vif);
 *   bfm.init();                 // drive master signals to safe defaults
 *   bfm.idle_mode        = 1;   // 3-cycle gap before asserting psel
 *   bfm.backpressure_mode = 1;  // 3-cycle stall between SETUP and ACCESS
 *   bfm.write(addr, data, resp);
 *   bfm.read (addr, data, resp);
 */
package apb_master_bfm_pkg;

  // APB transfer response, decoded from PSLVERR.
  typedef enum logic {
    APB_OKAY  = 1'b0,
    APB_ERROR = 1'b1
  } apb_resp_e;

  class apb_master_bfm #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
  );
    virtual apb_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)).master_sync vif;

    // Throttling modes: both use the [1,1,1,0] cycle_pause pattern
    int idle_mode         = 0; // inserts 3-cycle gap before asserting psel
    int backpressure_mode = 0; // inserts 3-cycle stall before asserting penable

    // Maximum wait cycles before $fatal (matches the AXI BFM TIMEOUT_AXI)
    int unsigned TIMEOUT_APB = 20000;

    function new(virtual apb_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)).master_sync vif);
      this.vif = vif;
    endfunction

    // Drive all master-sourced signals to safe defaults through the clocking
    // block. Call once before reset deasserts so the DUT never samples X.
    task automatic init();
      vif.master_cb.paddr   <= '0;
      vif.master_cb.pwrite  <= 1'b0;
      vif.master_cb.psel    <= 1'b0;
      vif.master_cb.penable <= 1'b0;
      vif.master_cb.pwdata  <= '0;
    endtask

    // Insert 3 idle cycles (cycle_pause throttle) before the SETUP phase.
    task automatic idle_pause();
      if (idle_mode) begin
        repeat(3) @(vif.master_cb);
      end
    endtask

    // Insert 3 stall cycles (cycle_pause throttle) between SETUP and ACCESS.
    task automatic bp_pause();
      if (backpressure_mode) begin
        repeat(3) @(vif.master_cb);
      end
    endtask

    // -----------------------------------------------------------------------
    // Common APB transfer: SETUP phase, then ACCESS phase, wait for PREADY.
    // -----------------------------------------------------------------------
    task automatic transfer(
      input  logic              write_en,
      input  logic [ADDR_W-1:0] addr,
      input  logic [DATA_W-1:0] wdata,
      output logic [DATA_W-1:0] rdata,
      output apb_resp_e         resp
    );
      int unsigned timeout_cnt;

      @(vif.master_cb);
      idle_pause();

      // SETUP phase: assert psel, drive address/control, penable stays low.
      vif.master_cb.paddr   <= addr;
      vif.master_cb.pwrite  <= write_en;
      vif.master_cb.pwdata  <= write_en ? wdata : '0;
      vif.master_cb.psel    <= 1'b1;
      vif.master_cb.penable <= 1'b0;

      // Optional stall holding the bus in the SETUP phase.
      bp_pause();

      // ACCESS phase: assert penable and wait for the slave to signal pready.
      @(vif.master_cb);
      vif.master_cb.penable <= 1'b1;

      timeout_cnt = 0;
      forever begin
        @(vif.master_cb);
        if (vif.master_cb.pready) break;
        if (++timeout_cnt >= TIMEOUT_APB)
          $fatal(1, "[apb_master_bfm] TIMEOUT waiting for pready");
      end

      rdata = vif.master_cb.prdata;
      resp  = apb_resp_e'(vif.master_cb.pslverr);

      // End the transfer: deassert psel/penable for at least one idle cycle.
      vif.master_cb.psel    <= 1'b0;
      vif.master_cb.penable <= 1'b0;
      vif.master_cb.pwrite  <= 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Write transaction
    // -----------------------------------------------------------------------
    task automatic write(
      input  logic [ADDR_W-1:0] addr,
      input  logic [DATA_W-1:0] data,
      output apb_resp_e         resp
    );
      logic [DATA_W-1:0] unused_rdata;
      transfer(1'b1, addr, data, unused_rdata, resp);
    endtask

    // -----------------------------------------------------------------------
    // Read transaction
    // -----------------------------------------------------------------------
    task automatic read(
      input  logic [ADDR_W-1:0] addr,
      output logic [DATA_W-1:0] data,
      output apb_resp_e         resp
    );
      transfer(1'b0, addr, '0, data, resp);
    endtask

  endclass : apb_master_bfm

endpackage : apb_master_bfm_pkg
