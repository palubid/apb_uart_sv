###############################################################################
## Makefile for the Verilog Testbench — soc_top
##
###############################################################################

-include ../Makefile

export TB_DIR								:= $(UART_ROOT)/tb
export TB_TOP								?= tb_uart
LOGS_DIR 										:= $(TB_DIR)/logs
SIM_DIR 										:= $(TB_DIR)/sim

# TB source files
TB_SRCS 										:= $(TB_DIR)/sv/tb.sv

###############################################################################
## Simulation options
###############################################################################

QUESTA_TOP_OPT  := $(TB_TOP)_opt

QUESTA_INCDIRS := \
	+incdir+$(TB_DIR)/sv

VLOG_OPTS := \
	-sv \
	-timescale 1ns/1ps \
	-work $(QUESTA_LIB) \
	$(QUESTA_DEFINES) \
	$(QUESTA_INCDIRS)

VOPT_OPTS := \
	-work $(QUESTA_LIB)

ifdef DEBUG
	VSIM_RUN_OPTS	:= -do "log -r /*" -do $(TB_DIR)/tcl/questa.tcl -do "run -all" -do "wave zoom full"
	VOPT_OPTS 		+= -debugdb +access +r
else
	VSIM_RUN_OPTS := -c -do "run -all; quit"
endif

###############################################################################
## Targets
###############################################################################

## Create logs directory if it doesn't exist
$(LOGS_DIR):
	mkdir -p $@

## Create simulation directory if it doesn't exist
$(SIM_DIR):
	mkdir -p $@

## Create both logs and simulation directories if they don't exist
all_dirs: $(LOGS_DIR) $(SIM_DIR)

## Default target
all: run-questa

## QuestaSim compile: DUT file list + TB, then elaborate into $(QUESTA_TOP_OPT)
$(SIM_DIR)/$(QUESTA_LIB)/$(QUESTA_TOP_OPT): $(FLIST) | $(LOGS_DIR) $(SIM_DIR)
	cd $(SIM_DIR) && $(VLIB) $(QUESTA_LIB)
	cd $(SIM_DIR) && $(VLOG) \
		$(VLOG_OPTS) \
		-f $(FLIST) \
		$(TB_SRCS) \
		-l $(LOGS_DIR)/questa_compile.log
	cd $(SIM_DIR) && $(VOPT) \
		$(VOPT_OPTS) \
		$(TB_TOP) \
		-o $(QUESTA_TOP_OPT)

## QuestaSim run: load the elaborated design and run to completion
run-questa: $(SIM_DIR)/$(QUESTA_LIB)/$(QUESTA_TOP_OPT) | $(LOGS_DIR) $(SIM_DIR)
	cd $(SIM_DIR) && $(VSIM) \
		$(QUESTA_LIB).$(QUESTA_TOP_OPT) \
		$(VSIM_RUN_OPTS) \
		-l $(LOGS_DIR)/questa_sim__.log

clean-sim:
	rm -rf $(SIM_DIR)/*
	rm -rf $(LOGS_DIR)/*

.PHONY: all_dirs all run-questa clean-sim
