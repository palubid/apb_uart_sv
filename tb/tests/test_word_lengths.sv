/**
 * Test ID : 9
 * File    : test_word_lengths.sv
 * Brief   : Exercises every supported character length (5, 6, 7 and 8 data
 *           bits, LCR[1:0] = 00/01/10/11) through an internal serial loopback
 *           (tx_o mirrored onto rx_i) at 115200 baud, no parity, 1 stop bit.
 *           For each width a set of patterns is transmitted and read back; the
 *           receiver zero-fills the unused upper bits, so the expected readback
 *           is the transmitted byte masked to the active width. This validates
 *           the s_target_bits decode in both uart_tx and uart_rx.
 */
task automatic test_word_lengths();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] THR = 12'h0; // TX holding / RX buffer (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2; // fifo control register
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register

  localparam logic [7:0] LCR_DLAB = 8'h80; // DLAB only, to expose DLL/DLM

  localparam int LSR_DR = 0; // Data Ready: RX FIFO holds a byte

  // Baud divisor = round(f_clk / baud) - 1.
  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  // Patterns pushed at every width; low bits chosen so the masked value is
  // distinct across positions.
  byte unsigned pattern[] = '{8'h55, 8'hAA, 8'hFF, 8'h00, 8'h3C, 8'h81};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;

  // Internal loopback: mirror the serial TX line onto RX. Sampling on the
  // negedge keeps rx_i stable ahead of the DUT's posedge rx synchronizer.
  fork
    forever @(negedge clk) uart_if_inst.rx = tx_o;
  join_none

  // Program the baud divisor once behind the DLAB bit (the per-width LCR writes
  // below clear DLAB but leave the stored divisor latches intact).
  bfm.write(LCR, {24'h0, LCR_DLAB},      resp);
  bfm.write(DLL, {24'h0, BAUD_DIV[7:0]}, resp);
  bfm.write(DLM, {24'h0, BAUD_DIV[15:8]},resp);
  $display("[%0t] UART baud configured: 115200 (div=%0d)", $time, BAUD_DIV);

  // Sweep 5..8 data bits.
  for (int wl = 5; wl <= 8; wl++) begin
    logic [7:0] lcr_val = (wl - 5); // LCR[1:0]=word-length code, DLAB/parity/stop=0
    logic [7:0] mask    = 8'hFF >> (8 - wl);

    bfm.write(LCR, {24'h0, lcr_val}, resp);
    bfm.write(FCR, 32'h0000_0006, resp); // flush both FIFOs between widths
    $display("[%0t] --- word length = %0d bits (LCR=0x%02x, mask=0x%02x) ---",
             $time, wl, lcr_val, mask);

    foreach (pattern[i]) begin
      logic [7:0] sent = pattern[i] & mask; // only the low `wl` bits are framed
      logic [7:0] got;

      bfm.write(THR, {24'h0, pattern[i]}, resp);

      poll = 0;
      do begin
        bfm.read(LSR, rdata, resp);
        if (++poll > 100000)
          $fatal(1, "[test_word_lengths] TIMEOUT waiting for RX (wl=%0d, byte[%0d])",
                 wl, i);
      end while (!rdata[LSR_DR]);

      bfm.read(THR, rdata, resp);
      got = rdata[7:0];
      if (got === sent)
        $display("[%0t] wl=%0d byte[%0d] = 0x%02x  PASS", $time, wl, i, got);
      else begin
        $error("[%0t] wl=%0d byte[%0d] = 0x%02x  MISMATCH (expected 0x%02x)",
               $time, wl, i, got, sent);
        errors++;
      end
    end
  end

  if (errors == 0)
    $display("[%0t] test_word_lengths PASSED", $time);
  else
    $display("[%0t] test_word_lengths FAILED (%0d mismatches)", $time, errors);

endtask
