set work "/home/asura/Projects/GitHub/rv32im-riscv-processor"
set pdk  "/home/asura/Projects/pdk"


read_liberty $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_lef     $pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
read_lef     $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

read_verilog $work/scripts/synth/riscv_top_netlist.v
link_design riscv_top
read_sdc constraints.sdc

initialize_floorplan -die_area "0 0 500 500" \
                     -core_area "50 50 450 450" \
                     -site unithd \

make_tracks

insert_tiecells sky130_fd_sc_hd__conb_1/HI 
insert_tiecells sky130_fd_sc_hd__conb_1/LO
# 1. Define global power and ground nets for the core
add_global_connection -net VDD -inst_pattern .* -pin_pattern VPWR -power
add_global_connection -net VDD -inst_pattern .* -pin_pattern VPB  -power
add_global_connection -net VSS -inst_pattern .* -pin_pattern VGND -ground
add_global_connection -net VSS -inst_pattern .* -pin_pattern VNB  -ground

global_connect

# 3. Generate the Power Delivery Network (PDN) using default rules
pdngen

place_pins -hor_layers met3 -ver_layers met2

global_placement
detailed_placement

global_route
detailed_route

write_def riscv_top.def
report_checks -fields {input_pin slews cap delay}