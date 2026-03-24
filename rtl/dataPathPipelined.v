
`include "header.vh"

module DatapathPipelined (
    input                     clk,
    input                     rst,
    output     [ `REG_SIZE-1:0] pc_to_imem,
    input      [`INST_SIZE-1:0] inst_from_imem,
    // dmem is read/write
    output reg [ `REG_SIZE-1:0] addr_to_dmem,
    input      [ `REG_SIZE-1:0] load_data_from_dmem,
    output reg [ `REG_SIZE-1:0] store_data_to_dmem,
    output reg [         3:0] store_we_to_dmem,
    output reg                halt,
    // The PC of the inst currently in Writeback. 0 if not a valid inst.
    output reg [ `REG_SIZE-1:0] trace_writeback_pc,
    // The bits of the inst currently in Writeback. 0 if not a valid inst.
    output reg [`INST_SIZE-1:0] trace_writeback_inst
);
    // =========================================================================
    // Opcodes & Constants
    // =========================================================================
    localparam [`OPCODE_SIZE-1:0] OpLoad    = 7'b00_000_11;
    localparam [`OPCODE_SIZE-1:0] OpStore   = 7'b01_000_11;
    localparam [`OPCODE_SIZE-1:0] OpBranch  = 7'b11_000_11;
    localparam [`OPCODE_SIZE-1:0] OpJalr    = 7'b11_001_11;
    localparam [`OPCODE_SIZE-1:0] OpJal     = 7'b11_011_11;
    localparam [`OPCODE_SIZE-1:0] OpRegImm  = 7'b00_100_11;
    localparam [`OPCODE_SIZE-1:0] OpRegReg  = 7'b01_100_11;
    localparam [`OPCODE_SIZE-1:0] OpEnviron = 7'b11_100_11;
    localparam [`OPCODE_SIZE-1:0] OpAuipc   = 7'b00_101_11;
    localparam [`OPCODE_SIZE-1:0] OpLui     = 7'b01_101_11;

    // Cycle Counter
    reg [`REG_SIZE-1:0] cycles_current;
    always @(posedge clk) begin
        if (rst) cycles_current <= 0;
        else cycles_current <= cycles_current + 1;
    end

    // =========================================================================
    // PIPELINE REGISTER DEFINITIONS
    // =========================================================================
    
    // --- IF/ID Pipeline Registers ---
    reg [31:0] d_pc, d_inst;
    // --- ID/EX Pipeline Registers ---
    reg [31:0] x_pc, x_inst;
    reg [31:0] x_rs1_data, x_rs2_data;
    // Raw values from RegFile (after WD bypass)
    reg [31:0] x_imm;
    reg [4:0]  x_rd;
    reg        x_reg_write, x_mem_read, x_mem_write;
    reg        x_halt;
    // --- EX/MEM Pipeline Registers ---
    reg [31:0] m_pc, m_inst;
    reg [31:0] m_alu_res;
    reg [31:0] m_rs2_data;
    // For Store (Value to store)
    reg [4:0]  m_rd;
    reg        m_reg_write, m_mem_read, m_mem_write;
    reg        m_halt;
    // --- MEM/WB Pipeline Registers ---
    reg [31:0] w_pc, w_inst;
    reg [31:0] w_alu_res;
    reg [31:0] w_mem_data;
    reg [4:0]  w_rd;
    reg        w_reg_write;
    reg        w_halt;

    // =========================================================================
    // WIRES & HAZARD SIGNALS
    // =========================================================================
    
    wire stall_pipeline;
    wire flush_decode;
    wire flush_execute;

    // Hazard Logic Wires
    wire x_branch_taken;
    wire x_jump_taken;
    reg  [31:0] pc_next;     
    reg  [31:0] pc_target;

    // Divider Logic Wires
    wire x_is_div;
    reg  [3:0] div_counter;
    wire div_stall;

    // =========================================================================
    // 1. FETCH STAGE (F)
    // =========================================================================
    
    reg [31:0] f_pc;
    // Next PC Logic
    always @(*) begin
        if (x_branch_taken || x_jump_taken) begin
            // Branch misprediction recovery: Go to calculated target
            pc_next = pc_target;
        end else begin
            // Normal sequential execution
            pc_next = f_pc + 4;
        end
    end

    // PC Update & IF/ID Register Update
    always @(posedge clk) begin
        if (rst) begin
            f_pc <= 0;
            d_pc <= 0;
            d_inst <= 32'h00000013; // Reset to NOP
        end else if (!stall_pipeline) begin
            f_pc <= pc_next;
            // If flushing decode (due to taken branch), insert NOP into D stage
            if (flush_decode) begin
                d_inst <= 32'h00000013; // NOP
                d_pc   <= 0;
            end else begin
                d_pc   <= f_pc;
                if (^inst_from_imem === 1'bx)
                    d_inst <= 32'h00000013;
                else
                    d_inst <= inst_from_imem;
            end
        end
    end

    assign pc_to_imem = f_pc;

    // =========================================================================
    // 2. DECODE STAGE (D)
    // =========================================================================

    wire [6:0] d_opcode = d_inst[6:0];
    wire [4:0] d_rd     = d_inst[11:7];
    wire [2:0] d_funct3 = d_inst[14:12];
    wire [4:0] d_rs1    = d_inst[19:15];
    wire [4:0] d_rs2    = d_inst[24:20];
    wire [6:0] d_funct7 = d_inst[31:25];

    // Immediate Generation
    wire [31:0] d_imm_i = {{20{d_inst[31]}}, d_inst[31:20]};
    wire [31:0] d_imm_s = {{20{d_inst[31]}}, d_inst[31:25], d_inst[11:7]};
    wire [31:0] d_imm_b = {{19{d_inst[31]}}, d_inst[31], d_inst[7], d_inst[30:25], d_inst[11:8], 1'b0};
    wire [31:0] d_imm_u = {d_inst[31:12], 12'b0};
    wire [31:0] d_imm_j = {{11{d_inst[31]}}, d_inst[31], d_inst[19:12], d_inst[20], d_inst[30:21], 1'b0};
    
    // Immediate Selection Mux
    reg [31:0] d_imm_val;
    always @(*) begin
        case (d_opcode)
            OpStore:     d_imm_val = d_imm_s;
            OpBranch:    d_imm_val = d_imm_b;
            OpJal:       d_imm_val = d_imm_j;
            OpLui, OpAuipc: d_imm_val = d_imm_u;
            default:     d_imm_val = d_imm_i;
        endcase
    end

    // Register File
    wire [31:0] rf_rs1_data, rf_rs2_data;
    wire [31:0] w_write_data; // Computed in WB stage

    RegFile rf (
        .clk(clk), .rst(rst),
        .rd(w_rd), .rd_data(w_write_data), .we(w_reg_write),
        .rs1(d_rs1), .rs1_data(rf_rs1_data),
        .rs2(d_rs2), .rs2_data(rf_rs2_data)
    );
    
    // WD BYPASS: Forwarding from WB stage to Decode stage
    reg [31:0] d_rs1_data_bypassed;
    reg [31:0] d_rs2_data_bypassed;

    always @(*) begin
        // Forward to RS1
        if (w_reg_write && (w_rd != 0) && (w_rd == d_rs1)) 
            d_rs1_data_bypassed = w_write_data;
        else 
            d_rs1_data_bypassed = rf_rs1_data;
        // Forward to RS2
        if (w_reg_write && (w_rd != 0) && (w_rd == d_rs2)) 
            d_rs2_data_bypassed = w_write_data;
        else 
            d_rs2_data_bypassed = rf_rs2_data;
    end

    // Control Signals (Decode)
    wire d_is_load      = (d_opcode == OpLoad);
    wire d_is_store     = (d_opcode == OpStore);
    wire d_is_ecall     = (d_opcode == OpEnviron) && (d_inst[31:7] == 0);
    
    // --- HAZARD DETECTION UNIT ---
    wire d_uses_rs1 = (d_opcode == OpRegReg) || (d_opcode == OpRegImm) || 
                      (d_opcode == OpLoad)   || (d_opcode == OpStore) || 
                      (d_opcode == OpBranch) || (d_opcode == OpJalr);
                      
    wire d_uses_rs2 = (d_opcode == OpRegReg) || (d_opcode == OpStore) || 
                      (d_opcode == OpBranch);

    // Load-Use Hazard: 
    wire load_use_hazard = x_mem_read && (x_rd != 0) && (
                           (d_uses_rs1 && (x_rd == d_rs1)) || 
                           (d_uses_rs2 && (x_rd == d_rs2) && !d_is_store) 
    );

    // Control to pass to Execute
    wire d_reg_write = (d_opcode != OpStore) && (d_opcode != OpBranch) && (d_opcode != OpEnviron);
    wire d_mem_read  = d_is_load;
    wire d_mem_write = d_is_store;
    wire d_halt      = d_is_ecall;

    // ID/EX Pipeline Register Update
    always @(posedge clk) begin
        if (rst) begin
            x_pc <= 0;
            x_inst <= 32'h00000013; // NOP
            x_reg_write <= 0;
            x_mem_read <= 0; x_mem_write <= 0; x_halt <= 0;
            x_rs1_data <= 0; x_rs2_data <= 0; x_rd <= 0;
            x_imm <= 0;
        end else if (!div_stall) begin 
            if (load_use_hazard || flush_execute) begin
                // Insert Bubble (NOP)
                x_inst <= 32'h00000013;
                x_reg_write <= 0;
                x_mem_read  <= 0;
                x_mem_write <= 0;
                x_halt      <= 0;
                x_pc        <= 0;
            end else begin
                // Normal Propagation
                x_pc <= d_pc;
                x_inst <= d_inst;
                x_rs1_data <= d_rs1_data_bypassed; // Use bypassed data
                x_rs2_data <= d_rs2_data_bypassed;
                x_imm <= d_imm_val;
                x_rd  <= d_rd;
                x_reg_write <= d_reg_write;
                x_mem_read  <= d_mem_read;
                x_mem_write <= d_mem_write;
                x_halt      <= d_halt;
            end
        end
    end

    // =========================================================================
    // 3. EXECUTE STAGE (X)
    // =========================================================================

    wire [4:0] x_rs1 = x_inst[19:15];
    wire [4:0] x_rs2 = x_inst[24:20];
    wire [6:0] x_op  = x_inst[6:0];
    wire [2:0] x_f3  = x_inst[14:12];
    wire [6:0] x_f7  = x_inst[31:25];

    // Forwarding Unit (MX and WX)
    reg [31:0] forward_a_val;
    reg [31:0] forward_b_val;

    always @(*) begin
        // Forward A (RS1)
        if (m_reg_write && (m_rd != 0) && (m_rd == x_rs1) && !m_mem_read)
            forward_a_val = m_alu_res;
        else if (w_reg_write && (w_rd != 0) && (w_rd == x_rs1))
            forward_a_val = w_write_data;
        else
            forward_a_val = x_rs1_data;
        // Forward B (RS2)
        if (m_reg_write && (m_rd != 0) && (m_rd == x_rs2) && !m_mem_read)
            forward_b_val = m_alu_res;
        else if (w_reg_write && (w_rd != 0) && (w_rd == x_rs2))
            forward_b_val = w_write_data;
        else
            forward_b_val = x_rs2_data;
    end

    // ALU Operands
    wire [31:0] alu_op_a = (x_op == OpAuipc) ? x_pc : forward_a_val;
    // [NOTE] Correctly selecting immediate for I-Type, including Shifts
    wire [31:0] alu_op_b_mux = (x_op == OpRegReg || x_op == OpBranch) ? forward_b_val : x_imm;
    wire [31:0] alu_op_b = alu_op_b_mux;

    // --- CLA INSTANTIATION ---
    wire is_sub = (x_op == OpRegReg && x_f3 == 3'b000 && x_f7 == 7'b0100000) ||
                  (x_op == OpBranch);
    wire [31:0] cla_b_in = is_sub ? ~alu_op_b : alu_op_b;
    wire [31:0] cla_sum;
    cla cla_inst (.a(alu_op_a), .b(cla_b_in), .cin(is_sub), .sum(cla_sum));

    // --- DIVIDER LOGIC ---
    assign x_is_div = (x_op == OpRegReg) && (x_f7 == 7'd1) && (x_f3[2] == 1);
    
    wire [31:0] div_quo, div_rem;
    
    wire is_signed_div = (x_f3 == 3'b100) || (x_f3 == 3'b110);
    wire div_sign_dvd  = is_signed_div & forward_a_val[31];
    wire div_sign_div  = is_signed_div & forward_b_val[31];
    wire [31:0] abs_dvd = div_sign_dvd ? (~forward_a_val + 1) : forward_a_val;
    wire [31:0] abs_div = div_sign_div ? (~forward_b_val + 1) : forward_b_val;

    DividerUnsignedPipelined divider (
        .clk(clk), .rst(rst), .stall(1'b0),
        .i_dividend(abs_dvd), .i_divisor(abs_div),
        .o_quotient(div_quo), .o_remainder(div_rem)
    );

    wire quo_neg = is_signed_div & (div_sign_dvd ^ div_sign_div);
    wire rem_neg = is_signed_div & div_sign_dvd;
    wire [31:0] final_quo = quo_neg ? (~div_quo + 1) : div_quo;
    wire [31:0] final_rem = rem_neg ? (~div_rem + 1) : div_rem;

    always @(posedge clk) begin
        if (rst) begin
            div_counter <= 0;
        end else if (x_is_div) begin
            if (div_counter < 8) 
                div_counter <= div_counter + 1;
            else    
                div_counter <= 0;
        end else begin
            div_counter <= 0;
        end
    end
    assign div_stall = x_is_div && (div_counter < 8);

    // --- ALU RESULT SELECTION ---
    reg [31:0] alu_result;
    reg [63:0] mul_res;
    always @(*) begin
        // DEFAULT VALUES
        alu_result = 32'd0;
        mul_res = 64'd0;

        if (x_op == OpLui) alu_result = x_imm;
        else if (x_op == OpJal || x_op == OpJalr) alu_result = x_pc + 4;
        else if (x_is_div) begin
             // DIV/REM selection
             case (x_f3)
                3'b100: alu_result = (forward_b_val == 0) ? -1 : 
                                     (forward_a_val == 32'h80000000 && forward_b_val == -1) ? 32'h80000000 : final_quo; 
                3'b101: alu_result = (forward_b_val == 0) ? -1 : div_quo; 
                3'b110: alu_result = (forward_b_val == 0) ? forward_a_val : 
                                     (forward_a_val == 32'h80000000 && forward_b_val == -1) ? 0 : final_rem; 
                3'b111: alu_result = (forward_b_val == 0) ? forward_a_val : div_rem; 
                default: alu_result = 0;
             endcase
        end else if (x_op == OpRegReg && x_f7 == 7'd1) begin
             // Multiply
             case (x_f3)
                 3'b000: alu_result = forward_a_val * forward_b_val; 
                 3'b001: begin mul_res = $signed(forward_a_val) * $signed(forward_b_val); alu_result = mul_res[63:32]; end 
                 3'b010: begin mul_res = $signed(forward_a_val) * $signed({1'b0, forward_b_val}); alu_result = mul_res[63:32]; end 
                 3'b011: begin mul_res = {1'b0, forward_a_val} * {1'b0, forward_b_val}; alu_result = mul_res[63:32]; end 
                 default: alu_result = 0;
             endcase
        end else if (x_op == OpLoad || x_op == OpStore || x_op == OpAuipc) begin
             alu_result = cla_sum;
        end else begin
            // Standard ALU
            case (x_f3)
                3'b000: alu_result = cla_sum; // add/sub
                // [FIX] Shift Left: Logical only
                3'b001: alu_result = forward_a_val << alu_op_b[4:0]; // sll/slli
                3'b010: alu_result = ($signed(forward_a_val) < $signed(alu_op_b)) ? 1 : 0; // slt
                3'b011: alu_result = (forward_a_val < alu_op_b) ? 1 : 0; // sltu
                3'b100: alu_result = forward_a_val ^ alu_op_b; // xor
                // [FIX] Shift Right: Arithmetic (SRA/SRAI) if bit 30 is set, else Logical (SRL/SRLI)
                // Use explicit x_inst[30] to check 'funct7' bit for I-types too.
                3'b101: begin
                    if (x_inst[30]) // SRA or SRAI
                        alu_result = $signed(forward_a_val) >>> alu_op_b[4:0];
                    else            // SRL or SRLI
                        alu_result = forward_a_val >> alu_op_b[4:0];
                end
                3'b110: alu_result = forward_a_val | alu_op_b; // or
                3'b111: alu_result = forward_a_val & alu_op_b; // and
                default: alu_result = 0;
            endcase
        end
    end

    // --- BRANCH & JUMP LOGIC ---
    reg br_cond;
    always @(*) begin
        case (x_f3)
            3'b000: br_cond = (forward_a_val == forward_b_val); // beq
            3'b001: br_cond = (forward_a_val != forward_b_val); // bne
            3'b100: br_cond = ($signed(forward_a_val) < $signed(forward_b_val)); // blt
            3'b101: br_cond = ($signed(forward_a_val) >= $signed(forward_b_val)); // bge
            3'b110: br_cond = (forward_a_val < forward_b_val); // bltu
            3'b111: br_cond = (forward_a_val >= forward_b_val); // bgeu
            default: br_cond = 0;
        endcase
    end

    assign x_branch_taken = (x_op == OpBranch) && br_cond;
    assign x_jump_taken   = (x_op == OpJal) || (x_op == OpJalr);
    always @(*) begin
        if (x_op == OpJalr) pc_target = (forward_a_val + x_imm) & ~32'd1;
        else pc_target = x_pc + x_imm; // Branch or JAL
    end

    // Control Signals for Stalls/Flush
    assign stall_pipeline = load_use_hazard || div_stall;
    assign flush_decode   = x_branch_taken || x_jump_taken;
    assign flush_execute  = x_branch_taken || x_jump_taken || load_use_hazard; 

    // EX/MEM Pipeline Register Update
    always @(posedge clk) begin
        if (rst) begin
            m_pc <= 0;
            m_inst <= 32'h00000013;
            m_alu_res <= 0; m_rs2_data <= 0; m_rd <= 0;
            m_reg_write <= 0; m_mem_read <= 0;
            m_mem_write <= 0; m_halt <= 0;
        end else if (!div_stall) begin 
             m_pc <= x_pc;
             m_inst <= x_inst;
             m_alu_res <= alu_result;
             m_rs2_data <= forward_b_val; 
             m_rd <= x_rd;
             m_reg_write <= x_reg_write;
             m_mem_read <= x_mem_read;
             m_mem_write <= x_mem_write;
             m_halt <= x_halt;
        end
    end
    
    // =========================================================================
    // 4. MEMORY STAGE (M)
    // =========================================================================

    // WM BYPASS
    reg [31:0] store_val_final;
    always @(*) begin
        if (w_reg_write && (w_rd != 0) && (w_rd == m_inst[24:20])) 
            store_val_final = w_write_data;
        else
            store_val_final = m_rs2_data;
    end

    // Memory Access Wiring
    always @(*) begin
        addr_to_dmem = m_alu_res;
        store_data_to_dmem = 0;
        store_we_to_dmem = 0;

        if (m_mem_write) begin
            case (m_inst[14:12]) 
                3'b000: begin // sb
                    case (m_alu_res[1:0])
                        2'b00: begin store_we_to_dmem = 4'b0001; store_data_to_dmem[7:0] = store_val_final[7:0]; end
                        2'b01: begin store_we_to_dmem = 4'b0010; store_data_to_dmem[15:8] = store_val_final[7:0]; end
                        2'b10: begin store_we_to_dmem = 4'b0100; store_data_to_dmem[23:16] = store_val_final[7:0]; end
                        2'b11: begin store_we_to_dmem = 4'b1000; store_data_to_dmem[31:24] = store_val_final[7:0]; end
                    endcase
                end
                3'b001: begin // sh
                    case (m_alu_res[1])
                        1'b0: begin store_we_to_dmem = 4'b0011; store_data_to_dmem[15:0] = store_val_final[15:0]; end
                        1'b1: begin store_we_to_dmem = 4'b1100; store_data_to_dmem[31:16] = store_val_final[15:0]; end
                    endcase
                end
                3'b010: begin // sw
                    store_we_to_dmem = 4'b1111;
                    store_data_to_dmem = store_val_final;
                end
            endcase
        end
    end

    // Load Data Alignment
    reg [31:0] loaded_val_aligned;
    always @(*) begin
        loaded_val_aligned = load_data_from_dmem; // Default (lw)
        case (m_inst[14:12])
            3'b010: loaded_val_aligned = load_data_from_dmem; 
            3'b000: case(m_alu_res[1:0]) // lb
                2'b00: loaded_val_aligned = {{24{load_data_from_dmem[7]}}, load_data_from_dmem[7:0]};
                2'b01: loaded_val_aligned = {{24{load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
                2'b10: loaded_val_aligned = {{24{load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
                2'b11: loaded_val_aligned = {{24{load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
            endcase
            3'b001: case(m_alu_res[1]) // lh
                1'b0: loaded_val_aligned = {{16{load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
                1'b1: loaded_val_aligned = {{16{load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
            endcase
            3'b100: case(m_alu_res[1:0]) // lbu
                2'b00: loaded_val_aligned = {24'b0, load_data_from_dmem[7:0]};
                2'b01: loaded_val_aligned = {24'b0, load_data_from_dmem[15:8]};
                2'b10: loaded_val_aligned = {24'b0, load_data_from_dmem[23:16]};
                2'b11: loaded_val_aligned = {24'b0, load_data_from_dmem[31:24]};
            endcase
            3'b101: case(m_alu_res[1]) // lhu
                1'b0: loaded_val_aligned = {16'b0, load_data_from_dmem[15:0]};
                1'b1: loaded_val_aligned = {16'b0, load_data_from_dmem[31:16]};
            endcase
        endcase
    end

    // MEM/WB Pipeline Register Update
    always @(posedge clk) begin
        if (rst) begin
            w_pc <= 0;
            w_inst <= 32'h00000013;
            w_alu_res <= 0; w_mem_data <= 0; w_rd <= 0;
            w_reg_write <= 0; w_halt <= 0;
        end else if (!div_stall) begin
            w_pc <= m_pc;
            w_inst <= m_inst;
            w_alu_res <= m_alu_res;
            w_mem_data <= loaded_val_aligned; 
            w_rd <= m_rd;
            w_reg_write <= m_reg_write;
            w_halt <= m_halt;
        end
    end

    // =========================================================================
    // 5. WRITEBACK STAGE (W)
    // =========================================================================

    assign w_write_data = (w_inst[6:0] == OpLoad) ? w_mem_data : w_alu_res;

    always @(*) begin
        trace_writeback_pc   = w_pc;
        trace_writeback_inst = w_inst;
        halt                 = w_halt;
    end

endmodule


