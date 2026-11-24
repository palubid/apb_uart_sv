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


set RBR 0
set THR 0
set IER 1
set IIR 2
set FCR 2
set LCR 3
set MCR 4
set LSR 5
set MSR 6
set SCR 7
set DLL 8
set DLM 9


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
add wave /$tb/u_apb_uart_sv/wr_adr
add wave -label DLAB /$tb/u_apb_uart_sv/regs_q\[${LCR}\]\[7\]
add wave -label LCR /$tb/u_apb_uart_sv/regs_q\[${LCR}\]
add wave -label LSR /$tb/u_apb_uart_sv/regs_q\[${LSR}\]
add wave -label DLL /$tb/u_apb_uart_sv/regs_q\[${DLL}\]
add wave -label DLM /$tb/u_apb_uart_sv/regs_q\[${DLM}\]
add wave -label FCR /$tb/u_apb_uart_sv/regs_q\[${FCR}\]
add wave -label IER /$tb/u_apb_uart_sv/regs_q\[${IER}\]
add wave -label IIR /$tb/u_apb_uart_sv/regs_q\[${IIR}\]
add wave -divider {uart irq}
add wave /$tb/u_apb_uart_sv/uart_interrupt_i/trigger_level_i
add wave /$tb/u_apb_uart_sv/uart_interrupt_i/RDA_i
add wave /$tb/u_apb_uart_sv/uart_interrupt_i/trigger_level_reached
add wave /$tb/u_apb_uart_sv/uart_interrupt_i/iir_q
add wave /$tb/u_apb_uart_sv/uart_interrupt_i/IIR_o

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

add wave -divider {uart RX}
add wave /$tb/u_apb_uart_sv/fifo_rx_valid
add wave /$tb/u_apb_uart_sv/fifo_rx_data
add wave /$tb/u_apb_uart_sv/rx_valid
add wave /$tb/u_apb_uart_sv/rx_ready
add wave /$tb/u_apb_uart_sv/rx_data
add wave /$tb/u_apb_uart_sv/rx_elements
add wave /$tb/u_apb_uart_sv/uart_rx_i/CS
add wave /$tb/u_apb_uart_sv/uart_rx_i/reg_data
add wave /$tb/u_apb_uart_sv/uart_rx_i/reg_bit_count
add wave /$tb/u_apb_uart_sv/uart_rx_i/bit_done

add wave -divider {uart ports}
add wave -color "orange" /$tb/u_apb_uart_sv/tx_o
add wave -color "orange red" /$tb/u_apb_uart_sv/rx_i
add wave /$tb/u_apb_uart_sv/event_o
