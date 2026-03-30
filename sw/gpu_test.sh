#!/bin/bash
# =============================================================================
# gpu_test.sh  —  Custom GPU ANN Accelerator on NetFPGA
#
# Register map (matches ids.xml):
#   GPU_CMD_REG         0x2000300  bit[0]=reset, bit[1]=prog_en,
#                                   bit[2]=dmem_sel, bit[3]=prog_we
#   HOST_THREAD_ID_REG  0x2000304
#   PROG_ADDR_REG       0x2000308  byte address
#   PROG_WDATA_LO_REG   0x200030c  lower 32 bits of write data
#   PROG_WDATA_HI_REG   0x2000310  upper 32 bits of write data (DMEM only)
#   GPU_RESULT_LOW_REG  0x2000314  result bits [31:0]
#   GPU_RESULT_HIGH_REG 0x2000318  result bits [63:32]
#   GPU_PC_REG          0x200031c  bit[31]=gpu_done, bit[7:0]=PC
#
# CMD values:
#   0x0  GPU running
#   0x2  IMEM prog idle    (prog_en=1, dmem_sel=0, prog_we=0)
#   0xA  IMEM write pulse  (prog_en=1, dmem_sel=0, prog_we=1)
#   0x6  DMEM prog idle    (prog_en=1, dmem_sel=1, prog_we=0)
#   0xE  DMEM write pulse  (prog_en=1, dmem_sel=1, prog_we=1)
#
# DMEM is 64-bit wide; PCI is 32-bit.
# Each DMEM write requires: set ADDR, set WDATA_LO, set WDATA_HI, pulse CMD.
# IMEM is 32-bit; only WDATA_LO is used.
# =============================================================================

GPU_SCRIPT="./gpureg.pl"

REG_CMD=0x2000300
REG_THREAD=0x2000304
REG_ADDR=0x2000308
REG_WDATA_LO=0x200030c
REG_WDATA_HI=0x2000310
REG_RESULT_LO=0x2000314
REG_RESULT_HI=0x2000318
REG_PC=0x200031c

# Strip Windows carriage returns from hex files
sed 's/\r//' gpu_program.hex  > gpu_program_clean.hex
sed 's/\r//' data_memory.hex  > data_memory_clean.hex

echo "======================================"
echo "  Custom GPU ANN Accelerator — NetFPGA"
echo "======================================"

# ── [1] Assert Reset ─────────────────────────────────────────────────────
echo ""
echo "--- [1] Asserting GPU Reset ---"
perl $GPU_SCRIPT write $REG_CMD 0x1
echo "GPU Reset = 1"

# ── [2] Load IMEM ────────────────────────────────────────────────────────
echo ""
echo "--- [2] Loading IMEM (gpu_program.hex) ---"
# Enter IMEM prog mode: prog_en=1, dmem_sel=0, prog_we=0 → CMD=0x2
perl $GPU_SCRIPT write $REG_CMD 0x2

ADDR=0
IMEM_COUNT=0
while read -r line; do
    # Skip blank lines and comment-only lines
    WORD=$(echo "$line" | sed 's/\/\/.*//' | tr -d ' \t\r')
    if [ -n "$WORD" ]; then
        perl $GPU_SCRIPT write $REG_ADDR    $ADDR
        perl $GPU_SCRIPT write $REG_WDATA_LO 0x$WORD
        perl $GPU_SCRIPT write $REG_CMD     0xA   # prog_en=1, prog_we=1
        perl $GPU_SCRIPT write $REG_CMD     0x2   # prog_en=1, prog_we=0
        ADDR=$((ADDR + 4))
        IMEM_COUNT=$((IMEM_COUNT + 1))
    fi
done < gpu_program_clean.hex
echo "IMEM loaded: $IMEM_COUNT words."

# ── [3] Verify IMEM (first 4 words) ─────────────────────────────────────
echo ""
echo "--- [3] Verifying IMEM (first 4 words) ---"
# IMEM uses async read so a single CMD write suffices for settling
for i in 0 4 8 12; do
    perl $GPU_SCRIPT write $REG_ADDR $i
    perl $GPU_SCRIPT write $REG_CMD  0x2   # keep prog_en=1
    perl $GPU_SCRIPT write $REG_CMD  0x2   # 2nd pulse for BRAM latency
    DATA=$(perl $GPU_SCRIPT read $REG_RESULT_LO)
    # NOTE: IMEM readback comes via gpu_result_low since prog_rdata
    # is not exposed in this design — verify visually against gpu_program.hex
    echo "  IMEM[$(($i/4))] addr=0x$(printf '%03X' $i)"
done

# ── [4] Load DMEM ────────────────────────────────────────────────────────
echo ""
echo "--- [4] Loading DMEM (data_memory.hex) ---"
# Enter DMEM prog mode: prog_en=1, dmem_sel=1, prog_we=0 → CMD=0x6
perl $GPU_SCRIPT write $REG_CMD 0x6

# DMEM is 64-bit (8 bytes per word). Each line in data_memory.hex is a
# 16-hex-digit (64-bit) value. Split into hi [63:32] and lo [31:0].
ADDR=0
DMEM_COUNT=0
while read -r line; do
    WORD=$(echo "$line" | sed 's/\/\/.*//' | tr -d ' \t\r')
    if [ -n "$WORD" ]; then
        # Split 16-char hex string into upper and lower 32 bits
        HI="0x${WORD:0:8}"
        LO="0x${WORD:8:8}"
        perl $GPU_SCRIPT write $REG_ADDR     $ADDR
        perl $GPU_SCRIPT write $REG_WDATA_LO $LO
        perl $GPU_SCRIPT write $REG_WDATA_HI $HI
        perl $GPU_SCRIPT write $REG_CMD      0xE   # prog_en=1, dmem_sel=1, prog_we=1
        perl $GPU_SCRIPT write $REG_CMD      0x6   # prog_en=1, dmem_sel=1, prog_we=0
        echo "  DMEM[$DMEM_COUNT] addr=0x$(printf '%03X' $ADDR) = $HI $LO"
        ADDR=$((ADDR + 8))   # 64-bit step = 8 bytes
        DMEM_COUNT=$((DMEM_COUNT + 1))
    fi
done < data_memory_clean.hex
echo "DMEM loaded: $DMEM_COUNT entries."

# ── [5] Verify DMEM (readback) ───────────────────────────────────────────
echo ""
echo "--- [5] Verifying DMEM ---"
# Note: Data_Memory.v uses synchronous read with 1-cycle latency.
# Double CMD pulse needed (same as ARM CPU DMEM readback).
# gpu_result bus reflects DMEM read_data during prog_mode via gpu_top_design.
for i in 0 1 2; do
    BYTE_ADDR=$((i * 8))
    perl $GPU_SCRIPT write $REG_ADDR $BYTE_ADDR
    perl $GPU_SCRIPT write $REG_CMD  0x6   # 1st pulse: addr latches
    perl $GPU_SCRIPT write $REG_CMD  0x6   # 2nd pulse: data valid
    HI=$(perl $GPU_SCRIPT read $REG_RESULT_HI)
    LO=$(perl $GPU_SCRIPT read $REG_RESULT_LO)
    printf "  DMEM[%d] (addr=0x%03X) = %s %s\n" $i $BYTE_ADDR "$HI" "$LO"
done
echo "Expected:"
echo "  DMEM[0] = 0x40004000 0x40004000  (Vector A: 2.0 x4)"
echo "  DMEM[1] = 0x3FC03FC0 0x3FC03FC0  (Vector B: 1.5 x4)"
echo "  DMEM[2] = 0x3F003F00 0x3F003F00  (Vector C: 0.5 x4)"

# ── [6] Set Thread ID ────────────────────────────────────────────────────
echo ""
echo "--- [6] Setting Thread ID ---"
THREAD_ID=0
perl $GPU_SCRIPT write $REG_THREAD $THREAD_ID
echo "Thread ID = $THREAD_ID"

# ── [7] Release prog mode and reset ──────────────────────────────────────
echo ""
echo "--- [7] Releasing Prog Mode and Reset ---"
perl $GPU_SCRIPT write $REG_CMD 0x0   # prog_en=0 → GPU owns buses
perl $GPU_SCRIPT write $REG_CMD 0x0   # confirm reset=0 too
echo "GPU is now running."

# ── [8] Poll gpu_done ────────────────────────────────────────────────────
echo ""
echo "--- [8] Polling for Completion ---"
# gpu_done = bit[31] of GPU_PC_REG, set when PC >= 0x18 (past all 6 instructions)
echo "Waiting for GPU to finish..."

TIMEOUT=30
ELAPSED=0
while true; do
    RAW=$(perl $GPU_SCRIPT read $REG_PC)
    RAW_DEC=$(printf "%d" "$RAW" 2>/dev/null || echo "0")
    DONE_BIT=$(( (RAW_DEC >> 31) & 1 ))
    PC_VAL=$(printf "0x%02X" $(( RAW_DEC & 0xFF )))

    if [ "$DONE_BIT" -eq 1 ]; then
        echo "GPU done! (PC = $PC_VAL)"
        break
    fi

    echo "  Running... PC = $PC_VAL  (${ELAPSED}s)"
    sleep 1
    ELAPSED=$((ELAPSED + 1))

    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "ERROR: Timeout after ${TIMEOUT}s. Last RAW_PC = $RAW"
        perl $GPU_SCRIPT write $REG_CMD 0x0
        rm -f gpu_program_clean.hex data_memory_clean.hex
        exit 1
    fi
done

# ── [9] Read Result ───────────────────────────────────────────────────────
echo ""
echo "--- [9] Reading GPU Result ---"
HI=$(perl $GPU_SCRIPT read $REG_RESULT_HI)
LO=$(perl $GPU_SCRIPT read $REG_RESULT_LO)
printf "GPU Result: 0x%s%s\n" "${HI#0x}" "${LO#0x}"
echo ""
echo "Expected BFloat16 FMA result:"
echo "  D = (A x B) + C  where A=2.0, B=1.5, C=0.5 (4 lanes)"
echo "  Each lane: (2.0 * 1.5) + 0.5 = 3.0 + 0.5 = 3.5"
echo "  BFloat16 3.5 = 0x4060"
echo "  Expected 64-bit result: 0x4060406040604060"

# Clean up
rm -f gpu_program_clean.hex data_memory_clean.hex

echo ""
echo "======================================"
echo "  Done."
echo "======================================"