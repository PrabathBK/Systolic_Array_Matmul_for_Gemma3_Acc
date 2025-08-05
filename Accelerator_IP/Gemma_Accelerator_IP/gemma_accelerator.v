
`timescale 1ns / 1ps

module gemma_accelerator (
    input ap_clk,
    input ap_rst_n,
    // AXI-Lite Control Interface
    input s_axi_control_awvalid,
    output s_axi_control_awready,
    input [5:0] s_axi_control_awaddr,
    input s_axi_control_wvalid,
    output s_axi_control_wready,
    input [31:0] s_axi_control_wdata,
    input [3:0] s_axi_control_wstrb,
    output reg s_axi_control_bvalid,
    input s_axi_control_bready,
    output [1:0] s_axi_control_bresp,
    input s_axi_control_arvalid,
    output s_axi_control_arready,
    input [5:0] s_axi_control_araddr,
    output reg s_axi_control_rvalid,
    input s_axi_control_rready,
    output reg [31:0] s_axi_control_rdata,
    output [1:0] s_axi_control_rresp,

    // AXI Master Memory Interface
    output reg m_axi_gmem_awvalid,
    input m_axi_gmem_awready,
    output reg [63:0] m_axi_gmem_awaddr,
    output reg [7:0] m_axi_gmem_awlen,
    output reg [2:0] m_axi_gmem_awsize,
    output reg [1:0] m_axi_gmem_awburst,
    output reg m_axi_gmem_wvalid,
    input m_axi_gmem_wready,
    output reg [127:0] m_axi_gmem_wdata,
    output reg [15:0] m_axi_gmem_wstrb,
    output reg m_axi_gmem_wlast,
    input m_axi_gmem_bvalid,
    output reg m_axi_gmem_bready,
    input [1:0] m_axi_gmem_bresp,
    output reg m_axi_gmem_arvalid,
    input m_axi_gmem_arready,
    output reg [63:0] m_axi_gmem_araddr,
    output reg [7:0] m_axi_gmem_arlen,
    output reg [2:0] m_axi_gmem_arsize,
    output reg [1:0] m_axi_gmem_arburst,
    input m_axi_gmem_rvalid,
    output reg m_axi_gmem_rready,
    input [127:0] m_axi_gmem_rdata,
    input m_axi_gmem_rlast,
    input [1:0] m_axi_gmem_rresp
);

  // FSM states
  localparam [4:0] S_IDLE=5'h00, S_FETCH_ACT_ADDR=5'h02, S_FETCH_ACT_DATA=5'h03,
                   S_FETCH_WGT_ADDR=5'h04, S_FETCH_WGT_DATA=5'h05, S_WRITE_OUT_ADDR=5'h0D,
                   S_WRITE_OUT_DATA=5'h0E, S_WAIT_WRITE_END=5'h0F, S_DONE=5'h10;

  // AXI-Lite register offsets
  localparam ADDR_CTRL=6'h00, ADDR_STATUS=6'h04;
  localparam C_CODE_ADDR_A_LSB = 6'h10, C_CODE_ADDR_A_MSB = 6'h14;
  localparam C_CODE_ADDR_B_LSB = 6'h18, C_CODE_ADDR_B_MSB = 6'h1C;
  localparam C_CODE_ADDR_C_LSB = 6'h20, C_CODE_ADDR_C_MSB = 6'h24;

  reg [4:0] current_state, next_state;
  reg [7:0] beat_counter;
  reg [63:0] addr_a_reg, addr_b_reg, addr_c_reg;

  // Start signal
  reg start_pulse;

  // AXI-Lite write buffering
  reg awvalid_seen, wvalid_seen;
  reg [5:0] awaddr_latched;
  reg [31:0] wdata_latched;

  // FSM register
  always @(posedge ap_clk) begin
    if (!ap_rst_n)
      current_state <= S_IDLE;
    else
      current_state <= next_state;
  end

  // AXI-Lite interface handshaking
  assign s_axi_control_awready = (current_state == S_IDLE);
  assign s_axi_control_wready  = (current_state == S_IDLE);
  assign s_axi_control_arready = (current_state == S_IDLE) || (s_axi_control_araddr == ADDR_STATUS);
  assign s_axi_control_bresp   = 2'b00;
  assign s_axi_control_rresp   = 2'b00;

  // AXI-Lite register write and pulse logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_bvalid <= 0;
      start_pulse <= 0;
      beat_counter <= 0;
      awvalid_seen <= 0;
      wvalid_seen <= 0;
      addr_a_reg <= 0;
      addr_b_reg <= 0;
      addr_c_reg <= 0;
    end else begin
      if (start_pulse) start_pulse <= 0;

      // Capture AW
      if (s_axi_control_awvalid && s_axi_control_awready) begin
        awaddr_latched <= s_axi_control_awaddr;
        awvalid_seen <= 1;
      end

      // Capture W
      if (s_axi_control_wvalid && s_axi_control_wready) begin
        wdata_latched <= s_axi_control_wdata;
        wvalid_seen <= 1;
      end

      // Decode write once both seen
      if (awvalid_seen && wvalid_seen) begin
        awvalid_seen <= 0;
        wvalid_seen <= 0;
        s_axi_control_bvalid <= 1;

        case (awaddr_latched)
          ADDR_CTRL:         start_pulse <= wdata_latched[0];
          C_CODE_ADDR_A_LSB: addr_a_reg[31:0]  <= wdata_latched;
          C_CODE_ADDR_A_MSB: addr_a_reg[63:32] <= wdata_latched;
          C_CODE_ADDR_B_LSB: addr_b_reg[31:0]  <= wdata_latched;
          C_CODE_ADDR_B_MSB: addr_b_reg[63:32] <= wdata_latched;
          C_CODE_ADDR_C_LSB: addr_c_reg[31:0]  <= wdata_latched;
          C_CODE_ADDR_C_MSB: addr_c_reg[63:32] <= wdata_latched;
        endcase
      end

      if (s_axi_control_bvalid && s_axi_control_bready)
        s_axi_control_bvalid <= 0;

      // AXI burst beat counter logic
      if ((current_state == S_FETCH_ACT_ADDR && m_axi_gmem_arready) ||
          (current_state == S_FETCH_WGT_ADDR && m_axi_gmem_arready) ||
          (current_state == S_WRITE_OUT_ADDR && m_axi_gmem_awready)) begin
        beat_counter <= 0;
      end else if ((current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
                   (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
                   (current_state == S_WRITE_OUT_DATA && m_axi_gmem_wready)) begin
        beat_counter <= beat_counter + 1;
      end
    end
  end

  // AXI-Lite read handling
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_rvalid <= 0;
      s_axi_control_rdata <= 0;
    end else begin
      if (s_axi_control_arvalid && s_axi_control_arready) begin
        s_axi_control_rvalid <= 1;
        if (s_axi_control_araddr == ADDR_STATUS)
          s_axi_control_rdata <= {30'b0, (current_state == S_DONE), (current_state != S_IDLE)};
        else
          s_axi_control_rdata <= 32'hDEADBEEF;
      end else if (s_axi_control_rready) begin
        s_axi_control_rvalid <= 0;
      end
    end
  end

  // FSM control logic
  always @(*) begin
    next_state = current_state;

    m_axi_gmem_awvalid = 0;
    m_axi_gmem_wvalid = 0;
    m_axi_gmem_wlast  = 0;
    m_axi_gmem_bready = 0;
    m_axi_gmem_arvalid = 0;
    m_axi_gmem_rready  = 0;

    m_axi_gmem_awaddr = 0;
    m_axi_gmem_awlen  = 0;
    m_axi_gmem_araddr = 0;
    m_axi_gmem_arlen  = 0;
    m_axi_gmem_wdata  = 32;
    m_axi_gmem_awsize = 3'b100;
    m_axi_gmem_awburst= 2'b01;
    m_axi_gmem_arsize = 3'b100;
    m_axi_gmem_arburst= 2'b01;
    m_axi_gmem_wstrb  = 16'hFFFF;

    case (current_state)
      S_IDLE:
        if (start_pulse)
          next_state = S_FETCH_ACT_ADDR;

      S_FETCH_ACT_ADDR: begin
        m_axi_gmem_arvalid = 1;
        m_axi_gmem_araddr  = addr_a_reg;
        m_axi_gmem_arlen   = 15;
        if (m_axi_gmem_arready)
          next_state = S_FETCH_ACT_DATA;
      end

      S_FETCH_ACT_DATA: begin
        m_axi_gmem_rready = 1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rlast)
          next_state = S_FETCH_WGT_ADDR;
      end

      S_FETCH_WGT_ADDR: begin
        m_axi_gmem_arvalid = 1;
        m_axi_gmem_araddr  = addr_b_reg;
        m_axi_gmem_arlen   = 15;
        if (m_axi_gmem_arready)
          next_state = S_FETCH_WGT_DATA;
      end

      S_FETCH_WGT_DATA: begin
        m_axi_gmem_rready = 1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rlast)
          next_state = S_WRITE_OUT_ADDR;
      end

      S_WRITE_OUT_ADDR: begin
        m_axi_gmem_awvalid = 1;
        m_axi_gmem_awaddr  = addr_c_reg;
        m_axi_gmem_awlen   = 15;
        if (m_axi_gmem_awready)
          next_state = S_WRITE_OUT_DATA;
      end

      S_WRITE_OUT_DATA: begin
        m_axi_gmem_wvalid = 1;
        m_axi_gmem_wlast  = (beat_counter == 15);
        if (m_axi_gmem_wready && m_axi_gmem_wlast)
          next_state = S_WAIT_WRITE_END;
      end

      S_WAIT_WRITE_END: begin
        m_axi_gmem_bready = 1;
        if (m_axi_gmem_bvalid)
          next_state = S_DONE;
      end

      S_DONE:
        next_state = S_IDLE;
    endcase
  end
endmodule

