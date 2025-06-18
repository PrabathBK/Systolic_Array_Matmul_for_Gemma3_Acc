// `include "block.v"

module systolic_array #(parameter SIZE = 4, DATA_WIDTH = 32)(
    input clk, rst,
    input [DATA_WIDTH-1:0] inp_west [0:SIZE-1],
    input [DATA_WIDTH-1:0] inp_north [0:SIZE-1],
    output reg done,
    output wire [2*DATA_WIDTH-1:0] result [0:SIZE-1][0:SIZE-1]
);

    wire [DATA_WIDTH-1:0] east [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] south [0:SIZE-1][0:SIZE-1];

    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : row
            for (j = 0; j < SIZE; j = j + 1) begin : col
                wire [DATA_WIDTH-1:0] in_n;
                wire [DATA_WIDTH-1:0] in_w;

                assign in_n = (i == 0) ? inp_north[j] : south[i-1][j];
                assign in_w = (j == 0) ? inp_west[i] : east[i][j-1];

                block #(DATA_WIDTH) pe (
                    .inp_north(in_n),
                    .inp_west(in_w),
                    .clk(clk),
                    .rst(rst),
                    .outp_south(south[i][j]),
                    .outp_east(east[i][j]),
                    .result(result[i][j])
                );
            end
        end
    endgenerate

    reg [7:0] count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 0;
            done <= 0;
        end else begin
            if (count >= 2 * SIZE) begin
                done <= 1;
            end else begin
                count <= count + 1;
                done <= 0;
            end
        end
    end

endmodule