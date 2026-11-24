/**
 * Test ID : 5
 * File    : test_rx_irq.sv
 * Brief   : Drives the UART receiver with an external transmitter. The
 *           uart_tx_model serializes a set of bytes onto the DUT rx line
 *           (8N1, 115200 baud). Program the IER[0] to enable data ready interrupt.
  For each byte the test polls LSR[0] (Data
 *           Ready), reads the byte back from the RX buffer (RBR) and compares
 *           it against what was transmitted. This exercises the UART purely on
 *           the receive path, with no TX->RX loopback involved.
 */
task automatic test_rx_irq();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] RBR = 12'h0; // RX buffer / TX holding (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2; // fifo control register
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register
  localparam logic [APB_ADDR_WIDTH-1:0] IIR = 12'h2; // interrupt identification
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable       (DLAB=0)

  // 8N1: 8 data bits (LCR[1:0]=11), no parity (LCR[3]=0), 1 stop bit (LCR[2]=0).
  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches
  localparam logic [7:0] IER_EDRI     = 8'h01; // Enable Data Ready interrupt
  localparam logic [1:0] FCR_TL1      = 2'b00; // Trigger level 1 byte
  localparam logic [1:0] FCR_TL4      = 2'b01; // Trigger level 4 bytes
  localparam logic [1:0] FCR_TL8      = 2'b10; // Trigger level 8 bytes
  localparam logic [1:0] FCR_TL14     = 2'b11; // Trigger level 14 bytes

  // Line Status Register bit positions.
  localparam int LSR_DR = 0; // Data Ready: RX FIFO holds a byte

  // Baud divisor = round(f_clk / baud) - 1. At 100 MHz, 115200 baud -> div = 867.
  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  // Bytes the external transmitter pushes into the receiver. Distinct values so
  // a mismatch points at a specific position.
  byte unsigned tx_bytes[] = '{8'h55, 8'hA3, 8'h00, 8'hFF, 8'h5A, 8'h7E, 8'h81};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;
  logic [7:0] got [$];
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

  bfm.write(IER, {24'h0, IER_EDRI}, resp);
  $display("[%0t] IER = 0x%02x (Data Ready interrupt enabled)", $time, IER_EDRI);

  // Set FIFO trigger level to 4 bytes and enable FIFO mode.
  bfm.write(FCR, {24'h0, FCR_TL4, 6'h1}, resp);
  $display("[%0t] FIFO mode enabled", $time);
  $display("[%0t] FCR = 0x%02x", $time, {24'h0, FCR_TL4, 6'h0});

  fork // Start parallel block for transmitting and receiving bytes
  begin
    // Transmit each byte serially, then read it back from the RX buffer.
    foreach (tx_bytes[i]) begin
      logic [7:0] sent = tx_bytes[i];

      utx.send_byte(sent);
      $display("[%0t] RX-in  byte[%0d] = 0x%02x (serial)", $time, i, sent);
    end
  end
  begin
    bfm.wait_irq(5000);
    $display("[%0t] IRQ raised: rx data is ready (ERBI set)", $time);
    for (int i = 0; i < 'd4; i++) begin
      // read BFM IRQ status
      bfm.read(RBR, rdata, resp);
      $display("[%0t] RBR = 0x%02x", $time, rdata[7:0]);
      got.push_back(rdata[7:0]);
    end

    // Below the trigger level no more IRQs are raised: poll LSR[0] for the
    // remaining bytes.
    while (got.size() < tx_bytes.size()) begin
      poll = 0;
      do begin
        bfm.read(LSR, rdata, resp);
        poll++;
      end while (!rdata[LSR_DR] && poll < 20000);

      if (!rdata[LSR_DR]) begin
        $error("[%0t] Timeout waiting for byte %0d (LSR=0x%02x)",
               $time, got.size(), rdata[7:0]);
        break;
      end
      bfm.read(RBR, rdata, resp);
      $display("[%0t] RBR = 0x%02x", $time, rdata[7:0]);
      got.push_back(rdata[7:0]);
    end
  end
  join
  bfm.read(IIR, rdata, resp);
  $display("[%0t] IIR = 0x%02x (IIR_o=0x%01x)", $time, rdata[7:0], rdata[3:0]);

  if (got.size() != tx_bytes.size()) begin
    $error("[%0t] Received %0d bytes, expected %0d",
           $time, got.size(), tx_bytes.size());
    errors++;
  end

  foreach (tx_bytes[i]) begin
    if (i >= got.size()) break;
    if (got[i] !== tx_bytes[i]) begin
      $error("[%0t] MISMATCH byte[%0d]: got 0x%02x, expected 0x%02x",
             $time, i, got[i], tx_bytes[i]);
      errors++;
    end
    else
      $display("[%0t] byte[%0d] OK: 0x%02x", $time, i, got[i]);
  end

  if (errors == 0)
    $display("[%0t] test_rx_irq PASSED: %0d bytes matched", $time, tx_bytes.size());
  else
    $display("[%0t] test_rx_irq FAILED: %0d error(s)", $time, errors);

endtask