/**
 * Test ID : 4
 * File    : test_rx_bytes.sv
 * Brief   : Drives the UART receiver with an external transmitter. The
 *           uart_tx_model serializes a set of bytes onto the DUT rx line
 *           (8N1, 115200 baud). For each byte the test polls LSR[0] (Data
 *           Ready), reads the byte back from the RX buffer (RBR) and compares
 *           it against what was transmitted. This exercises the UART purely on
 *           the receive path, with no TX->RX loopback involved.
 */
task automatic test_rx_bytes();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] RBR = 12'h0; // RX buffer / TX holding (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2; // fifo control register
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register

  // 8N1: 8 data bits (LCR[1:0]=11), no parity (LCR[3]=0), 1 stop bit (LCR[2]=0).
  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches

  // Line Status Register bit positions.
  localparam int LSR_DR = 0; // Data Ready: RX FIFO holds a byte

  // Baud divisor = round(f_clk / baud) - 1. At 100 MHz, 115200 baud -> div = 867.
  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  // Bytes the external transmitter pushes into the receiver. Distinct values so
  // a mismatch points at a specific position.
  byte unsigned rx_bytes[] = '{8'h55, 8'hA3, 8'h00, 8'hFF, 8'h5A, 8'h7E, 8'h81};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;

  // Program the baud divisor behind the DLAB bit.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},   resp);
  bfm.write(DLL, {24'h0, BAUD_DIV[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV[15:8]}, resp);

  // Switch back to normal 8N1 access (DLAB cleared) and clear both FIFOs.
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  bfm.write(FCR, 32'h0000_0006, resp); // FCR[1]=rx clr, FCR[2]=tx clr
  $display("[%0t] UART configured: 115200 8N1 (div=%0d), FIFOs cleared",
           $time, BAUD_DIV);

  // Match the external TX model's framing to the DUT configuration and idle
  // the serial line (mark) before the first frame.
  utx.configure(.baud_div(BAUD_DIV), .data_bits(8), .parity_en(1'b0),
                .stop_bits(1));
  utx.init();

  // RX path must start empty (no data ready).
  bfm.read(LSR, rdata, resp);
  if (rdata[LSR_DR])
    $error("[%0t] DR set before any byte received (LSR=0x%02x)", $time, rdata[7:0]);

  // Transmit each byte serially, then read it back from the RX buffer.
  foreach (rx_bytes[i]) begin
    logic [7:0] sent = rx_bytes[i];
    logic [7:0] got;

    utx.send_byte(sent);
    $display("[%0t] RX-in  byte[%0d] = 0x%02x (serial)", $time, i, sent);

    // Poll LSR[0] (Data Ready) until the received byte is available.
    poll = 0;
    do begin
      bfm.read(LSR, rdata, resp);
      if (++poll > 100000)
        $fatal(1, "[test_rx_bytes] TIMEOUT waiting for RX byte[%0d]", i);
    end while (!rdata[LSR_DR]);

    // Read the received byte back from RBR and compare against what was sent.
    bfm.read(RBR, rdata, resp);
    got = rdata[7:0];
    if (got === sent)
      $display("[%0t] RX-out byte[%0d] = 0x%02x  PASS", $time, i, got);
    else begin
      $error("[%0t] RX-out byte[%0d] = 0x%02x  MISMATCH (expected 0x%02x)",
             $time, i, got, sent);
      errors++;
    end
  end

  // After draining every byte the receiver must report empty again.
  bfm.read(LSR, rdata, resp);
  if (rdata[LSR_DR])
    $error("[%0t] DR still set after draining all bytes (LSR=0x%02x)",
           $time, rdata[7:0]);

  if (errors == 0)
    $display("[%0t] test_rx_bytes PASSED (%0d bytes)", $time, rx_bytes.size());
  else
    $display("[%0t] test_rx_bytes FAILED (%0d mismatches)", $time, errors);

endtask
