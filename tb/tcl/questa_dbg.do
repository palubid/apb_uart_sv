### QuestaSim TCL script for waveform configuration and plotting

##########################################################
## top-level variables
##########################################################

if {[info exists env(UART_ROOT)]} {
  set tb_root $env(UART_ROOT)/tb
} else {
  puts "UART_ROOT not set"
}

##########################################################
## waveform configuration
##########################################################
configure wave -namecolwidth 400
configure wave -valuecolwidth 70
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 6
configure wave -childrowmargin 4
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns

source $tb_root/tcl/questa_apb_waves_procs.tcl

# 1. Record all signals recursively for waveform viewing.
log -r /*

# 2. Open the wave viewer and plot the AXI interfaces.
#    The script lives next to this do-file.
do $tb_root/tcl/questa_waves.tcl

# 3. Run the selected test to completion (left interactive for inspection).
run -all

wave zoom full