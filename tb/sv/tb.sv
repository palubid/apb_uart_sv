`timescale 1ns/1ps
`include "tb_defs.sv"

module tb_uart;

  import apb_master_bfm_pkg::*;

  // -------------------------------------------------------------------------
  // Local Parameters
  // -------------------------------------------------------------------------

  localparam RESET_CYCLES = 3;
  localparam APB_ADDR_WIDTH = 12;

  // -------------------------------------------------------------------------
  // Signal Declarations
  // -------------------------------------------------------------------------

  logic clk;
  logic resetn;

  logic rx_i;
  logic tx_o;
  logic event_o;

  // -------------------------------------------------------------------------
  // APB interface + master BFM
  // -------------------------------------------------------------------------

  apb_if #(.ADDR_W(APB_ADDR_WIDTH), .DATA_W(32)) apb_if_inst (
    .pclk    ( clk    ),
    .presetn ( resetn )
  );

  apb_master_bfm #(.ADDR_W(APB_ADDR_WIDTH), .DATA_W(32)) bfm;

  // -------------------------------------------------------------------------
  // DUT (Device Under Test) Signals
  // -------------------------------------------------------------------------

  apb_uart_sv #(
    .APB_ADDR_WIDTH ( APB_ADDR_WIDTH )
  ) u_apb_uart_sv (
    .CLK            ( clk                     ),
    .RSTN           ( resetn                  ),
    // APB Interface Signals
    .PADDR          ( apb_if_inst.paddr       ),
    .PSEL           ( apb_if_inst.psel        ),
    .PENABLE        ( apb_if_inst.penable     ),
    .PWRITE         ( apb_if_inst.pwrite      ),
    .PWDATA         ( apb_if_inst.pwdata      ),
    .PRDATA         ( apb_if_inst.prdata      ),
    .PREADY         ( apb_if_inst.pready      ),
    .PSLVERR        ( apb_if_inst.pslverr     ),
    // UART Interface Signals
    .rx_i           ( rx_i                    ),
    .tx_o           ( tx_o                    ),
    .event_o        ( event_o                 )
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
    apb_resp_e         resp;
    logic [31:0]       rdata;

    // UART register offsets (word-addressed register file, PADDR[2:0])
    localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3;
    localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1;

    rx_i = 1'b1; // UART idle line is high

    bfm = new(apb_if_inst);
    bfm.init();

    // Hold until reset is released.
    wait (resetn === 1'b1);
    repeat(2) @(posedge clk);

    // Baseline back-to-back transfers.
    bfm.write(LCR, 32'h0000_0083, resp); // set DLAB + 8-bit word length
    $display("[%0t] WRITE LCR resp=%s", $time, resp.name());
    bfm.read (LCR, rdata, resp);
    $display("[%0t] READ  LCR = 0x%08x resp=%s", $time, rdata, resp.name());

    // Exercise idle throttling (gap before SETUP phase).
    bfm.idle_mode = 1;
    bfm.write(IER, 32'h0000_0001, resp);
    bfm.read (IER, rdata, resp);
    $display("[%0t] READ  IER = 0x%08x resp=%s (idle_mode)", $time, rdata, resp.name());
    bfm.idle_mode = 0;

    // Exercise backpressure throttling (SETUP-to-ACCESS stall).
    bfm.backpressure_mode = 1;
    bfm.read (LCR, rdata, resp);
    $display("[%0t] READ  LCR = 0x%08x resp=%s (backpressure_mode)", $time, rdata, resp.name());
    bfm.backpressure_mode = 0;

    repeat(10) @(posedge clk);
    $display("[%0t] Main simulation finished", $time);
    $finish;

  end : main_simulation

  // final block for simulation end
  final begin
    $display("\n============END OF SIM===================================\n");
  end

endmodule