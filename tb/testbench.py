import os
import subprocess

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

DIVIDER_STAGES = 8

# HELPER FUNCTIONS

def assertEquals(expected, actual, msg=""):
    """Helper to replace the missing cocotb_utils.assertEquals"""
    # Convert cocotb BinaryValue to integer if needed
    if hasattr(actual, "integer"):
        try:
            actual_val = actual.integer
        except ValueError:
            # Handle cases where the register might be 'x' or 'z'
            actual_val = str(actual)
    else:
        actual_val = actual

    assert expected == actual_val, (
        f"Expected {expected} (0x{expected:x}), got {actual_val}. {msg}"
    )


def assemble_and_load(dut, asm_code):
    """Compiles RISC-V assembly and loads it directly into the Verilog memory array."""
    # Write the assembly string to a temporary file
    with open("temp.s", "w") as f:
        f.write(asm_code)

    # Assemble to an object file (targeting RV32IM architecture)
    subprocess.run(
        [
            "riscv64-linux-gnu-as",
            "-march=rv32im",
            "-mabi=ilp32",
            "temp.s",
            "-o",
            "temp.o",
        ],
        check=True,
    )

    # Extract the raw machine code binary
    subprocess.run(
        ["riscv64-linux-gnu-objcopy", "-O", "binary", "temp.o", "temp.bin"], check=True
    )

    # Read the raw binary bytes
    with open("temp.bin", "rb") as f:
        machine_code = f.read()

    # Inject the 32-bit machine code words into the Verilog memory array
    word_index = 0
    for i in range(0, len(machine_code), 4):
        chunk = machine_code[i : i + 4].ljust(4, b"\x00")
        word_val = int.from_bytes(chunk, byteorder="little")
        dut.memory.mem_array[word_index].value = word_val
        word_index += 1


async def preTestSetup(dut, asm_code):
    """Setup the DUT. MUST be called at the start of EACH test."""
    # Start a 4ns clock (from original script)
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await RisingEdge(dut.clk)

    # Raise `rst` signal
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)

    # Clear the first 100 words of memory to ensure clean state
    for i in range(100):
        dut.memory.mem_array[i].value = 0

    # Compile and load the instruction
    assemble_and_load(dut, asm_code)

    # Lower `rst` signal
    dut.rst.value = 0
    await ClockCycles(dut.clk, 1)


# TEST CASES

@cocotb.test()
async def testLui(dut):
    "Run one lui inst."
    await preTestSetup(dut, "lui x1,0x12345")

    await ClockCycles(dut.clk, 6)
    assertEquals(
        0x12345000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testLuiLui(dut):
    "Run two lui independent inst."
    await preTestSetup(
        dut,
        """lui x1,0x12345
        lui x2,0x6789A""",
    )

    await ClockCycles(dut.clk, 7)
    assertEquals(
        0x12345000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        0x6789A000,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testAddi3(dut):
    "Run three addi inst."
    await preTestSetup(
        dut,
        """addi x1,x1,1
        addi x1,x1,1
        addi x1,x1,1""",
    )
    assertEquals(0, dut.datapath.rf.regs[1].value)

    await ClockCycles(dut.clk, 8)
    assertEquals(
        3,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testMX1(dut):
    "Check MX bypass to rs1"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        add x2,x1,x0""",
    )

    await ClockCycles(dut.clk, 7)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testMX2(dut):
    "Check MX bypass to rs2"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        add x2,x0,x1""",
    )

    await ClockCycles(dut.clk, 7)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testWX1(dut):
    "Check WX bypass to rs1"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        lui x5,0x12345
        add x2,x1,x0""",
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testWX2(dut):
    "Check WX bypass to rs2"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        lui x5,0x12345
        add x2,x0,x1""",
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testWD1(dut):
    "Check WD bypass to rs1"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        lui x5,0x12345
        lui x6,0x12345
        add x2,x1,x0""",
    )

    await ClockCycles(dut.clk, 9)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testWD2(dut):
    "Check WD bypass to rs2"
    await preTestSetup(
        dut,
        """
        addi x1,x0,42
        lui x5,0x12345
        lui x6,0x12345
        add x2,x0,x1""",
    )

    await ClockCycles(dut.clk, 9)
    assertEquals(
        42,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testX0Bypassing(dut):
    "Check that reads/writes to x0 are not bypassed"
    await preTestSetup(
        dut,
        """
        lui x0,0x12345
        add x1,x0,x0 # should not use MX bypass
        add x2,x0,x0 # should not use WX bypass
        add x3,x0,x0 # should not use WD bypass
        addi x4,x2,1
        """,
    )

    await ClockCycles(dut.clk, 10)
    assertEquals(
        0,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        0,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        0,
        dut.datapath.rf.regs[3].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        1,
        dut.datapath.rf.regs[4].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testBneNotTaken(dut):
    "bne which is not taken"
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        bne x0,x0,target
        lui x1,0x54321
        target: addi x0,x0,0""",
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        0x54321000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testBeqNotTaken(dut):
    "beq which is not taken"
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        beq x1,x0,target
        lui x1,0x54321
        target: addi x0,x0,0""",
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        0x54321000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testBneTaken(dut):
    "bne which is taken"
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        bne x1,x0,target
        lui x1,0x54321 # in Decode when branch is taken, should get cleared
        lui x1,0xABCDE # in Fetch when branch is taken, should get cleared
        target: addi x0,x0,0
        addi x0,x0,0
        """,
    )
    await ClockCycles(dut.clk, 9)
    assertEquals(
        0x12345000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test()
async def testBeqTaken(dut):
    "beq which is taken"
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        beq x1,x1,target
        lui x1,0x54321 # in Decode when branch is taken, should get cleared
        lui x1,0xABCDE # in Fetch when branch is taken, should get cleared
        target: addi x0,x0,0
        addi x0,x0,0
        """,
    )

    await ClockCycles(dut.clk, 9)
    assertEquals(
        0x12345000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


# ==========================================
# FULL ISA TEST CASES
# ==========================================


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testLoadUse1(dut):
    "load to use in rs1"
    await preTestSetup(
        dut,
        """
        lw x1,0(x0) # loads bits of
        add x2,x1,x0
        """,
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        0x0000_2083,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testLoadUse2(dut):
    "load to use in rs1"
    await preTestSetup(
        dut,
        """
        lw x1,0(x0) # loads bits of the lw inst. itself
        add x2,x0,x1
        """,
    )

    await ClockCycles(dut.clk, 8)
    assertEquals(
        0x0000_2083,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testLoadFalseUse(dut):
    "load followed by inst. that doesn't actually use load result"
    await preTestSetup(
        dut,
        """
        lw x0,0(x0) # loads bits of the lw inst. itself
        lui x1,0xFE007
        """,
    )

    await ClockCycles(dut.clk, 7)
    assertEquals(
        0xFE00_7000,
        dut.datapath.rf.regs[1].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testWMData(dut):
    "WM bypass"
    await preTestSetup(
        dut,
        """
        lw x1,0(x0) # loads bits of the lw inst. itself
        sw x1,12(x0)
        """,
    )

    await ClockCycles(dut.clk, 7)
    assertEquals(
        0x0000_2083,
        dut.memory.mem_array[3].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


# @cocotb.test(skip="RVTEST_ALUBR" in os.environ)
# async def testWMAddress(dut):
#     "WM bypass"
#     await preTestSetup(
#         dut,
#         """
#         lw x1,0(x0) # loads bits of the lw inst. itself
#         sb x1,0(x1) # use sb since x1 is not 2B or 4B aligned
#         """,
#     )
#     loadValue = 0x2083

#     await ClockCycles(dut.clk, 5)  # sb in X stage
#     assertEquals(
#         0,
#         dut.memory.mem_array[int(loadValue / 4)].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )
#     await ClockCycles(dut.clk, 1)  # sb reaches M stage, writes to memory
#     assertEquals(
#         0x8300_0000,
#         dut.memory.mem_array[int(loadValue / 4)].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testDiv(dut):
    "Run div inst."
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        div x2,x1,x1""",
    )

    await ClockCycles(dut.clk, 6 + DIVIDER_STAGES)
    assertEquals(
        1,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


# @cocotb.test(skip="RVTEST_ALUBR" in os.environ)
# async def test2DivIndependent(dut):
#     "Run 2 independent div inst."
#     await preTestSetup(
#         dut,
#         """
#         lui x1,0x12345
#         div x2,x1,x1
#         div x3,x1,x1""",
#     )

#     await ClockCycles(dut.clk, 6 + DIVIDER_STAGES + 1)
#     assertEquals(
#         1,
#         dut.datapath.rf.regs[2].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )
#     assertEquals(
#         1,
#         dut.datapath.rf.regs[3].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )


# @cocotb.test(skip="RVTEST_ALUBR" in os.environ)
# async def test8DivIndependent(dut):
#     "Run 8 independent div inst."
#     await preTestSetup(
#         dut,
#         """
#         lui x1,0x12345
#         div x2,x1,x1
#         div x3,x1,x1
#         div x4,x1,x1
#         div x5,x1,x1
#         div x6,x1,x1
#         div x7,x1,x1
#         div x8,x1,x1
#         div x9,x1,x1""",
#     )

#     await ClockCycles(dut.clk, 5 + DIVIDER_STAGES)
#     for i in range(8):
#         await ClockCycles(dut.clk, 1)
#         assertEquals(
#             1,
#             dut.datapath.rf.regs[2 + i].value,
#             f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#         )


# @cocotb.test(skip="RVTEST_ALUBR" in os.environ)
# async def test2DivDependent(dut):
#     "Run 2 dependent div inst."
#     await preTestSetup(
#         dut,
#         """
#         lui x1,0x12345
#         div x2,x1,x1
#         div x3,x2,x2""",
#     )

#     await ClockCycles(dut.clk, 5 + DIVIDER_STAGES + 1)
#     assertEquals(
#         1,
#         dut.datapath.rf.regs[2].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )
#     assertEquals(
#         0,
#         dut.datapath.rf.regs[3].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )
#     await ClockCycles(dut.clk, DIVIDER_STAGES + 1)
#     assertEquals(
#         1,
#         dut.datapath.rf.regs[3].value,
#         f"failed at cycle {dut.datapath.cycles_current.value.integer}",
#     )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testDivNonDiv(dut):
    "Run div inst. followed by independent, non-div inst."
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        div x2,x1,x1
        addi x3,x0,7""",
    )

    await ClockCycles(dut.clk, 6 + DIVIDER_STAGES)
    # div has written back, addi is in W but hasn't written back yet
    assertEquals(
        1,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        0,
        dut.datapath.rf.regs[3].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    await ClockCycles(dut.clk, 1)
    # now addi has written back
    assertEquals(
        7,
        dut.datapath.rf.regs[3].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testDivUse(dut):
    "Run div + dependent inst."
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        div x2,x1,x1
        add x3,x2,x2 # uses MX bypass
        """,
    )

    await ClockCycles(dut.clk, 5 + DIVIDER_STAGES + 2)
    assertEquals(
        1,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        2,
        dut.datapath.rf.regs[3].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testDivToStoreData(dut):
    "Run div + dependent inst."
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        div x2,x1,x1
        sw x2,16(x0) # uses WM bypass to avoid stall
        """,
    )

    await ClockCycles(dut.clk, 5 + DIVIDER_STAGES + 1)  # sw is in M stage, div is in W
    assertEquals(
        1,
        dut.memory.mem_array[4].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        1,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )


@cocotb.test(skip="RVTEST_ALUBR" in os.environ)
async def testDivToStoreAddress(dut):
    "Run div + dependent inst."
    await preTestSetup(
        dut,
        """
        lui x1,0x12345
        div x2,x1,x1
        sw x2,23(x2) # uses MX bypass
        """,
    )

    await ClockCycles(dut.clk, 5 + DIVIDER_STAGES + 1)  # sw is in M stage, div is in W
    assertEquals(
        1,
        dut.datapath.rf.regs[2].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )
    assertEquals(
        1,
        dut.memory.mem_array[6].value,
        f"failed at cycle {dut.datapath.cycles_current.value.integer}",
    )



