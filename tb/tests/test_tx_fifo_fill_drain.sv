/**
 * Test ID : 3
 * File    : test_tx_fifo_fill_drain.sv
 * Brief   : Fills the TX FIFO to its full depth (TX_FIFO_DEPTH bytes) with
 *           back-to-back APB writes, confirms the FIFO reports non-empty
 *           (LSR[5]=THRE deasserted), then waits for the UART to transmit every
 *           byte and fully drain (LSR[6]=TEMT asserted). An internal serial
 *           loopback mirrors tx_o onto rx_i so each transmitted byte is read
 *           back from the RX FIFO and compared against what was sent.
 */
task automatic test_tx_fifo_fill_drain();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] THR = 12'h0; // TX holding / RX buffer (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2; // fifo control register
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register

  // 8N1: 8 data bits (LCR[1:0]=11), no parity (LCR[3]=0), 1 stop bit (LCR[2]=0).
  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches

  // Line Status Register bit positions.
  localparam int LSR_DR   = 0; // Data Ready: RX FIFO holds a byte
  localparam int LSR_THRE = 5; // TX FIFO empty
  localparam int LSR_TEMT = 6; // TX FIFO and shift register both empty

  // TX FIFO depth in bytes (must match apb_uart_sv TX_FIFO_DEPTH).
  localparam int TX_FIFO_DEPTH = 16;

  // Baud divisor = round(f_clk / baud) - 1. At 100 MHz, 115200 baud -> div = 867.
  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;

  // Bytes pushed into the TX FIFO. A full FIFO's worth of distinct values so a
  // mismatch on readback points at a specific position.
  byte unsigned tx_bytes[TX_FIFO_DEPTH];
  foreach (tx_bytes[i])
    tx_bytes[i] = 8'hA0 + i[7:0];

  // Internal loopback: mirror the serial TX line onto RX. Sampling on the
  // negedge keeps rx_i stable ahead of the DUT's posedge rx synchronizer.
  fork
    forever @(negedge clk) uart_if_inst.rx = tx_o;
  join_none

  // Program the baud divisor behind the DLAB bit.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},   resp);
  bfm.write(DLL, {24'h0, BAUD_DIV[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV[15:8]}, resp);

  // Switch back to normal 8N1 access (DLAB cleared) and clear both FIFOs.
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  bfm.write(FCR, 32'h0000_0006, resp); // FCR[1]=rx clr, FCR[2]=tx clr
  $display("[%0t] UART configured: 115200 8N1 (div=%0d), FIFOs cleared",
           $time, BAUD_DIV);

  // Confirm the TX path starts empty.
  bfm.read(LSR, rdata, resp);
  if (!rdata[LSR_THRE] || !rdata[LSR_TEMT])
    $error("[%0t] TX FIFO not empty at start (LSR=0x%02x)", $time, rdata[7:0]);

  // Fill the TX FIFO with back-to-back writes. The APB writes complete far
  // faster than the UART can serialize a single byte at 115200 baud, so the
  // FIFO fills before it begins to drain.
  foreach (tx_bytes[i]) begin
    bfm.write(THR, {24'h0, tx_bytes[i]}, resp);
    $display("[%0t] TX  byte[%2d] = 0x%02x", $time, i, tx_bytes[i]);
  end
  $display("[%0t] Pushed %0d bytes into the TX FIFO", $time, TX_FIFO_DEPTH);

  // With a full FIFO, the TX path must report non-empty.
  bfm.read(LSR, rdata, resp);
  if (rdata[LSR_THRE])
    $error("[%0t] THRE set after filling TX FIFO (LSR=0x%02x) - FIFO not full",
           $time, rdata[7:0]);
  else
    $display("[%0t] TX FIFO filled: THRE=0, TEMT=%0b (LSR=0x%02x)",
             $time, rdata[LSR_TEMT], rdata[7:0]);

  // Read every byte back through the loopback, draining it from the RX FIFO as
  // the TX FIFO empties.
  foreach (tx_bytes[i]) begin
    logic [7:0] sent = tx_bytes[i];
    logic [7:0] got;

    poll = 0;
    do begin
      bfm.read(LSR, rdata, resp);
      if (++poll > 1000000)
        $fatal(1, "[test_tx_fifo_fill_drain] TIMEOUT waiting for RX byte[%0d]", i);
    end while (!rdata[LSR_DR]);

    bfm.read(THR, rdata, resp);
    got = rdata[7:0];
    if (got === sent)
      $display("[%0t] RX  byte[%2d] = 0x%02x  PASS", $time, i, got);
    else begin
      $error("[%0t] RX  byte[%2d] = 0x%02x  MISMATCH (expected 0x%02x)",
             $time, i, got, sent);
      errors++;
    end
  end

  // After all bytes are transmitted the TX FIFO and shift register must be
  // empty again (fully drained).
  poll = 0;
  do begin
    bfm.read(LSR, rdata, resp);
    if (++poll > 1000000)
      $fatal(1, "[test_tx_fifo_fill_drain] TIMEOUT waiting for TX drain");
  end while (!rdata[LSR_TEMT]);
  $display("[%0t] TX FIFO drained: THRE=%0b, TEMT=1 (LSR=0x%02x)",
           $time, rdata[LSR_THRE], rdata[7:0]);

  if (!rdata[LSR_THRE])
    $error("[%0t] THRE not set after drain (LSR=0x%02x)", $time, rdata[7:0]);

  if (errors == 0)
    $display("[%0t] test_tx_fifo_fill_drain PASSED (%0d bytes)",
             $time, TX_FIFO_DEPTH);
  else
    $display("[%0t] test_tx_fifo_fill_drain FAILED (%0d mismatches)",
             $time, errors);

endtask
