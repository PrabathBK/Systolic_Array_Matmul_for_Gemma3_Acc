`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: dequant_engine
// Author: Gemini AI
// Date:   2025-07-15
// Status: VERIFIED
//
// Description:
// This module implements a high-throughput, pipelined dequantization engine. It is
// designed to convert 4-bit quantized weights into 8-bit signed integers, which is a
// critical first step in many neural network inference accelerators.
//
// Architecture:
// The engine consists of 16 parallel, 3-stage pipelines. This allows it to process
// 16 weights every clock cycle, meeting the throughput demands of the systolic array.
// The output port is an unsigned vector to ensure robust, portable synthesis, with
// all signed arithmetic handled internally.
//
// Pipeline Stages:
// 1. Unpack & Subtract: A 4-bit weight is unpacked and its 8-bit zero-point is subtracted.
// 2. Multiply: The result is multiplied by a 16-bit scale factor in Q8.8 fixed-point format.
// 3. Shift & Saturate: The product is arithmetically shifted right by 8 to get the
//    integer part, which is then saturated to the valid INT8 range [-128, 127].
//--------------------------------------------------------------------------------------------------
module dequant_engine #(
    // Parameter: WEIGHTS_PER_CYCLE
    // Defines how many weights are processed in parallel. Set to 16 for this design.
    parameter WEIGHTS_PER_CYCLE = 16
) (
    // System signals
    input clk,
    input rst,

    // Input Data & Configuration
    // A packed vector containing N 4-bit weights.
    input        [WEIGHTS_PER_CYCLE*4-1:0] quantized_weights_in,
    // The zero-point is subtracted from the quantized value.
    input signed [                    7:0] zero_point,
    // The scale factor is used to scale the result into the INT8 range.
    input signed [                   15:0] scale_factor_q8_8,

    // Output Data
    // A packed vector of the resulting N 8-bit signed integers.
    // **NOTE**: The port is `reg` but not `signed`. This is intentional for robust
    // synthesis. The bit patterns assigned to it are correct two's complement values.
    output reg [WEIGHTS_PER_CYCLE*8-1:0] dequantized_weights_out
);

  // --- Internal Pipeline Stage Registers ---
  // Stage 1: Result of (input - zero_point)
  reg signed [8:0] temp_val_stage1[WEIGHTS_PER_CYCLE-1:0];
  // Stage 2: Result of multiplication by scale factor
  reg signed [24:0] scaled_val_stage2[WEIGHTS_PER_CYCLE-1:0];
  // Stage 3: Result after arithmetic shift (integer part)
  reg signed [16:0] integer_val_stage3[WEIGHTS_PER_CYCLE-1:0];

  genvar i;

  // --- Pipeline Generation ---
  // A `generate` block creates 16 instances of the 3-stage pipeline logic.
  generate
    for (i = 0; i < WEIGHTS_PER_CYCLE; i = i + 1) begin : dequant_pipeline_gen
      // Pipeline Stage 1: Unpack and Subtract
      always @(posedge clk) begin
        if (rst) temp_val_stage1[i] <= 0;
        else temp_val_stage1[i] <= {1'b0, quantized_weights_in[i*4+:4]} - zero_point;
      end

      // Pipeline Stage 2: Fixed-Point Multiplication
      always @(posedge clk) begin
        if (rst) scaled_val_stage2[i] <= 0;
        else scaled_val_stage2[i] <= temp_val_stage1[i] * scale_factor_q8_8;
      end

      // Pipeline Stage 3: Arithmetic Shift to get Integer Part
      always @(posedge clk) begin
        if (rst) integer_val_stage3[i] <= 0;
        else integer_val_stage3[i] <= scaled_val_stage2[i] >>> 8;  // '>>>' is arithmetic shift
      end
    end
  endgenerate

  // --- Final Saturation Stage (Combinational) ---
  // This logic takes the final integer values from the pipeline and clamps them
  // to the valid 8-bit signed range.
  integer k;
  always @(*) begin
    for (k = 0; k < WEIGHTS_PER_CYCLE; k = k + 1) begin
      // Check for overflow (greater than 127)
      if (integer_val_stage3[k] > 127) begin
        dequantized_weights_out[k*8+:8] = 127;
        // Check for underflow (less than -128)
      end else if (integer_val_stage3[k] < -128) begin
        // Assign the two's complement bit pattern for -128.
        dequantized_weights_out[k*8+:8] = -128;
        // If within range, truncate to 8 bits.
      end else begin
        dequantized_weights_out[k*8+:8] = integer_val_stage3[k][7:0];
      end
    end
  end
endmodule
