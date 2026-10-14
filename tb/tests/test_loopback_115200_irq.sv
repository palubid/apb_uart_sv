/**
 * Test ID : 5
 * File    : test_loopback_115200_irq.sv
 * Brief   : Interrupt-driven variant of test_loopback_115200. The UART is set
 *           up for 115200 8N1 with an internal serial loopback (tx_o mirrored
 *           onto rx_i), but instead of polling LSR[0] the Received Data
 *           Available interrupt is enabled (IER[0]). The BFM blocks on the
 *           UART interrupt output (event_o); when it fires the received byte
 *           is read from RBR and compared against what was sent.
 */
task automatic test_loopback_115200_irq();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] THR = 12'h0; // TX holding / RX buffer (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable       (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register

  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches
  localparam logic [7:0] IER_ERBFI    = 8'h01; // Received Data Available interrupt enable

  int BAUD = 115200;
  real DIV = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // Assuming `CLK_PERIOD` is in ns
  logic [15:0] BAUD_DIV_115200 = int'(DIV);

  // Bytes pushed through the TX->RX loopback and checked on the way back.
  byte unsigned tx_bytes[] = '{8'h55, 8'hA3, 8'h00, 8'hFF, 8'h5A};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int          errors = 0;

  // Internal loopback: mirror the serial TX line onto RX.
  fork
    forever @(negedge clk) uart_if_inst.rx = tx_o;
  join_none

  // Program the baud divisor behind the DLAB bit.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},          resp);
  bfm.write(DLL, {24'h0, BAUD_DIV_115200[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV_115200[15:8]}, resp);

  // Switch back to normal 8N1 access (DLAB cleared).
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  $display("[%0t] UART configured: 115200 8N1 (div=%0d)", $time, BAUD_DIV_115200);

  // No interrupt may be pending before the interrupt source is enabled.
  if (event_o !== 1'b0) begin
    $error("[%0t] event_o unexpectedly asserted before IER is programmed", $time);
    errors++;
  end

  // Enable the Received Data Available interrupt.
  bfm.write(IER, {24'h0, IER_ERBFI}, resp);
  $display("[%0t] IER = 0x%02x (RDA interrupt enabled)", $time, IER_ERBFI);

  foreach (tx_bytes[i]) begin
    logic [7:0] sent = tx_bytes[i];
    logic [7:0] got;

    bfm.write(THR, {24'h0, sent}, resp);
    $display("[%0t] TX  byte[%0d] = 0x%02x", $time, i, sent);

    // Sleep until the UART signals that the byte has been received.
    bfm.wait_irq();
    $display("[%0t] IRQ for byte[%0d]", $time, i);

    // Interrupt service: read the received byte and compare. (Any read in the
    // low register group pops the RX FIFO in this DUT, so IIR is not read first.)
    bfm.read(THR, rdata, resp);
    got = rdata[7:0];
    if (got === sent)
      $display("[%0t] RX  byte[%0d] = 0x%02x  PASS", $time, i, got);
    else begin
      $error("[%0t] RX  byte[%0d] = 0x%02x  MISMATCH (expected 0x%02x)",
             $time, i, got, sent);
      errors++;
    end

    // Draining the RX FIFO must deassert the interrupt.
    repeat (3) @(posedge clk);
    if (event_o !== 1'b0) begin
      $error("[%0t] event_o still asserted after RBR read (byte[%0d])", $time, i);
      errors++;
    end
  end

  if (errors == 0)
    $display("[%0t] test_loopback_115200_irq PASSED (%0d bytes)", $time, tx_bytes.size());
  else
    $display("[%0t] test_loopback_115200_irq FAILED (%0d mismatches)", $time, errors);

endtask
