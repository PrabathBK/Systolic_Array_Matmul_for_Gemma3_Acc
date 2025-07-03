module pe #(
    parameter DATA_WIDTH = 8
)(
    input clk,
    input rst,
    input [DATA_WIDTH-1:0] inp_north,
    input [DATA_WIDTH-1:0] inp_west,
    output reg [DATA_WIDTH-1:0] outp_south,
    output reg [DATA_WIDTH-1:0] outp_east,
    output reg [2*DATA_WIDTH-1:0] result
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        outp_south <= 0;
        outp_east <= 0;
        result <= 0;
    end else begin
        outp_south <= inp_north;
        outp_east <= inp_west;
        
        // Accumulate when both inputs are valid (non-zero)
        if (inp_north != 0 && inp_west != 0) begin
            result <= result + (inp_north * inp_west);
        end
        // Keep previous result when inputs are zero (no accumulation)
    end
end

endmodule