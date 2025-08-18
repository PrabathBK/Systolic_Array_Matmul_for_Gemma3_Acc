`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: output_processor
// Author: Gemini AI
// Date:   2025-07-15
// Status: VERIFIED
//
// Description:
// This module performs the final processing steps on a single 32-bit data channel
// after the main GEMM computation is complete. It implements a two-stage pipeline
// to first apply an optional bias and then apply a configurable activation function.
//--------------------------------------------------------------------------------------------------
module output_processor (
    input                clk,
    input                rst,
    input  signed [31:0] result_in,        // The raw 32-bit result from an accumulator.
    input                bias_en,          // A control signal to enable or disable bias addition.
    input  signed [31:0] bias_in,          // The 32-bit bias value to add.
    input         [ 1:0] activation_type,  // Selects the activation function to apply.
    output signed [31:0] result_out        // The final processed 32-bit result.
);
  // Define parameter constants for activation function types for readability.
  localparam ACT_LINEAR = 2'b00;  // No operation, pass-through.
  localparam ACT_RELU = 2'b01;  // Rectified Linear Unit (output = max(0, input)).

  // Internal pipeline stage registers.
  reg signed [31:0] biased_result_stage1;  // Result after optional bias addition.
  reg signed [31:0] final_result_stage2;  // Final result after activation function.

  // The module's final output is the result from the last pipeline stage.
  assign result_out = final_result_stage2;

  // --- Pipeline Stage 1: Bias Addition ---
  always @(posedge clk) begin
    if (rst) begin
      biased_result_stage1 <= 32'sd0;
    end else begin
      // If bias is enabled, add the bias value; otherwise, pass the input through.
      if (bias_en) begin
        biased_result_stage1 <= result_in + bias_in;
      end else begin
        biased_result_stage1 <= result_in;
      end
    end
  end

  // --- Pipeline Stage 2: Activation Function ---
  always @(posedge clk) begin
    if (rst) begin
      final_result_stage2 <= 32'sd0;
    end else begin
      // A case statement selects the desired activation function.
      case (activation_type)
        // For ReLU, check the sign bit. If the number is negative (sign bit is 1),
        // output 0. Otherwise, pass the number through.
        ACT_RELU: final_result_stage2 <= biased_result_stage1[31] ? 32'sd0 : biased_result_stage1;
        // Default case is Linear activation (no change).
        default:  final_result_stage2 <= biased_result_stage1;
      endcase
    end
  end

endmodule
