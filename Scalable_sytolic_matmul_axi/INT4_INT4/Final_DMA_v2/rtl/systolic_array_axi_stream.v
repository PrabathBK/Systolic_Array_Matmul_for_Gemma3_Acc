`timescale 1ns / 1ps

module systolic_array_axi_stream #(
    parameter SIZE = 8,
    parameter DATA_WIDTH = 4,
    parameter ADDR_WIDTH = 6,
    parameter BUFFER_DEPTH = 64
)(
    input wire s_axi_aclk,
    input wire s_axi_aresetn,

    // AXI4-Lite Slave Interface (Control)
    input  wire [63:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output reg          s_axi_awready,
    input  wire [127:0] s_axi_wdata,
    input  wire         s_axi_wvalid,
    output reg          s_axi_wready,
    input  wire         s_axi_bready,
    output reg          s_axi_bvalid,
    output reg [1:0]    s_axi_bresp,
    input  wire [63:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output reg          s_axi_arready,
    output reg [127:0]  s_axi_rdata,
    output reg          s_axi_rvalid,
    output reg [1:0]    s_axi_rresp,
    input  wire         s_axi_rready,

    // AXI Master Interface
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    output reg [63:0]   m_axi_araddr,
    output reg [7:0]    m_axi_arlen,
    output reg [2:0]    m_axi_arsize,
    output reg [1:0]    m_axi_arburst,
    input  wire         m_axi_rvalid,
    input  wire [127:0] m_axi_rdata,
    input  wire         m_axi_rlast,
    output reg          m_axi_rready,

    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    output reg [63:0]   m_axi_awaddr,
    output reg [7:0]    m_axi_awlen,
    output reg [2:0]    m_axi_awsize,
    output reg [1:0]    m_axi_awburst,

    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    output reg [127:0]  m_axi_wdata,
    output reg [15:0]   m_axi_wstrb,
    output reg          m_axi_wlast,

    input  wire         m_axi_bvalid,
    output reg          m_axi_bready
);

// --------------------------------------------------
// Control Registers
// --------------------------------------------------
localparam REG_CONTROL      = 0;
localparam REG_SIZE         = 1;
localparam REG_STATUS       = 2;
localparam REG_ADDR_A_BASE  = 3;
localparam REG_ADDR_B_BASE  = 4;
localparam REG_ADDR_C_BASE  = 5;

reg [31:0] slv_reg [0:15];
wire       start       = slv_reg[REG_CONTROL][0];
wire [7:0] matrix_size = slv_reg[REG_SIZE][7:0];
// wire [63:0] addr_a     = {slv_reg[REG_ADDR_A_BASE], 2'b00};
// wire [63:0] addr_b     = {slv_reg[REG_ADDR_B_BASE], 2'b00};
// wire [63:0] addr_c     = {slv_reg[REG_ADDR_C_BASE], 2'b00};

wire [63:0] addr_a     = {slv_reg[REG_ADDR_A_BASE]};
wire [63:0] addr_b     = {slv_reg[REG_ADDR_B_BASE]};
wire [63:0] addr_c     = {slv_reg[REG_ADDR_C_BASE]};

wire done, result_valid;

// --------------------------------------------------
// AXI-Lite Read/Write Handling
// --------------------------------------------------
always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        s_axi_awready <= 0; s_axi_wready <= 0; s_axi_bvalid <= 0;
        s_axi_arready <= 0; s_axi_rvalid <= 0; s_axi_rdata <= 0;
    end else begin
        s_axi_awready <= s_axi_awvalid;
        s_axi_wready <= s_axi_wvalid;

        if (s_axi_awvalid && s_axi_wvalid) begin
            slv_reg[s_axi_awaddr[5:2]] <= s_axi_wdata[31:0];
            s_axi_bvalid <= 1;
        end

        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 0;

        s_axi_arready <= s_axi_arvalid;
        if (s_axi_arvalid) begin
            s_axi_rdata <= {96'd0, slv_reg[s_axi_araddr[5:2]]};
            s_axi_rvalid <= 1;
        end
        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 0;
    end
end

// --------------------------------------------------
// Read FSM with 256-bit buffering (Matrix A and B)
// --------------------------------------------------
reg reading_a, reading_b, compute_start;
reg [5:0] load_idx;
reg weight_load_en, activation_load_en;

// reg [255:0] axi_rdata_reg_A, axi_rdata_reg_B;
reg [1:0] burst_count;
reg [127:0] last_rdata;

reg [255:0] weight_buffer, activation_buffer;

always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        reading_a <= 0; reading_b <= 0; compute_start <= 0;
        m_axi_arvalid <= 0; m_axi_rready <= 1;
        burst_count <= 0;
        // axi_rdata_reg_A <= 0;
        // axi_rdata_reg_B <= 0;
        weight_load_en <= 0;
        activation_load_en <= 0;
        load_idx <= 0;
    end else begin
        weight_load_en <= 0;
        activation_load_en <= 0;
        compute_start <= 0;

        // AXI read response collection
        if (m_axi_rvalid && m_axi_rready) begin
            case (burst_count)
                0: begin
                    last_rdata <= m_axi_rdata;
                    burst_count <= 1;
                end
                1: begin
                    if (reading_a) begin
                        // axi_rdata_reg_A <= {m_axi_rdata, last_rdata};
                        activation_buffer <= {m_axi_rdata, last_rdata};
                        activation_load_en <= 1;
                    end else if (reading_b) begin
                        // axi_rdata_reg_B <= {m_axi_rdata, last_rdata};
                        weight_buffer <= {m_axi_rdata, last_rdata};
                        weight_load_en <= 1;
                    end
                    burst_count <= 0;
                    load_idx <= load_idx + 1;

                    if (m_axi_rlast) begin
                        if (reading_a) begin
                            reading_a <= 0;
                            reading_b <= 1;
                            m_axi_araddr <= addr_b;
                            m_axi_arvalid <= 1;
                            load_idx <= 0;
                        end else if (reading_b) begin
                            reading_b <= 0;
                            compute_start <= 1;
                            load_idx <= 0;
                        end
                    end
                end
            endcase
        end

        if (start && !reading_a && !reading_b) begin
            m_axi_araddr <= addr_a;
            m_axi_arlen <= 1; // Two 128-bit beats (2x128 = 256)
            m_axi_arsize <= 3'b100;
            m_axi_arburst <= 2'b01;
            m_axi_arvalid <= 1;
            reading_a <= 1;
        end else if ((reading_a || reading_b) && m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 0;
        end
    end
end

// --------------------------------------------------
// Systolic Core Instance
// --------------------------------------------------
wire [SIZE*SIZE*2*DATA_WIDTH-1:0] result_matrix;

systolic_array_with_buffers #(
    .SIZE(SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .BUFFER_DEPTH(BUFFER_DEPTH)
) core (
    .clk(s_axi_aclk),
    .rst(~s_axi_aresetn),
    .start(compute_start),
    .weight_load_en(weight_load_en),
    .weight_addr(load_idx),
    .weight_data(weight_buffer),
    .activation_load_en(activation_load_en),
    .activation_addr(load_idx),
    .activation_data(activation_buffer),
    .matrix_size(matrix_size),
    .done(done),
    .result_matrix(result_matrix),
    .result_valid(result_valid)
);

// --------------------------------------------------
// AXI Writeback FSM - For 4-beat burst
// --------------------------------------------------
reg writing_result;
reg [1:0] burst_counter;
reg [511:0] result_buffer;

always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        m_axi_awvalid   <= 0;
        m_axi_awaddr    <= 0;
        m_axi_awlen     <= 0;
        m_axi_awsize    <= 0;
        m_axi_awburst   <= 0;

        m_axi_wvalid    <= 0;
        m_axi_wdata     <= 0;
        m_axi_wstrb     <= 0;
        m_axi_wlast     <= 0;

        m_axi_bready    <= 1;

        writing_result  <= 0;
        burst_counter   <= 0;
        result_buffer   <= 0;
    end else begin
        // Start write burst
        if (result_valid && !writing_result) begin
            result_buffer   <= result_matrix;
            m_axi_awaddr    <= addr_c;
            m_axi_awlen     <= 3; // 4 beats
            m_axi_awsize    <= 3'b100;
            m_axi_awburst   <= 2'b01;
            m_axi_awvalid   <= 1;
            burst_counter   <= 0;
            writing_result  <= 1;
        end

        // Once AW is accepted
        if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 0;
        end

        // Drive write data when ready
        if (writing_result && (!m_axi_wvalid || (m_axi_wvalid && m_axi_wready))) begin
            m_axi_wvalid <= 1;
            m_axi_wstrb  <= 16'hFFFF;
            m_axi_wlast  <= (burst_counter == 3);

            case (burst_counter)
                0: m_axi_wdata <= result_buffer[255:128];
                1: m_axi_wdata <= result_buffer[383:256];
                2: m_axi_wdata <= result_buffer[511:384];
                default:m_axi_wdata <= result_buffer[127:0];
            endcase

            if (burst_counter == 3) begin
                writing_result <= 0;
            end else begin
                burst_counter <= burst_counter + 1;
            end
        end
    end
end


// --------------------------------------------------
// Update Status Register
// --------------------------------------------------
always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
        slv_reg[REG_STATUS] <= 0;
    else begin
        slv_reg[REG_STATUS][0] <= done;
        slv_reg[REG_STATUS][1] <= result_valid;
    end
end

endmodule
