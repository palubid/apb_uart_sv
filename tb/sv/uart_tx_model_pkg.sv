/**
 * File    : uart_tx_model_pkg.sv
 * License : MIT license
 * Brief   : Behavioural UART transmitter model used as testbench stimulus. It
 *           serializes bytes onto the UART line (uart_if.rx) so the DUT's
 *           receiver can be exercised exactly as if an external device were
 *           transmitting into it.
 *
 * Frame format (matches apb_uart_sv / uart_rx.sv):
 *   - idle/mark : line held high
 *   - start bit : one low bit
 *   - data bits : `data_bits` bits, LSB first (5..8 bits)
 *   - parity    : optional, EVEN parity over the data bits (parity_en)
 *   - stop bits : `stop_bits` high bits
 *
 * Timing: the DUT uses a baud divisor where one bit cell lasts (div + 1) clock
 * cycles (one bit period = (baud_div + 1) * clk period). The model drives each
 * bit for the same duration and changes the line on the clock's negedge so the
 * value is stable across the DUT's posedge rx synchronizer.
 *
 * Usage:
 *   uart_tx_model utx = new(uart_if_inst);
 *   utx.configure(.baud_div(867), .data_bits(8), .parity_en(0), .stop_bits(1));
 *   utx.init();                 // drive the line to idle (mark)
 *   utx.send_byte(8'h55);       // transmit a single byte
 *   utx.send_bytes('{8'hA5, 8'h3C});
 */
package uart_tx_model_pkg;

  class uart_tx_model;

    // Handle to the serial line driven toward the DUT receiver.
    virtual uart_if vif;

    // Configuration (defaults: 115200 8N1 at 100 MHz -> div = 867).
    int unsigned baud_div  = 867; // DUT baud divisor; bit cell = (baud_div+1) clks
    int unsigned data_bits = 8;   // number of data bits (5..8)
    bit          parity_en = 1'b0;// enable EVEN parity bit after the data bits
    int unsigned stop_bits = 1;   // number of stop (mark) bits

    function new(virtual uart_if vif);
      this.vif = vif;
    endfunction

    // Program the frame format / baud. Call before transmitting; the values
    // must mirror what the DUT register file is programmed with.
    function void configure(
      input int unsigned baud_div,
      input int unsigned data_bits = 8,
      input bit          parity_en = 1'b0,
      input int unsigned stop_bits = 1
    );
      this.baud_div  = baud_div;
      this.data_bits = data_bits;
      this.parity_en = parity_en;
      this.stop_bits = stop_bits;
    endfunction

    // Drive the line to the idle (mark) state. Call once before the first byte.
    task automatic init();
      @(negedge vif.clk);
      vif.rx = 1'b1;
    endtask

    // Drive one bit cell: set the line on a negedge, then hold it for a full
    // (baud_div + 1) clock-period bit time so the DUT samples it mid-cell.
    task automatic drive_bit(input logic b);
      @(negedge vif.clk);
      vif.rx = b;
      repeat (baud_div) @(negedge vif.clk);
    endtask

    // Transmit one byte: start bit, LSB-first data bits, optional EVEN parity,
    // then the configured number of stop bits.
    task automatic send_byte(input byte unsigned data);
      logic parity;

      drive_bit(1'b0); // start bit

      parity = 1'b0;
      for (int i = 0; i < int'(data_bits); i++) begin
        drive_bit(data[i]);
        parity ^= data[i];
      end

      if (parity_en)
        drive_bit(parity); // EVEN parity over the data bits

      repeat (stop_bits) drive_bit(1'b1); // stop bit(s)
    endtask

    // Transmit a stream of bytes back to back.
    task automatic send_bytes(input byte unsigned data[]);
      foreach (data[i])
        send_byte(data[i]);
    endtask

    // Hold the line idle for `n` bit times (inter-frame gap helper).
    task automatic idle(input int unsigned n = 1);
      repeat (n) drive_bit(1'b1);
    endtask

  endclass : uart_tx_model

endpackage : uart_tx_model_pkg
