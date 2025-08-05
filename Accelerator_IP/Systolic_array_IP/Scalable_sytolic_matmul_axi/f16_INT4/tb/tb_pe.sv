`timescale 1ns/1ps

module tb_pe;

    // Parameters
    parameter WEIGHT_WIDTH = 4;
    parameter ACTIVATION_WIDTH = 16;
    parameter ACC_WIDTH = 16;

    // DUT ports
    reg clk;
    reg rst;
    reg [WEIGHT_WIDTH-1:0] weight_in;
    reg [ACTIVATION_WIDTH-1:0] activation_in;

    wire [WEIGHT_WIDTH-1:0] weight_out;
    wire [ACTIVATION_WIDTH-1:0] activation_out;
    wire [ACC_WIDTH-1:0] result_accum;

    // DUT instance
    pe #(
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .weight_in(weight_in),
        .activation_in(activation_in),
        .weight_out(weight_out),
        .activation_out(activation_out),
        .result_accum(result_accum)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz

    // Stimulus
    initial begin
        $display("=== TB: PE FP16 × INT4 ===");

        // Reset
        rst = 1;
        weight_in = 0;
        activation_in = 16'h0000;
        #20;
        rst = 0;

        // === Test pattern ===
        // Weight: INT4 values 3, 5, 7
        // Activation: FP16 values 2.0, 1.5, -3.0

        // Example: weight = 3, activation = 2.0
        weight_in = 4'd3;
        activation_in = 16'h4000; // 2.0 in FP16
        #10;

        // Next input: weight = 5, activation = 1.5
        weight_in = 4'd5;
        activation_in = 16'h3E00; // 1.5 in FP16
        #10;

        // Next input: weight = 7, activation = -3.0
        weight_in = 4'd7;
        activation_in = 16'hC400; // -3.0 in FP16
        #10;

        // Hold
        weight_in = 0;
        activation_in = 0;

        #50;

        $display("Final accumulated result (FP32 bits): %h", result_accum);

        $finish;
    end

endmodule
