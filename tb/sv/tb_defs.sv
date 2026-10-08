`ifndef TB_DEFS_SV
`define TB_DEFS_SV

// -----------------------------------------------------
// CLOCK Period Defines
// -----------------------------------------------------
`ifndef CLK_PERIOD
  `define CLK_PERIOD            10 // Clock period in ns
`endif // CLK_PERIOD

`ifndef CLK_SKEW
  `define CLK_SKEW              0 // Clock skew in ns
`endif // CLK_SKEW

`define CLOCK_GEN(CLK_PERIOD, CLK_SKEW, CLKN_PERIOD, CLK_SRC)               \
  initial begin                                                             \
    ``CLK_SRC``                                         = 1'b0;             \
    #((``CLK_PERIOD``/2.0)+``CLK_SKEW``)    ``CLK_SRC`` = 1'b1;             \
    forever                                                                 \
    #(``CLKN_PERIOD``/2.0)                  ``CLK_SRC`` = ~``CLK_SRC``;     \
  end
`endif // TB_DEFS_SV
