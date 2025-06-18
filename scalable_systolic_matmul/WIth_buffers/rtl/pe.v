module pe #(
    parameter DATA_WIDTH = 8
)(
    input                           clk,
    input                           rst,
    input       [DATA_WIDTH-1:0]    inp_north,
    input       [DATA_WIDTH-1:0]    inp_west,
    output reg  [DATA_WIDTH-1:0]    outp_south,
    output reg  [DATA_WIDTH-1:0]    outp_east,
    output reg  [2*DATA_WIDTH-1:0]  result
);
always @(posedge clk or posedge rst) begin
    if (rst) begin
        outp_south <= 0;
        outp_east <= 0;
        result <= 0;
    end else begin
        outp_south <= inp_north;
        outp_east <= inp_west;

        // FIX: Only accumulate when valid data present
        if (inp_north !== 8'bx && inp_west !== 8'bx)
            result <= result + (inp_north * inp_west);
        else
            result <= result; // Preserve last valid value
    end
end

endmodule

