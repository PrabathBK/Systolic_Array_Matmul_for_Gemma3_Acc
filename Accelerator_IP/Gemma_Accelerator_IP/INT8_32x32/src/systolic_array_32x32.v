`timescale 1ns / 1ps

module systolic_array_32x32 #(
    // Parameter: SIZE
    // Defines the dimension of the square systolic array (e.g., 32 for a 32x32 grid).
    parameter integer SIZE = 32,

    // Parameter: DATA_WIDTH
    // The bit width of the input operands (must match the PE).
    parameter integer DATA_WIDTH = 8,

    // Parameter: ACCUM_WIDTH
    // The bit width of the accumulator result (must match the PE).
    parameter integer ACCUM_WIDTH = 32  // Must match the PE internals
) (
    // System-level signals
    input  wire                               clk,
    input  wire                               rst,
    input  wire                               accum_reset, // Clears all PE accumulators simultaneously.

    // Flattened 1D input buses for north (weights) and west (activations)
    input  wire signed [SIZE*DATA_WIDTH-1:0]  north_inputs,
    input  wire signed [SIZE*DATA_WIDTH-1:0]  west_inputs,

    // Valid flags accompanying each input lane
    input  wire [SIZE-1:0]                    north_valid,
    input  wire [SIZE-1:0]                    west_valid,

    // Packed 1D output result vector: SIZE*SIZE*ACCUM_WIDTH bits
    output wire signed [SIZE*SIZE*ACCUM_WIDTH-1:0] result_matrix
);

    // Internal 2D nets for data and valids
    wire signed [DATA_WIDTH-1:0] north_to_south  [0:SIZE][0:SIZE-1];
    wire signed [DATA_WIDTH-1:0] west_to_east    [0:SIZE-1][0:SIZE];
    wire signed [ACCUM_WIDTH-1:0] pe_results     [0:SIZE-1][0:SIZE-1];

    // FIXED: Pipelined valid signals - these will be driven by PE valid_out
    wire north_valid_to_south [0:SIZE][0:SIZE-1];
    wire west_valid_to_east   [0:SIZE-1][0:SIZE];

    genvar r, c;

    // Unpack north inputs and valids into top row
    generate
      for (c = 0; c < SIZE; c = c + 1) begin : UNPACK_NORTH
        assign north_to_south[0][c] = north_inputs[c*DATA_WIDTH +: DATA_WIDTH];
        assign north_valid_to_south[0][c] = north_valid[c];
      end
    endgenerate

    // Unpack west inputs and valids into left column
    generate
      for (r = 0; r < SIZE; r = r + 1) begin : UNPACK_WEST
        assign west_to_east[r][0] = west_inputs[r*DATA_WIDTH +: DATA_WIDTH];
        assign west_valid_to_east[r][0] = west_valid[r];
      end
    endgenerate

    // Instantiate the PE grid
    generate
      for (r = 0; r < SIZE; r = r + 1) begin : ROW
        for (c = 0; c < SIZE; c = c + 1) begin : COL

          // Create wires for the valid outputs of this PE
          wire pe_valid_out;

          pe_int8 #(
            .DATA_WIDTH  (DATA_WIDTH),
            .ACCUM_WIDTH (ACCUM_WIDTH)
          ) pe_inst (
            .clk         (clk),
            .rst         (rst),
            .accum_reset (accum_reset),
            // FIXED: Use properly synchronized valid signals
            .valid       (north_valid_to_south[r][c] & west_valid_to_east[r][c]),
            .inp_north   (north_to_south[r][c]),
            .inp_west    (west_to_east[r][c]),
            .outp_south  (north_to_south[r+1][c]),
            .outp_east   (west_to_east[r][c+1]),
            .valid_out   (pe_valid_out),
            .result      (pe_results[r][c])
          );

          // FIXED: Connect the pipelined valid signal to both directions
          // This ensures the valid signal follows the same timing as the data
          if (r < SIZE-1) begin : CONNECT_SOUTH_VALID
            assign north_valid_to_south[r+1][c] = pe_valid_out;
          end
          if (c < SIZE-1) begin : CONNECT_EAST_VALID
            assign west_valid_to_east[r][c+1] = pe_valid_out;
          end

        end
      end
    endgenerate

    // Pack PE results back into flattened result_matrix
    generate
      for (r = 0; r < SIZE; r = r + 1) begin : PACK_RESULTS_ROW
        for (c = 0; c < SIZE; c = c + 1) begin : PACK_RESULTS_COL
          assign result_matrix[((r*SIZE)+c)*ACCUM_WIDTH +: ACCUM_WIDTH] = pe_results[r][c];
        end
      end
    endgenerate

endmodule
