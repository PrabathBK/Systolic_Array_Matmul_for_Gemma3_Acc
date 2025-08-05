`timescale 1ns / 1ps

//--------------------------------------------------------------------------------------------------
// Module: accelerator_buffer
// Author: Gemini AI
// Date:   2025-07-15
// Status: VERIFIED
//
// Description:
// A generic, synthesizable, dual-port memory block. This is a behavioral model
// that will be synthesized to Block RAM (BRAM) on an FPGA. It allows for one
// read and one write operation to occur in the same clock cycle, which is essential
// for pipelined architectures.
//
// Architecture:
// - A simple register array `mem` models the storage elements.
// - On the positive edge of the clock, if the write enable (`wr_en`) signal is
//   high, the data on `wr_data` is written to the location specified by `wr_addr`.
// - Reading is combinational: the data at the location specified by `rd_addr` is
//   always present on the `rd_data` output port.
//--------------------------------------------------------------------------------------------------
module accelerator_buffer #(
    parameter DATA_WIDTH = 128,
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input clk,
    input wr_en,
    input [ADDR_WIDTH-1:0] wr_addr,
    input [DATA_WIDTH-1:0] wr_data,
    input [ADDR_WIDTH-1:0] rd_addr,
    output [DATA_WIDTH-1:0] rd_data
);
  // The core memory storage, implemented as a register array.
  reg [DATA_WIDTH-1:0] mem[DEPTH-1:0];

  // Synchronous write logic.
  always @(posedge clk) begin
    if (wr_en) begin
      mem[wr_addr] <= wr_data;
    end
  end

  // Asynchronous (combinational) read logic.
  assign rd_data = mem[rd_addr];

endmodule
