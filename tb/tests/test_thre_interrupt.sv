/**
 * Test ID : 6
 * File    : test_thre_interrupt.sv
 * Brief   : Exercises the 16550 Transmitter Holding Register Empty (THRE)
 *           interrupt. When the THRE condition is true (TX FIFO empty) and the
 *           corresponding enable bit is set (ETBEI = IER[1]), the UART must
 *           raise an interrupt on event_o. The BFM blocks on event_o via
 *           wait_irq() instead of polling LSR.
 *
 *           Phases:
 *             1. No interrupt before ETBEI is enabled.
 *             2. Enabling ETBEI with an empty TX FIFO raises THRE immediately;
 *                IIR reports the THRE source.
 *             3. Masking the interrupt (ETBEI=0, then an IIR read to clear the
 *                latched code) drops event_o.
 *             4. With the FIFO pre-filled, ETBEI stays silent until the FIFO
 *                drains, then THRE fires on the empty transition.
 */
task automatic test_thre_interrupt();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] THR = 12'h0; // TX holding / RX buffer (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable       (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IIR = 12'h2; // interrupt identification
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register

  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches
  localparam logic [7:0] IER_ETBEI    = 8'h02; // Transmitter Holding Reg Empty interrupt enable
  localparam logic [3:0] IIR_THRE     = 4'h4;  // IIR_o code when THRE is the pending source

  int BAUD = 115200;
  real DIV = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // Assuming `CLK_PERIOD` is in ns
  logic [15:0] BAUD_DIV_115200 = int'(DIV);

  // Bytes used to pre-fill the TX FIFO in phase 4.
  byte unsigned tx_bytes[] = '{8'h11, 8'h22, 8'h33, 8'h44};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int          errors = 0;

  // Program the baud divisor behind the DLAB bit.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},          resp);
  bfm.write(DLL, {24'h0, BAUD_DIV_115200[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV_115200[15:8]}, resp);
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  $display("[%0t] UART configured: 115200 8N1 (div=%0d)", $time, BAUD_DIV_115200);

  // -------------------------------------------------------------------------
  // Phase 1: no interrupt may be pending while all enables are clear (IER=0).
  // -------------------------------------------------------------------------
  if (event_o !== 1'b0) begin
    $error("[%0t] event_o asserted before ETBEI is enabled", $time);
    errors++;
  end

  // -------------------------------------------------------------------------
  // Phase 2: enable ETBEI with an empty TX FIFO. THRE is already true, so the
  // interrupt must assert immediately.
  // -------------------------------------------------------------------------
  bfm.write(IER, {24'h0, IER_ETBEI}, resp);
  $display("[%0t] IER = 0x%02x (ETBEI / THRE interrupt enabled)", $time, IER_ETBEI);

  bfm.wait_irq();
  $display("[%0t] IRQ raised on empty TX FIFO", $time);

  // IIR_o[3:0] must report the THRE source and bit0=0 (interrupt pending).
  bfm.read(IIR, rdata, resp);
  $display("[%0t] IIR = 0x%02x (IIR_o=0x%01x)", $time, rdata[7:0], rdata[3:0]);
  if (rdata[0] !== 1'b0) begin
    $error("[%0t] IIR[0]=1 (no interrupt) but event_o was asserted", $time);
    errors++;
  end
  if (rdata[3:0] !== IIR_THRE) begin
    $error("[%0t] IIR_o=0x%01x, expected 0x%01x (THRE)", $time, rdata[3:0], IIR_THRE);
    errors++;
  end

  // -------------------------------------------------------------------------
  // Phase 3: mask the source. Clearing ETBEI stops re-assertion; a following
  // IIR read clears the latched code, so event_o must drop.
  // -------------------------------------------------------------------------
  bfm.write(IER, {24'h0, 8'h00}, resp);
  bfm.read (IIR, rdata, resp); // clears the latched THRE code
  repeat (3) @(posedge clk);
  if (event_o !== 1'b0) begin
    $error("[%0t] event_o still asserted after masking ETBEI", $time);
    errors++;
  end
  else
    $display("[%0t] event_o deasserted after masking ETBEI", $time);

  // -------------------------------------------------------------------------
  // Phase 4: pre-fill the TX FIFO, then enable ETBEI. THRE must stay low while
  // the FIFO holds data, and fire only once the FIFO empties.
  // -------------------------------------------------------------------------
  foreach (tx_bytes[i]) begin
    bfm.write(THR, {24'h0, tx_bytes[i]}, resp);
  end
  $display("[%0t] Pushed %0d bytes into the TX FIFO", $time, tx_bytes.size());

  bfm.write(IER, {24'h0, IER_ETBEI}, resp);
  if (event_o !== 1'b0) begin
    $error("[%0t] THRE interrupt asserted while TX FIFO is non-empty", $time);
    errors++;
  end
  else
    $display("[%0t] ETBEI enabled, no interrupt while TX FIFO is full", $time);

  bfm.wait_irq();
  $display("[%0t] IRQ raised once TX FIFO drained (THRE set)", $time);

  bfm.read(IIR, rdata, resp);
  $display("[%0t] IIR = 0x%02x (IIR_o=0x%01x)", $time, rdata[7:0], rdata[3:0]);
  if (rdata[3:0] !== IIR_THRE) begin
    $error("[%0t] IIR_o=0x%01x, expected 0x%01x (THRE)", $time, rdata[3:0], IIR_THRE);
    errors++;
  end

  // Mask the source again so the run ends cleanly.
  bfm.write(IER, {24'h0, 8'h00}, resp);
  bfm.read (IIR, rdata, resp);

  if (errors == 0)
    $display("[%0t] test_thre_interrupt PASSED", $time);
  else
    $display("[%0t] test_thre_interrupt FAILED (%0d errors)", $time, errors);

endtask
