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
  // Include all test tasks (compiled together, selected at runtime)
  // -------------------------------------------------------------------------
  `include "../tests/test_smoke.sv"
  `include "../tests/test_loopback_115200.sv"

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
    string test_name;

    // ---- Parse plusargs ----
    if (!$value$plusargs("TESTNAME=%s",  test_name))   test_name   = "test_smoke";

    $display("");
    $display("===========================================================");
    $display(" APB UART BFM SV Testbench");
    $display("  Test     : %s", test_name);
    $display("===========================================================");
    $display("");

    rx_i = 1'b1; // UART idle line is high

    // construct BFM instance
    bfm = new(apb_if_inst);
    bfm.init();

    // Hold until reset is released.
    wait (resetn === 1'b1);
    repeat(2) @(posedge clk);

    // ---- Dispatch test ----
    case (test_name)
      "test_smoke"           : test_smoke();
      "test_loopback_115200" : test_loopback_115200();
      default: $fatal(1, "[tb_sv_apb_uart] Unknown test: %s", test_name);
    endcase

    repeat(10) @(posedge clk);
    $display("[%0t] Main simulation finished", $time);
    $finish;

  end : main_simulation

  // final block for simulation end
  final begin
    $display("\n============END OF SIM===================================\n");
  end

endmodule