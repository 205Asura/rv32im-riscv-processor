`timescale 1ns / 1ns
`include "header.vh"

module riscv_top (
    input                 clk,
    input                 rst,
    output                halt,
    output [ `REG_SIZE-1:0] trace_writeback_pc,
    output [`INST_SIZE-1:0] trace_writeback_inst
);
    wire [`INST_SIZE-1:0] inst_from_imem;
    wire [ `REG_SIZE-1:0] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
    wire [         3:0] mem_data_we;
    wire [(8*32)-1:0] test_case;

    memory #(
        .NUM_WORDS(30)
    ) memory (
        .rst                 (rst),
        .clk                 (clk),
        .pc_to_imem          (pc_to_imem),
        .inst_from_imem      (inst_from_imem),
        .addr_to_dmem        (mem_data_addr),
        .load_data_from_dmem (mem_data_loaded_value),
        .store_data_to_dmem  (mem_data_to_write),
        .store_we_to_dmem    (mem_data_we)
    );

    DatapathPipelined datapath (
        .clk                  (clk),
        .rst                  (rst),
        .pc_to_imem           (pc_to_imem),
        .inst_from_imem       (inst_from_imem),
        .addr_to_dmem         (mem_data_addr),
        .store_data_to_dmem   (mem_data_to_write),
        .store_we_to_dmem     (mem_data_we),
        .load_data_from_dmem  (mem_data_loaded_value),
        .halt                 (halt),
        .trace_writeback_pc   (trace_writeback_pc),
        .trace_writeback_inst (trace_writeback_inst)
    );
endmodule