`timescale 1ns/1ps

module tb_systolic_array;

    parameter SIZE = 5;
    parameter DATA_WIDTH = 32;

    reg clk, rst;
    reg [DATA_WIDTH-1:0] inp_west [0:SIZE-1];
    reg [DATA_WIDTH-1:0] inp_north [0:SIZE-1];
    wire [2*DATA_WIDTH-1:0] result [0:SIZE-1][0:SIZE-1];
    wire done;

    systolic_array #(SIZE, DATA_WIDTH) dut (
        .clk(clk),
        .rst(rst),
        .inp_west(inp_west),
        .inp_north(inp_north),
        .done(done),
        .result(result)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Matrix A (row-wise) and B (column-wise)
    reg [DATA_WIDTH-1:0] matrixA [0:SIZE-1][0:SIZE-1];
    reg [DATA_WIDTH-1:0] matrixB [0:SIZE-1][0:SIZE-1];

    initial begin
        $dumpfile("systolic.vcd");
        $dumpvars(0, tb_systolic_array);

        // Matrix A
        matrixA[0][0] = 1;  matrixA[0][1] = 2;  matrixA[0][2] = 3;  matrixA[0][3] = 4;
        matrixA[1][0] = 5;  matrixA[1][1] = 6;  matrixA[1][2] = 7;  matrixA[1][3] = 8;
        matrixA[2][0] = 9;  matrixA[2][1] = 10; matrixA[2][2] = 11; matrixA[2][3] = 12;
        matrixA[3][0] = 13; matrixA[3][1] = 14; matrixA[3][2] = 15; matrixA[3][3] = 16;
        

        // Matrix B
        matrixB[0][0] = 17; matrixB[0][1] = 18; matrixB[0][2] = 19; matrixB[0][3] = 20;
        matrixB[1][0] = 21; matrixB[1][1] = 22; matrixB[1][2] = 23; matrixB[1][3] = 24;
        matrixB[2][0] = 25; matrixB[2][1] = 26; matrixB[2][2] = 27; matrixB[2][3] = 28;
        matrixB[3][0] = 29; matrixB[3][1] = 30; matrixB[3][2] = 31; matrixB[3][3] = 32;

        rst = 1;
        #10 rst = 0;

        // Dynamic streaming of inputs
        for (int t = 0; t < 3 * SIZE; t++) begin
            for (int i = 0; i < SIZE; i++) begin
                inp_west[i] = ((t - i) >= 0 && (t - i) < SIZE) ? matrixA[i][t - i] : 0;
            end
            for (int j = 0; j < SIZE; j++) begin
                inp_north[j] = ((t - j) >= 0 && (t - j) < SIZE) ? matrixB[t - j][j] : 0;
            end
            #10;
        end

        wait(done);
        repeat (5) @(posedge clk);
        #10;

        $display("\n=== Final Matrix Multiplication Result ===");
        for (int i = 0; i < SIZE; i++) begin
            for (int j = 0; j < SIZE; j++) begin
                $display("Result[%0d][%0d] = %0d", i, j, result[i][j]);
            end
        end

        $finish;
    end

endmodule