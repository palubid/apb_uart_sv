### QuestaSim TCL script for waveform configuration and plotting

##########################################################
## top-level variables
##########################################################

set tb $env(TB_TOP)
puts "Testbench: $tb"


##########################################################
## plot waves
##########################################################

add wave -divider tb
add wave /$tb/clk
add wave /$tb/resetn

add wave -divider {interface}
apb_wave_add_apb $tb apb_if_inst "APB_master"

add wave -divider {dut}
add wave /$tb/u_apb_uart_sv/tx_o
add wave /$tb/u_apb_uart_sv/rx_i
add wave /$tb/u_apb_uart_sv/event_o