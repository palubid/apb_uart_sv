/**
 * File    : uart_if.sv
 * License : MIT license
 * Brief   : Serial interface carrying the single UART line that the external
 *           UART TX model drives into the DUT's receiver input (rx_i).
 *
 * The line idles high (UART mark state). The `uart_tx_model` drives `rx`
 * procedurally through a virtual interface handle, while the DUT samples the
 * same net on its rx_i port. `clk` is provided so the model can align its bit
 * cells to the DUT's sample clock, matching the DUT's baud divisor.
 */
interface uart_if (
  input logic clk
);
  // Serial line into the DUT receiver (model TX output == DUT rx_i).
  logic rx;

endinterface : uart_if
