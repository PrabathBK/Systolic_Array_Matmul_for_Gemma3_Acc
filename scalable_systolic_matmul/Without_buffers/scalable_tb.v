`timescale 1ns/1ps

module tb_systolic_array;

    parameter SIZE = 6;
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

    // Matrix A and B: 6x6
    reg [DATA_WIDTH-1:0] matrixA [0:SIZE-1][0:SIZE-1];
    reg [DATA_WIDTH-1:0] matrixB [0:SIZE-1][0:SIZE-1];

    initial begin
        $dumpfile("systolic.vcd");
        $dumpvars(0, tb_systolic_array);

        // Initialize matrixA (A[i][j] = i * SIZE + j + 1)
        for (int i = 0; i < SIZE; i++) begin
            for (int j = 0; j < SIZE; j++) begin
                matrixA[i][j] = i * SIZE + j + 1;
            end
        end

        // Initialize matrixB (B[i][j] = (i+1) * (j+1))
        for (int i = 0; i < SIZE; i++) begin
            for (int j = 0; j < SIZE; j++) begin
                matrixB[i][j] = (i + 1) * (j + 1);
            end
        end

        rst = 1;
        #10 rst = 0;

        // Stream data for 3*SIZE cycles
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

        $display("\n=== Final 6x6 Matrix Multiplication Result ===");
        for (int i = 0; i < SIZE; i++) begin
            for (int j = 0; j < SIZE; j++) begin
                $display("Result[%0d][%0d] = %0d", i, j, result[i][j]);
            end
        end

        $finish;
    end

endmodule