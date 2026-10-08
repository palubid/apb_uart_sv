`timescale 1ns/1ps
`include "tb_defs.sv"

module tb_uart;

  // -------------------------------------------------------------------------
  // Local Parameters
  // -------------------------------------------------------------------------

  localparam RESET_CYCLES = 3;

  // -------------------------------------------------------------------------
  // Signal Declarations
  // -------------------------------------------------------------------------

  logic clk;
  logic resetn;

  // -------------------------------------------------------------------------
  // DUT (Device Under Test) Signals
  // -------------------------------------------------------------------------

  apb_uart_sv u_apb_uart_sv (
    .CLK            ( clk     ),
    .RSTN           ( resetn  ),
    // APB Interface Signals
    .PADDR          ( ),
    .PSEL           ( ),
    .PENABLE        ( ),
    .PWRITE         ( ),
    .PWDATA         ( ),
    .PRDATA         ( ),
    .PREADY         ( ),
    .PSLVERR        ( ),
    // UART Interface Signals
    .rx_i           ( ),
    .tx_o           ( ),
    .event_o        ( )
  );

  // -------------------------------------------------------------------------
  // Clock & Reset Generation
  // -------------------------------------------------------------------------

  `CLOCK_GEN(`CLK_PERIOD, `CLK_SKEW, `CLK_PERIOD, clk)

  // Reset generation
  initial begin
    resetn = 1'b0;
    #(RESET_CYCLES * `CLK_PERIOD) resetn = 1'b1;
    $display("[%0t] Reset deasserted", $time);
  end

  // -------------------------------------------------------------------------
  // Main simulation entry point
  // -------------------------------------------------------------------------
  initial begin
    $timeformat(-6, 3, " us", 9);
    $display("\n============START OF SIM=================================");
  end

  initial begin : main_simulation

    repeat(10) @(posedge clk);
    $display("[%0t] Main simulation finished", $time);
    $finish;

  end : main_simulation

endmodule