`timescale 1ns / 1ps

module tb_systolic_array_acc;

parameter SIZE = 8;
parameter DATA_WIDTH = 4;
parameter ADDR_WIDTH = 64;
parameter BUFFER_DEPTH = 128;
parameter BASE_ADDR_A = 64;
parameter BASE_ADDR_B = 128;
parameter BASE_ADDR_C = 192;

logic clk = 0;
logic rstn = 0;
always #5 clk = ~clk;

// DUT <-> Memory interface
logic m_axi_arvalid, m_axi_arready;
logic [ADDR_WIDTH-1:0] m_axi_araddr;
logic [7:0] m_axi_arlen;
logic [2:0] m_axi_arsize;
logic [1:0] m_axi_arburst;
logic m_axi_rvalid, m_axi_rready, m_axi_rlast;
logic [127:0] m_axi_rdata;

logic m_axi_awvalid, m_axi_awready;
logic [ADDR_WIDTH-1:0] m_axi_awaddr;
logic [7:0] m_axi_awlen;
logic [2:0] m_axi_awsize;
logic [1:0] m_axi_awburst;

logic m_axi_wvalid, m_axi_wready, m_axi_wlast;
logic [127:0] m_axi_wdata;
logic [15:0] m_axi_wstrb;
logic m_axi_bvalid, m_axi_bready;

// AXI-Lite interface
logic [63:0] s_axi_awaddr, s_axi_araddr;
logic        s_axi_awvalid, s_axi_wvalid, s_axi_arvalid;
logic        s_axi_awready, s_axi_wready, s_axi_arready;
logic [127:0] s_axi_wdata, s_axi_rdata;
logic s_axi_bready = 1, s_axi_bvalid, s_axi_rvalid;
logic [1:0] s_axi_bresp, s_axi_rresp;
logic s_axi_rready = 1;

// Matrices
logic [DATA_WIDTH-1:0] mat_a [0:SIZE*SIZE-1];
logic [DATA_WIDTH-1:0] mat_b [0:SIZE*SIZE-1];
logic [2*DATA_WIDTH-1:0] golden [0:SIZE*SIZE-1];
logic [2*DATA_WIDTH-1:0] result [0:SIZE*SIZE-1];

// --------------------- DUT -----------------------
systolic_array_axi_stream #(
    .SIZE(SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(6),
    .BUFFER_DEPTH(BUFFER_DEPTH)
) dut (
    .s_axi_aclk(clk),
    .s_axi_aresetn(rstn),

    // AXI-Lite
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bready(s_axi_bready),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rready(s_axi_rready),

    // AXI Master
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rready(m_axi_rready),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
);

// ------------------ Memory Model -------------------
axi_memory_model #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(128),
    .DEPTH(20)
) mem (
    .clk(clk),
    .rstn(rstn),

    .arvalid(m_axi_arvalid),
    .arready(m_axi_arready),
    .araddr(m_axi_araddr),
    .arlen(m_axi_arlen),
    .arsize(m_axi_arsize),
    .arburst(m_axi_arburst),
    .rvalid(m_axi_rvalid),
    .rdata(m_axi_rdata),
    .rlast(m_axi_rlast),
    .rready(m_axi_rready),

    .awvalid(m_axi_awvalid),
    .awready(m_axi_awready),
    .awaddr(m_axi_awaddr),
    .awlen(m_axi_awlen),
    .awsize(m_axi_awsize),
    .awburst(m_axi_awburst),
    .wvalid(m_axi_wvalid),
    .wdata(m_axi_wdata),
    .wstrb(m_axi_wstrb),
    .wlast(m_axi_wlast),
    .wready(m_axi_wready),
    .bvalid(m_axi_bvalid),
    .bready(m_axi_bready)
);

// ----------- Helper Tasks --------------

task automatic axi_write(input [5:0] addr, input [31:0] data);
    @(posedge clk);
    s_axi_awaddr <= addr << 2;
    s_axi_wdata <= {96'd0, data};
    s_axi_awvalid <= 1;
    s_axi_wvalid <= 1;
    wait (s_axi_awready && s_axi_wready);
    @(posedge clk);
    s_axi_awvalid <= 0;
    s_axi_wvalid <= 0;
endtask

function logic [127:0] pack_4bit_32(input logic [3:0] src [32]);
    logic [127:0] out;
    for (int i = 0; i < 32; i++)
        out[i*4 +: 4] = src[i];
    return out;
endfunction

task automatic compare_results;
    int mismatches = 0;
    for (int i = 0; i < SIZE*SIZE; i++) begin
        int word_idx = (BASE_ADDR_C >> 4) + i / 16;
        int bit_offset = (i % 16) * 8;
        result[i] = mem.mem[word_idx][bit_offset +: 8];
        if (result[i] !== golden[i]) begin
            $display("Result[%0d] = %0d (expected %0d)", i, result[i], golden[i]);
            mismatches++;
        end else begin
            $display("Result[%0d] = %0d", i, result[i]);
        end
    end
    if (mismatches == 0)
        $display("🎉 Test PASSED");
    else
        $display("FAILED with %0d mismatches", mismatches);
endtask

// --------------------- TEST -----------------------

initial begin
    rstn = 0;
    repeat (5) @(posedge clk);
    rstn = 1;

    // Generate test matrices
    // for (int i = 0; i < SIZE*SIZE; i++) begin
    //     mat_a[i] = i;
    //     mat_b[i] = (SIZE*SIZE - 1 - i);
    // end

//     // Custom Matrix A (no pattern)
// mat_a = '{
//     12,  3,  7,  0,  9,  6, 15,  4,
//      2, 13,  5, 14,  1,  8,  0, 11,
//      7,  1, 12,  6,  5,  3,  9,  2,
//      4, 15, 10,  2, 11,  0,  8,  7,
//      9,  5,  3, 13, 14, 12,  6,  0,
//     11,  0,  8,  1,  7, 10,  2,  5,
//      6, 14,  4,  9,  0,  1, 13,  3,
//      8,  2,  6,  5, 10,  7,  1, 15
// };

// // Custom Matrix B (no pattern)
// mat_b = '{
//      5,  8,  1, 14,  0, 13,  7,  9,
//      6,  0, 10,  3, 15,  2,  4, 11,
//     12,  4,  9,  6,  1,  5,  0,  8,
//      0,  7, 13, 11,  2,  3,  6, 14,
//      3, 10,  5,  0,  8, 12,  1,  4,
//      7, 15,  2,  1,  9,  0, 13,  6,
//     14,  6, 11,  5,  4,  8, 10,  0,
//      1,  9,  3, 12,  6, 14,  2,  5
// };


    // for (int i = 0; i < SIZE*SIZE; i++) begin
    // mat_a[i] = 4'd1;
    // mat_b[i] = 4'd1;
    // end

    // Checkerboard A
// for (int i = 0; i < SIZE*SIZE; i++) begin
//     mat_a[i] = (i % 2);
// end

// // Identity matrix B
// for (int i = 0; i < SIZE*SIZE; i++) begin
//     mat_b[i] = (i / SIZE == i % SIZE) ? 4'd1 : 4'd0;
// end

// // Generate test matrices
for (int i = 0; i < SIZE*SIZE; i++) begin
    mat_a[i] = $urandom_range(0, 15); // 4-bit unsigned values
    mat_b[i] = $urandom_range(0, 15);
end


    // Compute golden result
    for (int r = 0; r < SIZE; r++)
        for (int c = 0; c < SIZE; c++) begin
            golden[r*SIZE + c] = 0;
            for (int k = 0; k < SIZE; k++)
                golden[r*SIZE + c] += mat_a[r*SIZE + k] * mat_b[k*SIZE + c];
        end

    // Pack and write matrix A and B to memory
    for (int blk = 0; blk < SIZE*SIZE/32; blk++) begin
        logic [3:0] tmp_a[32], tmp_b[32];
        for (int j = 0; j < 32; j++) begin
            tmp_a[j] = mat_a[blk*32 + j];
            tmp_b[j] = mat_b[blk*32 + j];
        end

        mem.mem[(BASE_ADDR_A >> 4) + blk] = pack_4bit_32(tmp_a);
        mem.mem[(BASE_ADDR_B >> 4) + blk] = pack_4bit_32(tmp_b);
    end

    // Configure ACC via AXI-Lite
    axi_write(1, SIZE);                 // Matrix size
    axi_write(3, BASE_ADDR_A[31:0]);    // Address A
    axi_write(4, BASE_ADDR_B[31:0]);    // Address B
    axi_write(5, BASE_ADDR_C[31:0]);    // Address C
    axi_write(0, 1);                    // Start

    // Wait for completion
    repeat (100) @(posedge clk);

    // Check output
    compare_results();
    $finish;
end

endmodule


