module axi_memory_model #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter DEPTH = 1024
)(
    input  logic clk,
    input  logic rstn,

    // AXI Read Address
    input  logic arvalid,
    output logic arready,
    input  logic [ADDR_WIDTH-1:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,

    // AXI Read Data
    output logic rvalid,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic rlast,
    input  logic rready,

    // AXI Write Address
    input  logic awvalid,
    output logic awready,
    input  logic [ADDR_WIDTH-1:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,

    // AXI Write Data
    input  logic wvalid,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [15:0] wstrb,
    input  logic wlast,
    output logic wready,

    // Write Response
    output logic bvalid,
    input  logic bready
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] rptr, wptr;
    logic [7:0] r_cnt, w_cnt;
    logic reading, writing;

    // Read FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            arready <= 0; rvalid <= 0; rlast <= 0; reading <= 0;
        end else begin
            if (arvalid && !reading) begin
                arready <= 1;
                rptr <= araddr >> 4;
                r_cnt <= arlen;
                reading <= 1;
            end else begin
                arready <= 0;
            end

            if (reading && rready) begin
                rdata <= mem[rptr];
                rptr <= rptr + 1;
                rlast <= (r_cnt == 0);
                rvalid <= 1;
                if (r_cnt == 0) reading <= 0;
                else r_cnt <= r_cnt - 1;
            end else rvalid <= 0;
        end
    end

    // Write FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            awready <= 0; wready <= 0; bvalid <= 0; writing <= 0;
        end else begin
            if (awvalid && !writing) begin
                awready <= 1;
                wptr <= awaddr >> 4;
                w_cnt <= awlen;
                writing <= 1;
            end else awready <= 0;

            if (writing && wvalid) begin
                mem[wptr] <= wdata;
                wptr <= wptr + 1;
                if (w_cnt == 0 || wlast) begin
                    bvalid <= 1;
                    writing <= 0;
                end else w_cnt <= w_cnt - 1;
                wready <= 1;
            end else wready <= 0;

            if (bvalid && bready) bvalid <= 0;
        end
    end

endmodule
