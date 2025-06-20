// pe.v
`timescale 1ns/1ps

module pe #(
    parameter WEIGHT_WIDTH = 4,      // Unsigned INT4
    parameter ACTIVATION_WIDTH = 16, // FP16
    parameter ACC_WIDTH = 16         // FP32 accumulator
)(
    input wire clk,
    input wire rst,

    input wire [WEIGHT_WIDTH-1:0] weight_in,
    input wire [ACTIVATION_WIDTH-1:0] activation_in,

    output reg [WEIGHT_WIDTH-1:0] weight_out,
    output reg [ACTIVATION_WIDTH-1:0] activation_out,

    output reg [ACC_WIDTH-1:0] result_accum
);

    // === Cast weight: INT4 → FP16 ===
    wire [ACTIVATION_WIDTH-1:0] weight_fp16;

    int2fp16 u_cast (
        .in(weight_in),
        .out(weight_fp16)
    );

    // === Multiply: FP16 × FP16 ===
    wire [ACC_WIDTH-1:0] mult_result;
    wire mult_result_valid;

    fp16_mult u_mult (
        .clk(clk),
        .a(weight_fp16),
        .b(activation_in),
        .result(mult_result),
        .result_valid(mult_result_valid)
    );

    // === PE behavior ===
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            weight_out <= 0;
            activation_out <= 0;
            result_accum <= 0;
        end else begin
            weight_out <= weight_in;
            activation_out <= activation_in;
        end
    end

    always @(*) begin
        if (mult_result_valid)
                result_accum <= mult_result;
        
    end

endmodule
