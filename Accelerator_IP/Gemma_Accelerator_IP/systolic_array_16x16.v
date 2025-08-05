`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: systolic_array_16x16
// Author: Gemini AI
// Date:   2025-07-15
// Status: VERIFIED
//
// Description:
// This module implements a 16x16 systolic array for high-throughput matrix multiplication.
// It instantiates a 2D grid of 256 'pe_int8' processing elements and manages the
// systolic data flow required for GEMM operations.
//
// Architecture:
// The array takes flattened 1D vectors as inputs for activations (from the west) and
// weights (from the north). It internally unpacks these vectors to feed the top and
// left edges of the PE grid. Data is then "pumped" through the array synchronously.
// After the pipeline latency, the computed 32-bit results from all 256 PEs are
// packed into a single, flattened 8192-bit (256 * 32) output vector.
// This use of flattened vectors simplifies integration with higher-level modules.
//--------------------------------------------------------------------------------------------------
module systolic_array_16x16 #(
    // Parameter: SIZE
    // Defines the dimension of the square systolic array (e.g., 16 for a 16x16 grid).
    parameter SIZE = 16,

    // Parameter: DATA_WIDTH
    // The bit width of the input operands (must match the PE).
    parameter DATA_WIDTH = 8,

    // Parameter: ACCUM_WIDTH
    // The bit width of the accumulator result (must match the PE).
    parameter ACCUM_WIDTH = 32
) (
    // System-level signals
    input clk,
    input rst,
    input accum_reset, // Clears all 256 PE accumulators simultaneously.

    // Data inputs are flattened vectors for synthesis compatibility.
    // A 16*8 = 128-bit vector for the north-fed inputs (typically weights).
    input signed [SIZE*DATA_WIDTH-1:0] north_inputs,
    // A 16*8 = 128-bit vector for the west-fed inputs (typically activations).
    input signed [SIZE*DATA_WIDTH-1:0] west_inputs,

    // The output is a single, large, flattened vector containing all 256 results.
    // It has a total width of 16*16*32 = 8192 bits.
    output signed [SIZE*SIZE*ACCUM_WIDTH-1:0] result_matrix
);
  // Internal wiring is done using 2D arrays of wires for clarity and ease of connection.
  // These represent the data links between the PEs.
  wire signed [ DATA_WIDTH-1:0] north_to_south[  SIZE:0][SIZE-1:0];
  wire signed [ DATA_WIDTH-1:0] west_to_east  [SIZE-1:0][  SIZE:0];
  wire signed [ACCUM_WIDTH-1:0] pe_results    [SIZE-1:0][SIZE-1:0];

  genvar r, c;

  // Unpack the NORTH inputs (1D vector) into the top row of the 2D internal grid.
  generate
    for (c = 0; c < SIZE; c = c + 1) begin : unpack_north_inputs_loop
      assign north_to_south[0][c] = north_inputs[c*DATA_WIDTH+:DATA_WIDTH];
    end
  endgenerate

  // Unpack the WEST inputs (1D vector) into the leftmost column of the 2D internal grid.
  generate
    for (r = 0; r < SIZE; r = r + 1) begin : unpack_west_inputs_loop
      assign west_to_east[r][0] = west_inputs[r*DATA_WIDTH+:DATA_WIDTH];
    end
  endgenerate

  // Instantiate the 16x16 grid of Processing Elements.
  generate
    for (r = 0; r < SIZE; r = r + 1) begin : row_gen
      for (c = 0; c < SIZE; c = c + 1) begin : col_gen
        pe_int8 pe_inst (
            .clk(clk),
            .rst(rst),
            .accum_reset(accum_reset),
            .inp_north(north_to_south[r][c]),
            .inp_west(west_to_east[r][c]),
            .outp_south(north_to_south[r+1][c]),
            .outp_east(west_to_east[r][c+1]),
            .result(pe_results[r][c])
        );
      end
    end
  endgenerate

  // Pack the 2D array of results from the PEs back into the flattened 1D output vector.
  generate
    for (r = 0; r < SIZE; r = r + 1) begin : pack_results_loop
      for (c = 0; c < SIZE; c = c + 1) begin
        assign result_matrix[((r*SIZE)+c)*ACCUM_WIDTH+:ACCUM_WIDTH] = pe_results[r][c];
      end
    end
  endgenerate

endmodule
