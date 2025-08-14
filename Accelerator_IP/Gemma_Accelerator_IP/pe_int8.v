module pe_int8 #(
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)(
    input clk,
    input rst,
    input accum_reset,
    input valid,
    input  [DATA_WIDTH-1:0] inp_north,
    input  [DATA_WIDTH-1:0] inp_west,
    output reg  [DATA_WIDTH-1:0] outp_south,
    output reg  [DATA_WIDTH-1:0] outp_east,
    output reg valid_out,
    output reg [ACCUM_WIDTH-1:0] result
);
    
    // FIXED: Pipeline the valid signal to match data timing
    reg valid_reg;
    
    // FIXED: Accumulation logic - use the current cycle's valid signal
    always @(posedge clk) begin
        if (rst || accum_reset) begin
            result <= 0;
        end else if (valid) begin  // Use current valid signal
            // Accumulate whenever valid is high (including zero values)
            result <= result + (inp_north * inp_west);
        end
        // If valid is 0, result holds its previous value
    end
    
    // Data flow pipeline with pipelined valid signal
    always @(posedge clk) begin
        if (rst) begin
            outp_south <= 0;
            outp_east <= 0;
            valid_out <= 0;
        end else begin
            outp_south <= inp_north;
            outp_east <= inp_west;
            valid_out <= valid;  // Pipeline the valid signal to match data timing
        end
    end
endmodule
