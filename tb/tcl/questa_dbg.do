### QuestaSim TCL script for waveform configuration and plotting

##########################################################
## top-level variables
##########################################################

if {[info exists env(UART_ROOT)]} {
  set tb_root $env(UART_ROOT)/tb
} else {
  puts "UART_ROOT not set"
}

# 1. Record all signals recursively for waveform viewing.
log -r /*

# 2. Open the wave viewer and plot the AXI interfaces.
#    The script lives next to this do-file.
do $tb_root/tcl/questa_waves.tcl

# 3. Run the selected test to completion (left interactive for inspection).
run -all

wave zoom full