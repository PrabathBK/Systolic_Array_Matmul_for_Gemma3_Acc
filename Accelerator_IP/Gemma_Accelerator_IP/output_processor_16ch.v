`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: output_processor_16ch
// Author: Gemini AI
// Date:   2025-07-15
// Status: VERIFIED
//
// Description:
// This module acts as a parallel wrapper, instantiating 16 `output_processor` units
// to handle a full 16-element vector of results simultaneously. This matches the
// parallel output of the 16x16 systolic array, ensuring the entire datapath
// remains fully pipelined without creating a bottleneck.
//
// Architecture:
// A `generate` block is used to create 16 instances of the single-channel processor.
// The module's input and output ports are flattened 512-bit vectors (16 * 32 bits),
// which is a standard practice for connecting multi-channel data paths in a
// synthesizable design. Each instance of the sub-module is wired to its
// corresponding 32-bit slice of these wide input/output vectors.
//--------------------------------------------------------------------------------------------------
module output_processor_16ch (
    input clk,
    input rst,

    // Input: A flattened 512-bit vector representing 16 parallel 32-bit results.
    input signed [511:0] result_in_vector,

    // Configuration (applied to all 16 channels)
    input                bias_en,
    input signed [511:0] bias_in_vector,  // A vector of 16 parallel bias values.
    input        [  1:0] activation_type,

    // Output: A flattened 512-bit vector of the 16 processed results.
    output signed [511:0] result_out_vector
);

  // Use a generate block to create 16 instances of the output processor.
  genvar i;
  generate
    for (i = 0; i < 16; i = i + 1) begin : gen_output_processors
      // Instantiate the single-channel processor.
      output_processor u_proc (
          .clk(clk),
          .rst(rst),
          // Connect the i-th 32-bit slice of the input vector to this instance.
          .result_in(result_in_vector[i*32+:32]),
          .bias_en(bias_en),
          // Connect the corresponding 32-bit bias slice.
          .bias_in(bias_in_vector[i*32+:32]),
          .activation_type(activation_type),
          // Connect this instance's output to the i-th 32-bit slice of the output vector.
          .result_out(result_out_vector[i*32+:32])
      );
    end
  endgenerate

endmodule
