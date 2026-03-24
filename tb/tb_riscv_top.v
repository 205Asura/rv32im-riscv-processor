`timescale 1ns / 1ps

module tb_riscv_top;

    // ========================================================================
    // 1. SIGNAL DEFINITIONS
    // ========================================================================
    reg clk;
    reg rst;
    wire halt;
    wire [31:0] trace_writeback_pc;
    wire [31:0] trace_writeback_inst;

    // ========================================================================
    // 2. INSTANTIATE PROCESSOR
    // ========================================================================
    riscv_top dut (
        .clk(clk),
        .rst(rst),
        .halt(halt),
        .trace_writeback_pc(trace_writeback_pc),
        .trace_writeback_inst(trace_writeback_inst)
    );

    // ========================================================================
    // 3. CLOCK GENERATION (10ns Period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // 4. HELPER TASK: DYNAMIC PROGRAM LOADER
    // ========================================================================
    reg [31:0] program_buffer [0:127]; // Increased buffer size
    
    task load_program;
        input integer num_insts;
        integer f, i;
        begin
            f = $fopen("mem_initial_contents_test.hex", "w");
            if (f == 0) begin
                $display("[ERROR] Could not open hex file for writing!");
                $finish;
            end
            
            for (i = 0; i < num_insts; i = i + 1) begin
                $fdisplay(f, "%h", program_buffer[i]);
            end
            
            // Fill padding with NOPs
            repeat(10) $fdisplay(f, "00000013"); 

            $fclose(f);
            
            // Reload memory
            $readmemh("mem_initial_contents_test.hex", dut.memory.mem_array);
            $display("[INFO] Program loaded (%0d instructions).", num_insts);
        end
    endtask

// ========================================================================
    // HELPER TASK: RESULT CHECKER
    // ========================================================================
    // This task handles the comparison and printing for you.
    // usage: check_result("TEST_NAME", reg_num, expected_val, is_signed);
    task check_result;
        input [8*10:1] test_name; // Test name (max 10 chars)
        input integer reg_num;    // Register to check (e.g., 1 for x1)
        input [31:0] expected_val;
        input is_signed;          // 1 for signed print, 0 for hex
        
        reg [31:0] actual_val;
        begin
            actual_val = dut.datapath.rf.regs[reg_num]; // Get value from DUT

            if (actual_val === expected_val) begin
                if (is_signed)
                    $display("[PASS] %s: x%0d = %0d (Expected %0d)", 
                             test_name, reg_num, $signed(actual_val), $signed(expected_val));
                else
                    $display("[PASS] %s: x%0d = %h (Expected %h)", 
                             test_name, reg_num, actual_val, expected_val);
            end else begin
                if (is_signed)
                    $display("[FAIL] %s: x%0d = %0d (Expected %0d)", 
                             test_name, reg_num, $signed(actual_val), $signed(expected_val));
                else
                    $display("[FAIL] %s: x%0d = %h (Expected %h)", 
                             test_name, reg_num, actual_val, expected_val);
            end
        end
    endtask

    // ========================================================================
    // 6. MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        $display("==================================================");
        $display("Starting Comprehensive Test Bench (Pipelined)");
        $display("==================================================");

        // -------------------------------------------------------------------------
        // PROGRAM 1: I-Type Arithmetic & Shifts
        // -------------------------------------------------------------------------
        $display("\n--- Program 1: I-Type Arithmetic & Shifts ---");
        program_buffer[0] = 32'hfff00093; // ADDI x1, x0, -1
        program_buffer[1] = 32'h00409113; // SLLI x2, x1, 4
        program_buffer[2] = 32'h0040d193; // SRLI x3, x1, 4
        program_buffer[3] = 32'h4040d213; // SRAI x4, x1, 4
        program_buffer[4] = 32'h0010c293; // XORI x5, x1, 1
        program_buffer[5] = 32'h0ff06313; // ORI  x6, x0, 255
        program_buffer[6] = 32'h00f37393; // ANDI x7, x6, 15
        program_buffer[7] = 32'h0000a413; // SLTI x8, x1, 0
        program_buffer[8] = 32'h0000b493; // SLTIU x9, x1, 0
        program_buffer[9] = 32'h00000073; // ecall

        load_program(10);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); // Wait for the cycle to actually finish
        #1;
        $display("[INFO] Program 1 Cycles: %0d", dut.datapath.cycles_current);
        
        // check_result(NAME, REG_NUM, EXPECTED_VALUE, IS_SIGNED)
        check_result("ADDI ", 1, 32'hFFFFFFFF, 0); // Display as Hex
        check_result("SLLI ", 2, 32'hFFFFFFF0, 0);
        check_result("SRLI ", 3, 32'h0FFFFFFF, 0);
        check_result("SRAI ", 4, 32'hFFFFFFFF, 0);
        check_result("XORI ", 5, 32'hFFFFFFFE, 0);
        check_result("ORI  ", 6, 32'h000000FF, 0);
        check_result("ANDI ", 7, 32'h0000000F, 0);
        check_result("SLTI ", 8, 1, 1);           // Display as Signed
        check_result("SLTIU", 9, 0, 1);


        // -------------------------------------------------------------------------
        // PROGRAM 2: R-Type Arithmetic & Logic
        // -------------------------------------------------------------------------
        $display("\n--- Program 2: R-Type Arithmetic & Logic ---");
        program_buffer[0] = 32'h00a00093; // Setup x1=10
        program_buffer[1] = 32'h00300113; // Setup x2=3
        program_buffer[2] = 32'hffb00193; // Setup x3=-5
        program_buffer[3] = 32'h00208233; // ADD
        program_buffer[4] = 32'h402082b3; // SUB
        program_buffer[5] = 32'h00209333; // SLL
        program_buffer[6] = 32'h0011a3b3; // SLT
        program_buffer[7] = 32'h0011b433; // SLTU
        program_buffer[8] = 32'h0020c4b3; // XOR
        program_buffer[9] = 32'h0021d533; // SRL
        program_buffer[10] = 32'h4021d5b3; // SRA
        program_buffer[11] = 32'h0020e633; // OR
        program_buffer[12] = 32'h0020f6b3; // AND
        program_buffer[13] = 32'h00000073;

        load_program(14);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); // Wait for the cycle to actually finish
        #1;
        $display("[INFO] Program 2 Cycles: %0d", dut.datapath.cycles_current);

        check_result("ADD  ", 4, 13, 1);
        check_result("SUB  ", 5, 7, 1);
        check_result("SLL  ", 6, 80, 1);
        check_result("SLT  ", 7, 1, 1);
        check_result("SLTU ", 8, 0, 1);
        check_result("XOR  ", 9, 9, 1);
        check_result("SRL  ", 10, 32'h1FFFFFFF, 0);
        check_result("SRA  ", 11, 32'hFFFFFFFF, 0);
        check_result("OR   ", 12, 11, 1);
        check_result("AND  ", 13, 2, 1);


        // -------------------------------------------------------------------------
        // PROGRAM 3: Branches, Jumps & LUI
        // -------------------------------------------------------------------------
        $display("\n--- Program 3: Branches, Jumps & LUI ---");
        program_buffer[0] = 32'h123450b7; // LUI
        program_buffer[1] = 32'h00a00113; // Setup
        program_buffer[2] = 32'h01400193; // Setup
        program_buffer[3] = 32'h00310463; // BEQ
        program_buffer[4] = 32'h00211263; // BNE
        program_buffer[5] = 32'h00314463; // BLT
        program_buffer[6] = 32'hbad00213; // FAIL
        program_buffer[7] = 32'h0021d463; // BGE
        program_buffer[8] = 32'hbad00213; // FAIL
        program_buffer[9] = 32'h00316463; // BLTU
        program_buffer[10] = 32'hbad00213; // FAIL
        program_buffer[11] = 32'h0021f463; // BGEU
        program_buffer[12] = 32'hbad00213; // FAIL
        program_buffer[13] = 32'h008002ef; // JAL
        program_buffer[14] = 32'h00000013; // NOP
        program_buffer[15] = 32'h00400313; // Skip
        program_buffer[16] = 32'h00100213; // Success Flag
        program_buffer[17] = 32'h00000073;

        load_program(18);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); // Wait for the cycle to actually finish
        #1;
        $display("[INFO] Program 3 Cycles: %0d", dut.datapath.cycles_current);

        check_result("LUI  ", 1, 32'h12345000, 0);
        check_result("Branch", 4, 1, 1); // Expect x4 = 1 (Success flag)


        // -------------------------------------------------------------------------
        // PROGRAM 4: Memory Widths
        // -------------------------------------------------------------------------
        $display("\n--- Program 4: Memory Load/Store Widths ---");
        program_buffer[0] = 32'h06400093; // Base
        program_buffer[1] = 32'hdeadc137; // DEADC000
        program_buffer[2] = 32'heef10113; // DEADBEEF
        program_buffer[3] = 32'h0020a023; // SW
        program_buffer[4] = 32'h00208223; // SB
        program_buffer[5] = 32'h00209423; // SH
        program_buffer[6] = 32'h0000a183; // LW
        program_buffer[7] = 32'h00008203; // LB
        program_buffer[8] = 32'h0000c283; // LBU
        program_buffer[9] = 32'h00009303; // LH
        program_buffer[10] = 32'h0000d383; // LHU
        program_buffer[11] = 32'h00000073;

        load_program(12);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); // Wait for the cycle to actually finish
        #1;
        
        $display("[INFO] Program 4 Cycles: %0d", dut.datapath.cycles_current);

        check_result("SW/LW", 3, 32'hDEADBEEF, 0);
        check_result("LB   ", 4, 32'hFFFFFFEF, 0);
        check_result("LBU  ", 5, 32'h000000EF, 0);
        check_result("LH   ", 6, 32'hFFFFBEEF, 0);
        check_result("LHU  ", 7, 32'h0000BEEF, 0);


        // -------------------------------------------------------------------------
        // PROGRAM 5: M-Extension
        // -------------------------------------------------------------------------
        $display("\n--- Program 5: M-Extension Full Suite ---");
        program_buffer[0] = 32'h01400093; // 20
        program_buffer[1] = 32'hffb00113; // -5
        program_buffer[2] = 32'h01e00193; // 30
        program_buffer[3] = 32'h02208233; // MUL
        program_buffer[4] = 32'h022092b3; // MULH
        program_buffer[5] = 32'h0220c333; // DIV
        program_buffer[6] = 32'h0220e3b3; // REM
        program_buffer[7] = 32'h0230d433; // DIVU
        program_buffer[8] = 32'h0230f4b3; // REMU
        program_buffer[9] = 32'h00000073;

        load_program(10);
        rst = 1; #20; @(negedge clk) rst = 0;
        
        wait(halt); @(posedge clk); // Wait for the cycle to actually finish
        #1;
        $display("[INFO] Program 5 Cycles: %0d", dut.datapath.cycles_current);

        check_result("MUL  ", 4, -100, 1);
        check_result("MULH ", 5, -1, 1);
        check_result("DIV  ", 6, -4, 1);
        check_result("REM  ", 7, 0, 1);
        check_result("DIVU ", 8, 0, 1);
        check_result("REMU ", 9, 20, 1);

        $display("==================================================");
        $finish;
    end

endmodule