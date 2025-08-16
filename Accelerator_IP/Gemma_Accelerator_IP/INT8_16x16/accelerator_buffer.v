module accelerator_buffer #(
    parameter DATA_WIDTH = 128,
    parameter DEPTH = 20,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                     clk,
    input  wire                     wr_en,
    input  wire [ADDR_WIDTH-1:0]    wr_addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    input  wire [ADDR_WIDTH-1:0]    rd_addr,
    output reg  [DATA_WIDTH-1:0]    rd_data
);

    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    
    // Initialize memory to zero
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = {DATA_WIDTH{1'b0}};
        end
    end
    
    // Write port
    always @(posedge clk) begin
        if (wr_en && wr_addr < DEPTH) begin
            memory[wr_addr] <= wr_data;
        end
    end
    
    // Read port
    always @(posedge clk) begin
        if (rd_addr < DEPTH) begin
            rd_data <= memory[rd_addr];
        end else begin
            rd_data <= {DATA_WIDTH{1'b0}};
        end
    end

endmodule