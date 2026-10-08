### QuestaSim TCL script for waveform configuration and plotting

if {![info exists tb_root]} {
  if {[info exists env(UART_ROOT)]} {
    set tb_root $env(UART_ROOT)/tb
  } else {
    puts "UART_ROOT not set"
  }
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

add wave -divider {uart registers}
add wave /$tb/u_apb_uart_sv/register_adr
add wave /$tb/u_apb_uart_sv/regs_q

add wave -divider {uart TX}
add wave /$tb/u_apb_uart_sv/fifo_tx_valid
add wave /$tb/u_apb_uart_sv/fifo_tx_data
add wave /$tb/u_apb_uart_sv/tx_valid
add wave /$tb/u_apb_uart_sv/tx_ready
add wave /$tb/u_apb_uart_sv/tx_data
add wave /$tb/u_apb_uart_sv/tx_elements
add wave /$tb/u_apb_uart_sv/uart_tx_i/CS
add wave /$tb/u_apb_uart_sv/uart_tx_i/reg_data
add wave /$tb/u_apb_uart_sv/uart_tx_i/reg_bit_count
add wave /$tb/u_apb_uart_sv/uart_tx_i/bit_done

add wave -divider {uart ports}
add wave -color "orange" /$tb/u_apb_uart_sv/tx_o
add wave -color "orange red" /$tb/u_apb_uart_sv/rx_i
add wave /$tb/u_apb_uart_sv/event_o