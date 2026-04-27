yosys -import
set work "/home/asura/Projects/GitHub/rv32im-riscv-processor"
set pdk  "/home/asura/Projects/pdk"

foreach file [glob -nocomplain $work/rtl/*/*.v] {
    read_verilog -I$work/rtl $file
}

foreach file [glob -nocomplain $work/rtl/*.v] {
    read_verilog -I$work/rtl $file
}



hierarchy -check -top riscv_top

yosys proc
opt; fsm; opt; memory; opt      

techmap; opt

dfflibmap -liberty $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

abc -liberty $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

clean

write_verilog -noattr riscv_top_netlist.v