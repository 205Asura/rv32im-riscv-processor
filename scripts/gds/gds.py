import pya

# Initialize an empty layout canvas
layout = pya.Layout()

print("1. Configuring LEF/DEF reader...")
opt = pya.LoadLayoutOptions()

# Safely extract the config, assign the LEF paths, and push it back
config = opt.lefdef_config
config.lef_files = [
    "../pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef",
    "../pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
]
opt.lefdef_config = config

print("2. Reading OpenROAD DEF routing...")
layout.read("../pd/riscv_top.def", opt)

print("3. Merging Sky130 Foundry standard cell transistors...")
# By default, reading a second file injects its polygons into the existing cell names
layout.read("../pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds")

print("4. Saving final GDS...")
layout.write("riscv_top.gds")

print("Success! Layout merged.")