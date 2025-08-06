
`timescale 1ns / 1ps

module gemma_accelerator #(
  parameter integer ID_WIDTH = 12
)(
  input  wire                  ap_clk,
  input  wire                  ap_rst_n,
  // AXI-Lite Control Interface (32-bit, with ID/last)
  input  wire                  s_axi_control_awvalid,
  output wire                  s_axi_control_awready,
  input  wire [5:0]            s_axi_control_awaddr,
  input  wire                  s_axi_control_wvalid,
  output wire                  s_axi_control_wready,
  input  wire [31:0]           s_axi_control_wdata,
  input  wire [3:0]            s_axi_control_wstrb,
  output reg                   s_axi_control_bvalid,
  input  wire                  s_axi_control_bready,
  output wire [1:0]            s_axi_control_bresp,
  input  wire [1-1:0]   s_axi_control_awid,    // <<< NEW
  output wire [1-1:0]   s_axi_control_bid,     // <<< NEW
  input  wire                  s_axi_control_arvalid,
  output wire                  s_axi_control_arready,
  input  wire [5:0]            s_axi_control_araddr,
  output reg                   s_axi_control_rvalid,
  input  wire                  s_axi_control_rready,
  output reg  [31:0]           s_axi_control_rdata,
  output wire [1:0]            s_axi_control_rresp,
  input  wire [1-1:0]   s_axi_control_arid,    // <<< NEW
  output wire [1-1:0]   s_axi_control_rid,     // <<< NEW

  // AXI4-Master Memory Interface
  output reg  [ID_WIDTH-1:0]   m_axi_gmem_awid,
  input  wire [ID_WIDTH-1:0]   m_axi_gmem_bid,
  output reg                   m_axi_gmem_awvalid,
  input  wire                  m_axi_gmem_awready,
  output reg  [63:0]           m_axi_gmem_awaddr,
  output reg  [7:0]            m_axi_gmem_awlen,
  output reg  [2:0]            m_axi_gmem_awsize,
  output reg  [1:0]            m_axi_gmem_awburst,
  output reg                   m_axi_gmem_wvalid,
  input  wire                  m_axi_gmem_wready,
  output reg  [127:0]          m_axi_gmem_wdata,
  output reg  [15:0]           m_axi_gmem_wstrb,
  output reg                   m_axi_gmem_wlast,
  input  wire                  m_axi_gmem_bvalid,
  output reg                   m_axi_gmem_bready,
  input  wire [1:0]            m_axi_gmem_bresp,
  output reg  [ID_WIDTH-1:0]   m_axi_gmem_arid,
  input  wire [ID_WIDTH-1:0]   m_axi_gmem_rid,
  output reg                   m_axi_gmem_arvalid,
  input  wire                  m_axi_gmem_arready,
  output reg  [63:0]           m_axi_gmem_araddr,
  output reg  [7:0]            m_axi_gmem_arlen,
  output reg  [2:0]            m_axi_gmem_arsize,
  output reg  [1:0]            m_axi_gmem_arburst,
  input  wire                  m_axi_gmem_rvalid,
  output reg                   m_axi_gmem_rready,
  input  wire [127:0]          m_axi_gmem_rdata,
  input  wire                  m_axi_gmem_rlast,
  input  wire [1:0]            m_axi_gmem_rresp
);

  // FSM states
  localparam [4:0]
    S_IDLE            = 5'h00,
    S_FETCH_ACT_ADDR  = 5'h02,
    S_FETCH_ACT_DATA  = 5'h03,
    S_FETCH_WGT_ADDR  = 5'h04,
    S_FETCH_WGT_DATA  = 5'h05,
    S_WRITE_OUT_ADDR  = 5'h0D,
    S_WRITE_OUT_DATA  = 5'h0E,
    S_WAIT_WRITE_END  = 5'h0F,
    S_DONE            = 5'h10;

  // AXI-Lite register offsets
  localparam [5:0]
    ADDR_CTRL   = 6'h00,
    ADDR_STATUS = 6'h04,
    A_LSB       = 6'h10,
    A_MSB       = 6'h14,
    B_LSB       = 6'h18,
    B_MSB       = 6'h1C,
    C_LSB       = 6'h20,
    C_MSB       = 6'h24;

  reg [4:0]   current_state, next_state;
  reg [7:0]   beat_counter;
  reg [63:0]  addr_a_reg, addr_b_reg, addr_c_reg;
  reg         start_pulse;
  // AXI-Lite write buffer
  reg         awvalid_seen, wvalid_seen;
  reg [5:0]   awaddr_latched;
  reg [31:0]  wdata_latched;

  // State register
  always @(posedge ap_clk) begin
    if (!ap_rst_n)
      current_state <= S_IDLE;
    else
      current_state <= next_state;
  end

  // AXI-Lite handshakes & ID pass-through
  assign s_axi_control_awready = (current_state == S_IDLE);
  assign s_axi_control_wready  = (current_state == S_IDLE);
  assign s_axi_control_arready = (current_state == S_IDLE) || (s_axi_control_araddr == ADDR_STATUS);
  assign s_axi_control_bresp   = 2'b00;
  assign s_axi_control_rresp   = 2'b00;

  // reflect AWID → BID, ARID → RID
  assign s_axi_control_bid  = s_axi_control_awid;
  assign s_axi_control_rid  = s_axi_control_arid;

  // AXI-Lite write logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_bvalid <= 1'b0;
      start_pulse          <= 1'b0;
      beat_counter         <= 8'd0;
      awvalid_seen         <= 1'b0;
      wvalid_seen          <= 1'b0;
      addr_a_reg           <= 64'd0;
      addr_b_reg           <= 64'd0;
      addr_c_reg           <= 64'd0;
    end else begin
      if (start_pulse)
        start_pulse <= 1'b0;

      // capture AW
      if (s_axi_control_awvalid && s_axi_control_awready) begin
        awaddr_latched <= s_axi_control_awaddr;
        awvalid_seen   <= 1'b1;
      end
      // capture W
      if (s_axi_control_wvalid && s_axi_control_wready) begin
        wdata_latched <= s_axi_control_wdata;
        wvalid_seen   <= 1'b1;
      end
      // commit write
      if (awvalid_seen && wvalid_seen) begin
        awvalid_seen <= 1'b0;
        wvalid_seen  <= 1'b0;
        s_axi_control_bvalid <= 1'b1;
        case (awaddr_latched)
          ADDR_CTRL: start_pulse          <= wdata_latched[0];
          A_LSB:     addr_a_reg[31:0]     <= wdata_latched;
          A_MSB:     addr_a_reg[63:32]    <= wdata_latched;
          B_LSB:     addr_b_reg[31:0]     <= wdata_latched;
          B_MSB:     addr_b_reg[63:32]    <= wdata_latched;
          C_LSB:     addr_c_reg[31:0]     <= wdata_latched;
          C_MSB:     addr_c_reg[63:32]    <= wdata_latched;
        endcase
      end
      if (s_axi_control_bvalid && s_axi_control_bready)
        s_axi_control_bvalid <= 1'b0;

      // beat counter
      if ((current_state==S_FETCH_ACT_ADDR && m_axi_gmem_arready) ||
          (current_state==S_FETCH_WGT_ADDR && m_axi_gmem_arready) ||
          (current_state==S_WRITE_OUT_ADDR && m_axi_gmem_awready))
        beat_counter <= 8'd0;
      else if ((current_state==S_FETCH_ACT_DATA  && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
               (current_state==S_FETCH_WGT_DATA  && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
               (current_state==S_WRITE_OUT_DATA && m_axi_gmem_wready))
        beat_counter <= beat_counter + 1'b1;
    end
  end

  // AXI-Lite read logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_rvalid <= 1'b0;
      s_axi_control_rdata  <= 32'h0;
    end else begin
      if (s_axi_control_arvalid && s_axi_control_arready) begin
        s_axi_control_rvalid <= 1'b1;
        if (s_axi_control_araddr == ADDR_STATUS)
          s_axi_control_rdata <= {30'd0, (current_state == S_DONE), (current_state != S_IDLE)};
        else
          s_axi_control_rdata <= 32'hDEADBEEF;
      end else if (s_axi_control_rready) begin
        s_axi_control_rvalid <= 1'b0;
      end
    end
  end

  // FSM & Data-AXI interface
  always @(*) begin
    next_state          = current_state;
    m_axi_gmem_awid     = {ID_WIDTH{1'b0}};
    m_axi_gmem_arid     = {ID_WIDTH{1'b0}};
    m_axi_gmem_awvalid  = 1'b0;
    m_axi_gmem_wvalid   = 1'b0;
    m_axi_gmem_wlast    = 1'b0;
    m_axi_gmem_bready   = 1'b0;
    m_axi_gmem_arvalid  = 1'b0;
    m_axi_gmem_rready   = 1'b0;
    m_axi_gmem_awaddr   = 64'd0;
    m_axi_gmem_awlen    = 8'd0;
    m_axi_gmem_araddr   = 64'd0;
    m_axi_gmem_arlen    = 8'd0;
    m_axi_gmem_wdata    = 128'h0;
    m_axi_gmem_awsize   = 3'b100;
    m_axi_gmem_awburst  = 2'b01;
    m_axi_gmem_arsize   = 3'b100;
    m_axi_gmem_arburst  = 2'b01;
    m_axi_gmem_wstrb    = 16'hFFFF;

    case (current_state)
      S_IDLE: if (start_pulse)
        next_state = S_FETCH_ACT_ADDR;

      S_FETCH_ACT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = addr_a_reg;
        m_axi_gmem_arlen   = 8'd15;
        if (m_axi_gmem_arready) next_state = S_FETCH_ACT_DATA;
      end

      S_FETCH_ACT_DATA: if (m_axi_gmem_rvalid && m_axi_gmem_rready)
        if (m_axi_gmem_rlast) next_state = S_FETCH_WGT_ADDR;

      S_FETCH_WGT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = addr_b_reg;
        m_axi_gmem_arlen   = 8'd15;
        if (m_axi_gmem_arready) next_state = S_FETCH_WGT_DATA;
      end

      S_FETCH_WGT_DATA: if (m_axi_gmem_rvalid && m_axi_gmem_rready)
        if (m_axi_gmem_rlast) next_state = S_WRITE_OUT_ADDR;

      S_WRITE_OUT_ADDR: begin
        m_axi_gmem_awvalid = 1'b1;
        m_axi_gmem_awaddr  = addr_c_reg;
        m_axi_gmem_awlen   = 8'd15;
        if (m_axi_gmem_awready) next_state = S_WRITE_OUT_DATA;
      end

      S_WRITE_OUT_DATA: begin
        m_axi_gmem_wvalid = 1'b1;
        m_axi_gmem_wlast  = (beat_counter == 8'd15);
        if (m_axi_gmem_wready && m_axi_gmem_wlast) next_state = S_WAIT_WRITE_END;
      end

      S_WAIT_WRITE_END: begin
        m_axi_gmem_bready = 1'b1;
        if (m_axi_gmem_bvalid) next_state = S_DONE;
      end

      S_DONE: next_state = S_IDLE;
    endcase
  end

endmodule
