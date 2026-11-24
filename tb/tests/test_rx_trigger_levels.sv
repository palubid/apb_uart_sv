/**
 * Test ID : 10
 * File    : test_rx_trigger_levels.sv
 * Brief   : Exercises all four 16550 RX FIFO interrupt trigger levels
 *           (FCR[7:6] = 00/01/10/11 -> 1/4/8/14 bytes). For each level the
 *           external TX model drives bytes into the receiver while the Received
 *           Data Available interrupt is enabled (IER[0], FIFO mode). The test
 *           checks that event_o stays low below the trigger threshold, asserts
 *           exactly when the fill level reaches it, that the buffered bytes read
 *           back in order, and that event_o drops once drained below threshold.
 */

// Run one trigger-level scenario: re-arm the FIFO with `code`, push `count`
// bytes, and verify the interrupt threshold, data integrity and deassertion.
task automatic trig_check(input logic [1:0] code, input int count, ref int errors);

  localparam logic [APB_ADDR_WIDTH-1:0] RBR = 12'h0;
  localparam logic [APB_ADDR_WIDTH-1:0] FCR = 12'h2;

  apb_resp_e   resp;
  logic [31:0] rdata;
  byte unsigned sent[$];
  logic [7:0]  got;
  bit          asserted;
  int          c;

  // Enable FIFO mode, flush both FIFOs and program the trigger level.
  // FCR = {trigger[7:6], 3'b000, tx_clr, rx_clr, fifo_en} = {code, 6'b000111}.
  bfm.write(FCR, {24'h0, code, 6'h07}, resp);
  repeat (5) @(posedge clk);
  if (event_o !== 1'b0) begin
    $error("[%0t] TL%0d: event_o set with empty FIFO", $time, count);
    errors++;
  end

  // Fill up to one below the threshold; the interrupt must stay quiet.
  for (int i = 0; i < count - 1; i++) begin
    byte unsigned b = 8'hC0 + i[7:0];
    sent.push_back(b);
    utx.send_byte(b);
  end
  repeat (5) @(posedge clk);
  if (count > 1 && event_o !== 1'b0) begin
    $error("[%0t] TL%0d: event_o asserted at %0d bytes (below threshold)",
           $time, count, count - 1);
    errors++;
  end

  // The byte that reaches the threshold must raise the interrupt.
  begin
    byte unsigned b = 8'hC0 + (count - 1);
    sent.push_back(b);
    utx.send_byte(b);
  end

  asserted = 1'b0;
  for (c = 0; c < 4000; c++) begin
    @(posedge clk);
    if (event_o === 1'b1) begin asserted = 1'b1; break; end
  end
  if (asserted)
    $display("[%0t] TL%0d: RDA interrupt asserted at threshold", $time, count);
  else begin
    $error("[%0t] TL%0d: RDA interrupt never asserted at %0d bytes",
           $time, count, count);
    errors++;
  end

  // Read the buffered bytes back in order and compare.
  foreach (sent[i]) begin
    bfm.read(RBR, rdata, resp);
    got = rdata[7:0];
    if (got === sent[i])
      $display("[%0t] TL%0d byte[%0d] = 0x%02x  PASS", $time, count, i, got);
    else begin
      $error("[%0t] TL%0d byte[%0d] = 0x%02x  MISMATCH (expected 0x%02x)",
             $time, count, i, got, sent[i]);
      errors++;
    end
  end

  // Draining below the threshold must deassert the interrupt.
  repeat (5) @(posedge clk);
  if (event_o !== 1'b0) begin
    $error("[%0t] TL%0d: event_o still set after draining FIFO", $time, count);
    errors++;
  end
  else
    $display("[%0t] TL%0d: event_o deasserted after drain", $time, count);

endtask

task automatic test_rx_trigger_levels();

  // UART register offsets (word-addressed register file, PADDR[2:0]).
  localparam logic [APB_ADDR_WIDTH-1:0] DLL = 12'h0; // divisor latch low  (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] IER = 12'h1; // interrupt enable   (DLAB=0)
  localparam logic [APB_ADDR_WIDTH-1:0] DLM = 12'h1; // divisor latch high (DLAB=1)
  localparam logic [APB_ADDR_WIDTH-1:0] LCR = 12'h3; // line control register

  localparam logic [7:0] LCR_8N1      = 8'h03;
  localparam logic [7:0] LCR_8N1_DLAB = 8'h83;
  localparam logic [7:0] IER_ERBFI    = 8'h01; // Received Data Available interrupt enable

  int  BAUD = 115200;
  real DIV  = (100_000_000 / `CLK_PERIOD / BAUD) - 1; // `CLK_PERIOD` in ns
  logic [15:0] BAUD_DIV = int'(DIV);

  apb_resp_e resp;
  int        errors = 0;

  // Program the baud divisor behind DLAB, then return to 8N1 access.
  bfm.write(LCR, {24'h0, LCR_8N1_DLAB},   resp);
  bfm.write(DLL, {24'h0, BAUD_DIV[7:0]},  resp);
  bfm.write(DLM, {24'h0, BAUD_DIV[15:8]}, resp);
  bfm.write(LCR, {24'h0, LCR_8N1}, resp);
  $display("[%0t] UART configured: 115200 8N1 (div=%0d)", $time, BAUD_DIV);

  // Match the external TX model framing and idle the line.
  utx.configure(.baud_div(BAUD_DIV), .data_bits(8), .parity_en(1'b0),
                .stop_bits(1));
  utx.init();

  // Enable the Received Data Available interrupt for the whole run.
  bfm.write(IER, {24'h0, IER_ERBFI}, resp);
  $display("[%0t] IER = 0x%02x (RDA interrupt enabled)", $time, IER_ERBFI);

  // Trigger levels: FCR[7:6] = 00/01/10/11 -> 1/4/8/14 bytes.
  trig_check(2'b00, 1,  errors);
  trig_check(2'b01, 4,  errors);
  trig_check(2'b10, 8,  errors);
  trig_check(2'b11, 14, errors);

  if (errors == 0)
    $display("[%0t] test_rx_trigger_levels PASSED", $time);
  else
    $display("[%0t] test_rx_trigger_levels FAILED (%0d errors)", $time, errors);

endtask
