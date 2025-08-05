`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: pe_int8
// Author: Gemini AI
// Date:   2025-07-15
// Status: CORRECTED
//
// Description:
// CORRECTED: This version fixes a critical bug by properly registering the
// pass-through data paths. The `outp_south` and `outp_east` signals are now
// driven by registers (`north_reg`, `west_reg`) instead of being combinationally
// assigned from the inputs. This ensures the correct one-cycle delay between
// PEs, enabling the systolic data flow.
//--------------------------------------------------------------------------------------------------
module pe_int8 #(
    parameter DATA_WIDTH  = 8,
    parameter ACCUM_WIDTH = 32
) (
    // System-level signals
    input clk,
    input rst,
    input accum_reset,

    // Data inputs
    input signed [DATA_WIDTH-1:0] inp_north,
    input signed [DATA_WIDTH-1:0] inp_west,

    // Data outputs (now correctly registered)
    output signed [DATA_WIDTH-1:0] outp_south,
    output signed [DATA_WIDTH-1:0] outp_east,

    // Result output
    output signed [ACCUM_WIDTH-1:0] result
);
  // Internal register for the accumulator.
  reg signed [ACCUM_WIDTH-1:0] accumulator;

  // **FIX**: Registers for pipelining the inputs to the outputs.
  reg signed [ DATA_WIDTH-1:0] north_reg;
  reg signed [ DATA_WIDTH-1:0] west_reg;

  // The outputs are now driven by the pipeline registers.
  assign outp_south = north_reg;
  assign outp_east  = west_reg;
  assign result     = accumulator;

  // Separate logic block for the systolic data flow (pipelining).
  always @(posedge clk) begin
    if (rst) begin
      north_reg <= 8'sd0;
      west_reg  <= 8'sd0;
    end else begin
      // Data is registered every cycle to be passed to the next PE.
      north_reg <= inp_north;
      west_reg  <= inp_west;
    end
  end

  // Separate logic block for the computation.
  always @(posedge clk) begin
    if (rst) begin
      accumulator <= 32'sd0;
      // `accum_reset` clears the result between computation tiles.
    end else if (accum_reset) begin
      accumulator <= 32'sd0;
      // Otherwise, perform the Multiply-Accumulate operation.
    end else begin
      accumulator <= accumulator + (inp_north * inp_west);
    end
  end

endmodule
