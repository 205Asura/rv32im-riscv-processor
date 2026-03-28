
`include "header.vh"

module memory #(
    parameter NUM_WORDS = 512
) (
    input                    rst,
    input                    clk,
    input      [`REG_SIZE-1:0] pc_to_imem,
    output reg [`REG_SIZE-1:0] inst_from_imem,
    input      [`REG_SIZE-1:0] addr_to_dmem,
    output reg [`REG_SIZE-1:0] load_data_from_dmem,
    input      [`REG_SIZE-1:0] store_data_to_dmem,
    input      [        3:0] store_we_to_dmem
);
    reg [`REG_SIZE-1:0] mem_array[0:NUM_WORDS-1];

    initial begin
        $readmemh("mem_initial_contents.hex", mem_array);
    end

    localparam AddrMsb = $clog2(NUM_WORDS) + 1;
    localparam AddrLsb = 2;

    always @(negedge clk) begin
        inst_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
    end

    always @(negedge clk) begin
        if (store_we_to_dmem[0]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0]   <= store_data_to_dmem[7:0]; // sb
        if (store_we_to_dmem[1]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8]  <= store_data_to_dmem[15:8]; // sh
        if (store_we_to_dmem[2]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
        if (store_we_to_dmem[3]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24]; // sw
        
        load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
    end
endmodule