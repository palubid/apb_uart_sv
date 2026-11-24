/**
 * Test ID : 8
 * File    : test_reset_values.sv
 * Brief   : Verifies the 16550 register reset state. After reset the UART must
 *           present the documented default values (see architecture.md 4.2):
 *             IIR=0x01, LSR=0x60, and LCR/IER/MCR/MSR/SCR/DLL/DLM=0x00.
 *           The divisor latches (DLL/DLM) are read behind DLAB=1. No serial
 *           traffic is involved; this is a pure register-map reset check.
 */

// Compare a register's post-reset value against its expected default.
task automatic rv_chk(input string name, input logic [7:0] got,
                      input logic [7:0] exp, ref int errors);
  if (got !== exp) begin
    $error("[%0t] %s reset = 0x%02x, expected 0x%02x", $time, name, got, exp);
    errors++;
  end
  else
    $display("[%0t] %s reset = 0x%02x  OK", $time, name, got);
endtask

task automatic test_reset_values();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low  (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable   (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IIR = 12'h2; // interrupt identification
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] MCR = 12'h4; // modem control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register
  localparam logic [APB_ADDR_WIDTH-1:0] MSR = 12'h6; // modem status register
  localparam logic [APB_ADDR_WIDTH-1:0] SCR = 12'h7; // scratch register

  localparam logic [7:0] LCR_DLAB = 8'h80; // DLAB only, to expose DLL/DLM

  apb_resp_e   resp;
  logic [31:0] rdata;
  int          errors = 0;

  // Read the DLAB=0 register group first (reset LCR has DLAB=0, so addresses
  // 0x1 -> IER and 0x0/0x1 are not divisor latches yet).
  bfm.read(LCR, rdata, resp); rv_chk("LCR", rdata[7:0], 8'h00, errors);
  bfm.read(IER, rdata, resp); rv_chk("IER", rdata[7:0], 8'h00, errors);
  bfm.read(IIR, rdata, resp); rv_chk("IIR", rdata[7:0], 8'h01, errors);
  bfm.read(MCR, rdata, resp); rv_chk("MCR", rdata[7:0], 8'h00, errors);
  bfm.read(LSR, rdata, resp); rv_chk("LSR", rdata[7:0], 8'h60, errors);
  bfm.read(MSR, rdata, resp); rv_chk("MSR", rdata[7:0], 8'h00, errors);
  bfm.read(SCR, rdata, resp); rv_chk("SCR", rdata[7:0], 8'h00, errors);

  // Set DLAB to expose the divisor latches, then read their reset values.
  bfm.write(LCR, {24'h0, LCR_DLAB}, resp);
  bfm.read(DLL, rdata, resp); rv_chk("DLL", rdata[7:0], 8'h00, errors);
  bfm.read(DLM, rdata, resp); rv_chk("DLM", rdata[7:0], 8'h00, errors);

  // Restore DLAB=0 so the UART is left in a clean state.
  bfm.write(LCR, {24'h0, 8'h00}, resp);

  if (errors == 0)
    $display("[%0t] test_reset_values PASSED", $time);
  else
    $display("[%0t] test_reset_values FAILED (%0d mismatches)", $time, errors);

endtask
