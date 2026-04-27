create_clock -name clk -period 10.0 [get_ports clk]

set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition 0.15 [get_clocks clk]


set_input_delay -clock clk 2.0 [get_ports rst]

set_output_delay -clock clk 2.0 [get_ports halt]
set_output_delay -clock clk 2.0 [get_ports trace_writeback_pc*]
set_output_delay -clock clk 2.0 [get_ports trace_writeback_inst*]

set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 [get_ports rst]

set_load 0.05 [all_outputs]

