#!/bin/bash

# Define the path to your Perl script
GPU_SCRIPT="./gpureg.pl"

echo "======================================"
echo " Starting Custom GPU AI Accelerator "
echo "======================================"

# Step 1: Hold GPU in Reset
echo "[1/4] Putting GPU in Reset..."
$GPU_SCRIPT reset 1

# Step 2: Set Thread ID (Change this variable to test different threads)
THREAD_ID=0
echo "[2/4] Loading Thread ID: $THREAD_ID..."
$GPU_SCRIPT thread $THREAD_ID

# Step 3: Release Reset and let the FPGA fly
echo "[3/4] Releasing Reset (Executing Program)..."
$GPU_SCRIPT reset 0

# Pause for 0.1 seconds.
# This gives the 125 MHz FPGA plenty of time to finish the program
# and safely enter the Software Trap infinite loop.
sleep 0.1

# Step 4: Capture the Result
echo "[4/4] Fetching Final Result..."
RESULT=$($GPU_SCRIPT result)
echo "--------------------------------------"
echo " SUCCESS: $RESULT"
echo "======================================