`include "header.vh"


module RegFile (
    input      [        4:0] rd,
    input      [`REG_SIZE-1:0] rd_data,
    input      [        4:0] rs1,
    output reg [`REG_SIZE-1:0] rs1_data,
    input      [        4:0] rs2,
    output reg [`REG_SIZE-1:0] rs2_data,
    input                    clk,
    input                    we,
    input                    rst
);
    localparam NumRegs = 32;
    reg [`REG_SIZE-1:0] regs[0:NumRegs-1];
    integer i;

    // Synchronous Write
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NumRegs; i = i + 1) begin
                regs[i] <= 0;
            end
        end else if (we && (rd != 5'd0)) begin
            regs[rd] <= rd_data;
        end
    end

    // Asynchronous Read
    always @(*) begin
        if (rs1 == 0) rs1_data = 0;
        else rs1_data = regs[rs1];

        if (rs2 == 0) rs2_data = 0;
        else rs2_data = regs[rs2];
    end
endmodule