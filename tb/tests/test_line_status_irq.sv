/**
 * Test ID : 11
 * File    : test_line_status_irq.sv
 * Brief   : Exercises the 16550 Receiver Line Status interrupt on a parity
 *           error. The UART is configured for 8 data bits + EVEN parity, 1 stop
 *           bit, and the Receiver Line Status interrupt is enabled (IER[2]).
 *           The external TX model drives:
 *             1. a byte with correct parity   -> no line-status error, no IRQ,
 *                LSR[2]=0, data reads back correctly;
 *             2. a byte with inverted parity  -> parity error flagged in LSR[2],
 *                IIR reports the line-status source, event_o asserts, and the
 *                interrupt clears once the errored byte is popped from RBR.
 *           Only IER[2] is enabled so the interrupt is attributable solely to
 *           the receiver-line-status source.
 */
task automatic test_line_status_irq();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] RBR = 12'h0; // RX buffer              (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable       (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] IIR = 12'h2; // interrupt identification
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2; // fifo control register
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register

  // 8-bit word (LCR[1:0]=11), EVEN parity enabled (LCR[3]=1), 1 stop bit.
  localparam logic [7:0] LCR_8E1      = 8'h0B;
  localparam logic [7:0] LCR_8E1_DLAB = 8'h8B;
  localparam logic [7:0] IER_ELSI     = 8'h04; // Receiver Line Status interrupt enable
  localparam logic [3:0] IIR_RLS      = 4'hC;  // IIR_o code for receiver line status

  localparam int LSR_DR = 0; // Data Ready
  localparam int LSR_PE = 2; // Parity Error

  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;
  logic [7:0]  good_byte = 8'h5A;
  logic [7:0]  bad_byte  = 8'hC3;
  bit          asserted;
  int          c;

  // Program the baud divisor, then select 8E1 access (DLAB cleared) and flush.
  bfm.write(LCR, {24'h0, LCR_8E1_DLAB},   resp);
  bfm.write(DLL, {24'h0, BAUD_DIV[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV[15:8]}, resp);
  bfm.write(LCR, {24'h0, LCR_8E1}, resp);
  bfm.write(FCR, 32'h0000_0006, resp); // flush both FIFOs
  $display("[%0t] UART configured: 115200 8E1 (div=%0d)", $time, BAUD_DIV);

  // External TX model: 8 data bits + EVEN parity, 1 stop bit.
  utx.configure(.baud_div(BAUD_DIV), .data_bits(8), .parity_en(1'b1),
                .stop_bits(1));
  utx.init();

  // Enable only the Receiver Line Status interrupt.
  bfm.write(IER, {24'h0, IER_ELSI}, resp);
  $display("[%0t] IER = 0x%02x (Receiver Line Status interrupt enabled)",
           $time, IER_ELSI);

  if (event_o !== 1'b0) begin
    $error("[%0t] event_o asserted before any byte received", $time);
    errors++;
  end

  // -------------------------------------------------------------------------
  // Phase 1: correctly framed byte. No parity error, so no line-status IRQ.
  // -------------------------------------------------------------------------
  utx.send_byte(good_byte, .force_parity_err(1'b0));
  $display("[%0t] RX-in good byte = 0x%02x (valid parity)", $time, good_byte);

  poll = 0;
  do begin
    bfm.read(LSR, rdata, resp);
    if (++poll > 100000)
      $fatal(1, "[test_line_status_irq] TIMEOUT waiting for good byte");
  end while (!rdata[LSR_DR]);

  if (rdata[LSR_PE]) begin
    $error("[%0t] LSR[2] (parity error) set for a correctly framed byte", $time);
    errors++;
  end
  if (event_o !== 1'b0) begin
    $error("[%0t] line-status interrupt asserted for a valid byte", $time);
    errors++;
  end

  bfm.read(RBR, rdata, resp);
  if (rdata[7:0] !== good_byte) begin
    $error("[%0t] good byte = 0x%02x, expected 0x%02x", $time, rdata[7:0], good_byte);
    errors++;
  end
  else
    $display("[%0t] good byte read back = 0x%02x  PASS", $time, rdata[7:0]);

  // -------------------------------------------------------------------------
  // Phase 2: byte with inverted parity -> receiver line status interrupt.
  // -------------------------------------------------------------------------
  utx.send_byte(bad_byte, .force_parity_err(1'b1));
  $display("[%0t] RX-in bad byte = 0x%02x (inverted parity)", $time, bad_byte);

  // Bounded wait for the interrupt so a non-asserting DUT fails gracefully
  // instead of hitting the BFM wait_irq timeout ($fatal).
  asserted = 1'b0;
  for (c = 0; c < 4000; c++) begin
    @(posedge clk);
    if (event_o === 1'b1) begin asserted = 1'b1; break; end
  end

  if (!asserted) begin
    $error("[%0t] Receiver Line Status interrupt never asserted on parity error",
           $time);
    errors++;
  end
  else
    $display("[%0t] line-status interrupt asserted on parity error", $time);

  // Read LSR first: it lives in the high register group and does NOT pop the
  // RX FIFO, so the errored byte is still at the FIFO head and LSR[2] reflects
  // its parity-error flag. (Any low-group read in this DUT pops the FIFO.)
  bfm.read(LSR, rdata, resp);
  if (!rdata[LSR_PE]) begin
    $error("[%0t] LSR[2] (parity error) not set for a bad-parity byte (LSR=0x%02x)",
           $time, rdata[7:0]);
    errors++;
  end
  else
    $display("[%0t] LSR[2] parity error flagged (LSR=0x%02x)", $time, rdata[7:0]);

  // Read IIR to confirm the pending source is Receiver Line Status. This
  // low-group access also pops the errored byte, servicing the FIFO.
  bfm.read(IIR, rdata, resp);
  $display("[%0t] IIR = 0x%02x (IIR_o=0x%01x)", $time, rdata[7:0], rdata[3:0]);
  if (rdata[0] !== 1'b0) begin
    $error("[%0t] IIR[0]=1 (no interrupt) but event_o was asserted", $time);
    errors++;
  end
  if (rdata[3:0] !== IIR_RLS) begin
    $error("[%0t] IIR_o=0x%01x, expected 0x%01x (Receiver Line Status)",
           $time, rdata[3:0], IIR_RLS);
    errors++;
  end

  // With the errored byte drained the interrupt condition must clear.
  repeat (5) @(posedge clk);
  if (event_o !== 1'b0) begin
    $error("[%0t] line-status interrupt still asserted after draining the byte",
           $time);
    errors++;
  end
  else
    $display("[%0t] line-status interrupt cleared after service", $time);

  if (errors == 0)
    $display("[%0t] test_line_status_irq PASSED", $time);
  else
    $display("[%0t] test_line_status_irq FAILED (%0d errors)", $time, errors);

endtask
