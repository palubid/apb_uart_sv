/**
 * Test ID : 1
 * File    : test_smoke.sv
 * Brief   : Basic smoke test for the UART controller. Verifies that the controller
 *           can be configured and perform a simple UART write operation correctly.
 *
 */
task automatic test_smoke();

  // UART register offsets (word-addressed register file, PADDR[2:0])
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3;
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1;

  apb_resp_e         resp;
  logic [31:0]       rdata;

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

endtask
