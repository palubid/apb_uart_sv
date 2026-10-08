/**
 * Test ID : 2
 * File    : test_loopback_115200.sv
 * Brief   : Configures the UART for 115200 baud, 8 data bits, no parity, 1 stop
 *           bit (8N1) and runs an internal serial loopback: tx_o is mirrored
 *           onto rx_i, each transmitted byte is read back from the RX FIFO and
 *           compared against what was sent.
 */
task automatic test_loopback_115200();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] THR = 12'h0; // TX holding / RX buffer (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low      (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high     (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register
  localparam logic [APB_ADDR_WIDTH-1:0] LSR = 12'h5; // line status register

  // 8N1: 8 data bits (LCR[1:0]=11), no parity (LCR[3]=0), 1 stop bit (LCR[2]=0).
  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83; // + DLAB to expose the divisor latches

  // Baud divisor = round(f_clk / baud) - 1; one bit lasts (div+1) clocks and TX
  // and RX share the same divisor. At 100 MHz: 100e6/115200 = 868 -> div = 867.
  int BAUD = 115200;
  real DIV = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // Assuming `CLK_PERIOD` is in ns
  
  // localparam logic [15:0] BAUD_DIV_115200 = 16'd867; // 16'h0363
  // Alternatively, use the calculated DIV value
  logic [15:0] BAUD_DIV_115200 = int'(DIV);

  // Bytes pushed through the TX->RX loopback and checked on the way back.
  byte unsigned tx_bytes[] = '{8'h55, 8'hA3, 8'h00, 8'hFF, 8'h5A};

  apb_resp_e   resp;
  logic [31:0] rdata;
  int unsigned poll;
  int          errors = 0;

  // Internal loopback: mirror the serial TX line onto RX. Sampling on the
  // negedge keeps rx_i stable ahead of the DUT's posedge rx synchronizer.
  fork
    forever @(negedge clk) rx_i = tx_o;
  join_none

  // Program the baud divisor behind the DLAB bit.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},          resp);
  bfm.write(DLL, {24'h0, BAUD_DIV_115200[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV_115200[15:8]}, resp);

  // Switch back to normal 8N1 access (DLAB cleared).
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  $display("[%0t] UART configured: 115200 8N1 (div=%0d)", $time, BAUD_DIV_115200);

  // Send each byte, wait for it to loop back, then read and compare.
  foreach (tx_bytes[i]) begin
    logic [7:0] sent = tx_bytes[i];
    logic [7:0] got;

    bfm.write(THR, {24'h0, sent}, resp);
    $display("[%0t] TX  byte[%0d] = 0x%02x", $time, i, sent);

    // Poll LSR[0] (Data Ready) until the received byte is available.
    poll = 0;
    do begin
      bfm.read(LSR, rdata, resp);
      if (++poll > 100000)
        $fatal(1, "[test_loopback_115200] TIMEOUT waiting for RX byte[%0d]", i);
    end while (!rdata[0]);

    // Read the received byte back from RBR and compare against what was sent.
    bfm.read(THR, rdata, resp);
    got = rdata[7:0];
    if (got === sent)
      $display("[%0t] RX  byte[%0d] = 0x%02x  PASS", $time, i, got);
    else begin
      $error("[%0t] RX  byte[%0d] = 0x%02x  MISMATCH (expected 0x%02x)",
             $time, i, got, sent);
      errors++;
    end
  end

  if (errors == 0)
    $display("[%0t] test_loopback_115200 PASSED (%0d bytes)", $time, tx_bytes.size());
  else
    $display("[%0t] test_loopback_115200 FAILED (%0d mismatches)", $time, errors);

endtask
