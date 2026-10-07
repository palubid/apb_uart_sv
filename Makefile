#======================================================================
# Makefile - apb_uart_sv
#
# Generates a QuestaSim compile file list from the Bender manifest
# (Bender.yml) and tests the compilation/elaboration of the apb_uart_sv
# module with QuestaSim (vlog/vopt).
#
# The simulator environment is provided via `module load questa`.
#
# Targets:
#   make flist     - (default) generate the file list apb_uart_sv.f
#   make compile   - compile + elaborate the file list with QuestaSim
#   make verify    - check that every path in the file list exists
#   make clean     - remove the generated file list
#   make distclean - also remove QuestaSim work library and artifacts
#======================================================================

# Absolute path to this repository root (dir containing this Makefile)
export UART_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Tools
BENDER ?= bender

# QuestaSim tools (available after `module load questa`)
VLIB ?= vlib
VLOG ?= vlog
VOPT ?= vopt

# Top module to elaborate
TOP ?= apb_uart_sv

# Generated file list
FLIST := $(UART_ROOT)/src/apb_uart_sv.f

# QuestaSim work library
QUESTA_LIB := work

# Bender targets for a synthesizable RTL-only elaboration
BENDER_TARGETS := -t rtl

# Shell used to run QuestaSim after loading its environment module
MODULE_LOAD := module load questa

.PHONY: all flist compile verify clean distclean help

all: flist

help:
	@echo "Targets:"
	@echo "  flist      - generate the file list apb_uart_sv.f (default)"
	@echo "  compile    - compile + elaborate the file list with QuestaSim"
	@echo "  verify     - check that every path in the file list exists"
	@echo "  clean      - remove the generated file list"
	@echo "  distclean  - also remove QuestaSim work library and artifacts"

#----------------------------------------------------------------------
# 1. Generate the file list via bender, rebased to $${UART_ROOT}
#----------------------------------------------------------------------
$(FLIST): Bender.yml
	@echo ">> bender script flist-plus -> $@"
	cd $(UART_ROOT) && $(BENDER) script flist-plus $(BENDER_TARGETS) \
	  | sed -E 's#$(UART_ROOT)#$${UART_ROOT}#g' > $@
	@echo ">> wrote $@ ($$(grep -cE '\.(sv|v)$$' $@ 2>/dev/null) source files)"

flist: $(FLIST)

#----------------------------------------------------------------------
# 2. Verify all paths resolve
#----------------------------------------------------------------------
verify: $(FLIST)
	@echo ">> verifying paths in $(FLIST)"
	@UART_ROOT="$(UART_ROOT)"; miss=0; \
	while IFS= read -r line; do \
	  case "$$line" in ''|//*|+*) continue;; esac; \
	  f=$$(eval echo "$$line"); \
	  if [ ! -f "$$f" ]; then echo "MISSING: $$line"; miss=$$((miss+1)); fi; \
	done < $(FLIST); \
	if [ $$miss -ne 0 ]; then echo "FAILED: $$miss missing file(s)"; exit 1; \
	else echo "OK: all files present"; fi

#----------------------------------------------------------------------
# 3. Compile + elaborate with QuestaSim
#     Loads the simulator environment with `module load questa`.
#----------------------------------------------------------------------
compile: $(FLIST)
	@echo ">> questa compile (vlog + vopt)"
	bash -c '$(MODULE_LOAD) && \
		UART_ROOT="$(UART_ROOT)" $(VLIB) $(QUESTA_LIB) && \
		UART_ROOT="$(UART_ROOT)" $(VLOG) -sv -work $(QUESTA_LIB) -f $(FLIST) && \
		UART_ROOT="$(UART_ROOT)" $(VOPT) -work $(QUESTA_LIB) $(TOP) -o $(TOP)_opt'

#----------------------------------------------------------------------
# Cleanup
#----------------------------------------------------------------------
clean:
	rm -f $(FLIST)

distclean: clean
	rm -rf $(QUESTA_LIB) transcript vsim.wlf modelsim.ini *.vstf
