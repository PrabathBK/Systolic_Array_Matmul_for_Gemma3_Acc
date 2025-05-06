module block #(parameter DATA_WIDTH = 32)(
    input [DATA_WIDTH-1:0] inp_north, inp_west,
    input clk, rst,
    output reg [DATA_WIDTH-1:0] outp_south, outp_east,
    output reg [2*DATA_WIDTH-1:0] result
);

    wire [2*DATA_WIDTH-1:0] multi;
    assign multi = inp_north * inp_west;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            outp_east <= 0;
            outp_south <= 0;
        end else begin
            result <= result + multi;
            outp_east <= inp_west;
            outp_south <= inp_north;
        end
    end

endmodule