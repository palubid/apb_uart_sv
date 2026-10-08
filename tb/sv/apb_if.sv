/**
 * File    : apb_if.sv
 * License : MIT license
 * Brief   : APB4 interface used to drive the apb_uart_sv DUT from a master BFM.
 *
 * Mirrors the DUT's APB port list (PADDR/PWDATA/PWRITE/PSEL/PENABLE in,
 * PRDATA/PREADY/PSLVERR out). A master clocking block gives the BFM race-free
 * timing: inputs are sampled #1step before the edge and outputs driven #1
 * after it, so the DUT (wired to the raw nets) always samples stable stimulus.
 */
interface apb_if #(
  parameter int ADDR_W = 12,
  parameter int DATA_W = 32
)(
  input logic pclk,
  input logic presetn
);
  // Master-sourced request signals
  logic [ADDR_W-1:0]   paddr;
  logic                pwrite;
  logic                psel;
  logic                penable;
  logic [DATA_W-1:0]   pwdata;

  // Slave-sourced response signals
  logic [DATA_W-1:0]   prdata;
  logic                pready;
  logic                pslverr;

  // ---------------------------------------------------------------------------
  // Master clocking block (BFM side)
  //   Sample DUT responses #1step before the edge, drive the request signals #1
  //   after it so the DUT always samples un-torn stimulus on the next posedge.
  // ---------------------------------------------------------------------------
  clocking master_cb @(posedge pclk);
    default input #1step output #1;
    output paddr, pwrite, psel, penable, pwdata;
    input  prdata, pready, pslverr;
  endclocking

  // Synchronous master modport: BFM drives/samples exclusively via master_cb.
  modport master_sync (clocking master_cb, input pclk, presetn);

  // Master modport: a module-based master drives the request signals directly.
  modport master (
    input  pclk, presetn,
    output paddr, pwrite, psel, penable, pwdata,
    input  prdata, pready, pslverr
  );

  // Slave modport: a module-based slave drives the response signals.
  modport slave (
    input  pclk, presetn,
    input  paddr, pwrite, psel, penable, pwdata,
    output prdata, pready, pslverr
  );

endinterface : apb_if
