SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Point to the parent directory where the Verilog files live
SRC_DIR = $(PWD)/../rtl/

# Add the source directory to the include path for header.vh
COMPILE_ARGS += -I$(SRC_DIR)
COMPILE_ARGS += -DDIVIDER_STAGES=8

# Update all paths to use SRC_DIR
VERILOG_SOURCES += $(SRC_DIR)/riscv_top.v
VERILOG_SOURCES += $(SRC_DIR)/dataPathPipelined.v
VERILOG_SOURCES += $(SRC_DIR)/memory.v
VERILOG_SOURCES += $(SRC_DIR)/regfile.v
VERILOG_SOURCES += $(SRC_DIR)/dividerUnsignedPipelined.v
VERILOG_SOURCES += $(SRC_DIR)/cla.v

TOPLEVEL = riscv_top
MODULE = testbench

include $(shell cocotb-config --makefiles)/Makefile.sim