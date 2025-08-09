`timescale 1ns / 1ps

module gemma_accelerator_tb;

  //-------------------------------------------------------------------------
  // Parameters
  //-------------------------------------------------------------------------
  parameter integer ID_WIDTH           = 12;
  parameter integer BUFFER_DEPTH       = 20;
  parameter integer BUFFER_ADDR_WIDTH  = $clog2(BUFFER_DEPTH);
  parameter integer SYSTOLIC_SIZE      = 16;
  parameter integer DATA_WIDTH         = 8;
  parameter integer ACCUM_WIDTH        = 20;
  parameter integer MATRIX_SIZE        = 16;
  parameter integer NUM_ELEMENTS       = MATRIX_SIZE * MATRIX_SIZE;

  //-------------------------------------------------------------------------
  // Clock & Reset
  //-------------------------------------------------------------------------
  reg ap_clk;
  reg ap_rst_n;

  initial begin
    ap_clk = 0;
    forever #5 ap_clk = ~ap_clk;  // 100 MHz
  end

  //-------------------------------------------------------------------------
  // DUT I/O
  //-------------------------------------------------------------------------
  // AXI-Lite control port
  reg                 s_axi_control_awvalid;
  wire                s_axi_control_awready;
  reg   [5:0]         s_axi_control_awaddr;
  reg                 s_axi_control_wvalid;
  wire                s_axi_control_wready;
  reg   [31:0]        s_axi_control_wdata;
  reg   [3:0]         s_axi_control_wstrb;
  wire                s_axi_control_bvalid;
  reg                 s_axi_control_bready;
  wire  [1:0]         s_axi_control_bresp;
  reg   [0:0]         s_axi_control_awid;
  wire  [0:0]         s_axi_control_bid;
  reg                 s_axi_control_arvalid;
  wire                s_axi_control_arready;
  reg   [5:0]         s_axi_control_araddr;
  wire                s_axi_control_rvalid;
  reg                 s_axi_control_rready;
  wire  [31:0]        s_axi_control_rdata;
  wire  [1:0]         s_axi_control_rresp;
  reg   [0:0]         s_axi_control_arid;
  wire  [0:0]         s_axi_control_rid;

  // AXI-4 master port
  wire [ID_WIDTH-1:0] m_axi_gmem_awid;
  reg  [ID_WIDTH-1:0] m_axi_gmem_bid;
  wire                m_axi_gmem_awvalid;
  reg                 m_axi_gmem_awready;
  wire [63:0]         m_axi_gmem_awaddr;
  wire  [7:0]         m_axi_gmem_awlen;
  wire  [2:0]         m_axi_gmem_awsize;
  wire  [1:0]         m_axi_gmem_awburst;
  wire                m_axi_gmem_wvalid;
  reg                 m_axi_gmem_wready;
  wire [127:0]        m_axi_gmem_wdata;
  wire  [15:0]        m_axi_gmem_wstrb;
  wire                m_axi_gmem_wlast;
  reg                 m_axi_gmem_bvalid;
  wire                m_axi_gmem_bready;
  reg   [1:0]         m_axi_gmem_bresp;
  wire [ID_WIDTH-1:0] m_axi_gmem_arid;
  reg  [ID_WIDTH-1:0] m_axi_gmem_rid;
  wire                m_axi_gmem_arvalid;
  reg                 m_axi_gmem_arready;
  wire [63:0]         m_axi_gmem_araddr;
  wire  [7:0]         m_axi_gmem_arlen;
  wire  [2:0]         m_axi_gmem_arsize;
  wire  [1:0]         m_axi_gmem_arburst;
  reg                 m_axi_gmem_rvalid;
  wire                m_axi_gmem_rready;
  reg  [127:0]        m_axi_gmem_rdata;
  reg                 m_axi_gmem_rlast;
  reg   [1:0]         m_axi_gmem_rresp;

  //-------------------------------------------------------------------------
  // Local "memory" models
  //-------------------------------------------------------------------------
  reg signed [7:0]    mat_a     [0:NUM_ELEMENTS-1];   // identity
  reg signed [7:0]    mat_b     [0:NUM_ELEMENTS-1];   // ramp
  reg signed [31:0]   mat_c_exp [0:NUM_ELEMENTS-1];   // expected
  reg signed [31:0]   mat_c_act [0:NUM_ELEMENTS-1];   // captured

  //-------------------------------------------------------------------------
  // Addresses & Offsets
  //-------------------------------------------------------------------------
  localparam [63:0] ADDR_A      = 64'h00021000;
  localparam [63:0] ADDR_B      = 64'h00022000;
  localparam [63:0] ADDR_C      = 64'h00023000;

  localparam [5:0]  ADDR_CTRL   = 6'h00;
  localparam [5:0]  ADDR_STATUS = 6'h04;
  localparam [5:0]  A_LSB       = 6'h10;
  localparam [5:0]  A_MSB       = 6'h14;
  localparam [5:0]  B_LSB       = 6'h18;
  localparam [5:0]  B_MSB       = 6'h1C;
  localparam [5:0]  C_LSB       = 6'h20;
  localparam [5:0]  C_MSB       = 6'h24;

  //-------------------------------------------------------------------------
  // TB state
  //-------------------------------------------------------------------------
  reg  [7:0] read_count, write_count;
  reg        rd_a, rd_b;
  integer    errors;

  //-------------------------------------------------------------------------
  // DUT instantiation
  //-------------------------------------------------------------------------
  gemma_accelerator #(
    .ID_WIDTH           (ID_WIDTH),
    .BUFFER_DEPTH       (BUFFER_DEPTH),
    .BUFFER_ADDR_WIDTH  (BUFFER_ADDR_WIDTH),
    .SYSTOLIC_SIZE      (SYSTOLIC_SIZE),
    .DATA_WIDTH         (DATA_WIDTH),
    .ACCUM_WIDTH        (ACCUM_WIDTH)
  ) dut (
    .ap_clk               (ap_clk),
    .ap_rst_n             (ap_rst_n),
    // AXI-Lite
    .s_axi_control_awvalid(s_axi_control_awvalid),
    .s_axi_control_awready(s_axi_control_awready),
    .s_axi_control_awaddr (s_axi_control_awaddr),
    .s_axi_control_wvalid (s_axi_control_wvalid),
    .s_axi_control_wready (s_axi_control_wready),
    .s_axi_control_wdata  (s_axi_control_wdata),
    .s_axi_control_wstrb  (s_axi_control_wstrb),
    .s_axi_control_bvalid (s_axi_control_bvalid),
    .s_axi_control_bready (s_axi_control_bready),
    .s_axi_control_bresp  (s_axi_control_bresp),
    .s_axi_control_awid   (s_axi_control_awid),
    .s_axi_control_bid    (s_axi_control_bid),
    .s_axi_control_arvalid(s_axi_control_arvalid),
    .s_axi_control_arready(s_axi_control_arready),
    .s_axi_control_araddr (s_axi_control_araddr),
    .s_axi_control_rvalid (s_axi_control_rvalid),
    .s_axi_control_rready (s_axi_control_rready),
    .s_axi_control_rdata  (s_axi_control_rdata),
    .s_axi_control_rresp  (s_axi_control_rresp),
    .s_axi_control_arid   (s_axi_control_arid),
    .s_axi_control_rid    (s_axi_control_rid),
    // AXI-4 master
    .m_axi_gmem_awid      (m_axi_gmem_awid),
    .m_axi_gmem_bid       (m_axi_gmem_bid),
    .m_axi_gmem_awvalid   (m_axi_gmem_awvalid),
    .m_axi_gmem_awready   (m_axi_gmem_awready),
    .m_axi_gmem_awaddr    (m_axi_gmem_awaddr),
    .m_axi_gmem_awlen     (m_axi_gmem_awlen),
    .m_axi_gmem_awsize    (m_axi_gmem_awsize),
    .m_axi_gmem_awburst   (m_axi_gmem_awburst),
    .m_axi_gmem_wvalid    (m_axi_gmem_wvalid),
    .m_axi_gmem_wready    (m_axi_gmem_wready),
    .m_axi_gmem_wdata     (m_axi_gmem_wdata),
    .m_axi_gmem_wstrb     (m_axi_gmem_wstrb),
    .m_axi_gmem_wlast     (m_axi_gmem_wlast),
    .m_axi_gmem_bvalid    (m_axi_gmem_bvalid),
    .m_axi_gmem_bready    (m_axi_gmem_bready),
    .m_axi_gmem_bresp     (m_axi_gmem_bresp),
    .m_axi_gmem_arid      (m_axi_gmem_arid),
    .m_axi_gmem_rid       (m_axi_gmem_rid),
    .m_axi_gmem_arvalid   (m_axi_gmem_arvalid),
    .m_axi_gmem_arready   (m_axi_gmem_arready),
    .m_axi_gmem_araddr    (m_axi_gmem_araddr),
    .m_axi_gmem_arlen     (m_axi_gmem_arlen),
    .m_axi_gmem_arsize    (m_axi_gmem_arsize),
    .m_axi_gmem_arburst   (m_axi_gmem_arburst),
    .m_axi_gmem_rvalid    (m_axi_gmem_rvalid),
    .m_axi_gmem_rready    (m_axi_gmem_rready),
    .m_axi_gmem_rdata     (m_axi_gmem_rdata),
    .m_axi_gmem_rlast     (m_axi_gmem_rlast),
    .m_axi_gmem_rresp     (m_axi_gmem_rresp)
  );

  //-------------------------------------------------------------------------
  // Initialize matrices (ramp + identity)
  //-------------------------------------------------------------------------
  task init_matrices;
  integer i, r, c;
  begin
    for (i = 0; i < NUM_ELEMENTS; i = i + 1)
      mat_b[i] = i[7:0];
    for (r = 0; r < MATRIX_SIZE; r = r + 1)
      for (c = 0; c < MATRIX_SIZE; c = c + 1)
        mat_a[r*MATRIX_SIZE + c] = (r==c) ? 8'sd1 : 8'sd0;
    for (i = 0; i < NUM_ELEMENTS; i = i + 1)
      mat_c_exp[i] = {{16{mat_b[i][7]}}, mat_b[i]};
  end
  endtask

  //-------------------------------------------------------------------------
  // AXI-Lite write (blocking assigns)
  //-------------------------------------------------------------------------
  task axi_lite_wr(input [5:0] addr, input [31:0] data);
  begin
    @(posedge ap_clk);
      s_axi_control_awvalid = 1;
      s_axi_control_awaddr  = addr;
      s_axi_control_awid    = 0;
      s_axi_control_wvalid  = 1;
      s_axi_control_wdata   = data;
      s_axi_control_wstrb   = 4'hF;
      s_axi_control_bready  = 1;
    wait (s_axi_control_awready && s_axi_control_wready);
    @(posedge ap_clk);
      s_axi_control_awvalid = 0;
      s_axi_control_wvalid  = 0;
    wait (s_axi_control_bvalid);
    @(posedge ap_clk);
      s_axi_control_bready  = 0;
  end
  endtask

  //-------------------------------------------------------------------------
  // AXI-Lite read (blocking assigns)
  //-------------------------------------------------------------------------
  task axi_lite_rd(input [5:0] addr, output [31:0] data);
  begin
    @(posedge ap_clk);
      s_axi_control_arvalid = 1;
      s_axi_control_araddr  = addr;
      s_axi_control_arid    = 0;
      s_axi_control_rready  = 1;
    wait (s_axi_control_arready);
    @(posedge ap_clk);
      s_axi_control_arvalid = 0;
    wait (s_axi_control_rvalid);
      data = s_axi_control_rdata;
    @(posedge ap_clk);
      s_axi_control_rready  = 0;
  end
  endtask

//  //-------------------------------------------------------------------------
//  // AXI read-response model (fixed to emit beat 0)
//  //-------------------------------------------------------------------------
//  always @(posedge ap_clk) begin
//    if (!ap_rst_n) begin
//      m_axi_gmem_arready <= 0;
//      m_axi_gmem_rvalid  <= 0;
//      m_axi_gmem_rdata   <= 0;
//      m_axi_gmem_rlast   <= 0;
//      m_axi_gmem_rresp   <= 2'b00;
//      m_axi_gmem_rid     <= 0;
//      read_count         <= 0;
//      rd_a               <= 0;
//      rd_b               <= 0;
//    end else begin
//      // AR handshake + start R burst
//      if (m_axi_gmem_arvalid && !m_axi_gmem_arready) begin
//        m_axi_gmem_arready <= 1;
//        m_axi_gmem_rid     <= m_axi_gmem_arid;
//        read_count         <= 0;
//        rd_a               <= (m_axi_gmem_araddr == ADDR_A);
//        rd_b               <= (m_axi_gmem_araddr == ADDR_B);
//        m_axi_gmem_rvalid  <= 1;
//      end else begin
//        m_axi_gmem_arready <= 0;
//      end

//      // Drive RDATA & RLAST whenever RVALID
//      if (m_axi_gmem_rvalid) begin
//        integer base, i;
//        base = read_count * 16;
//        for (i = 0; i < 16; i = i + 1) begin
//          m_axi_gmem_rdata[i*8 +: 8] <= rd_a ? mat_a[base+i] : mat_b[base+i];
//        end
//        m_axi_gmem_rlast <= (read_count == 8'd15);

//        // Advance or end burst
//        if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
//          if (m_axi_gmem_rlast) begin
//            m_axi_gmem_rvalid <= 0;
//            m_axi_gmem_rlast  <= 0;
//          end else begin
//            read_count <= read_count + 1;
//          end
//        end
//      end
//    end
//  end
  
  //-------------------------------------------------------------------------
// AXI read-response model (FIXED)
//-------------------------------------------------------------------------
 integer next_base, j;
 integer base, i;
 
always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    m_axi_gmem_arready <= 0;
    m_axi_gmem_rvalid  <= 0;
    m_axi_gmem_rdata   <= 0;
    m_axi_gmem_rlast   <= 0;
    m_axi_gmem_rresp   <= 2'b00;
    m_axi_gmem_rid     <= 0;
    read_count         <= 0;
    rd_a               <= 0;
    rd_b               <= 0;
  end else begin
    // AR handshake + start R burst
    if (m_axi_gmem_arvalid && !m_axi_gmem_arready) begin
      m_axi_gmem_arready <= 1;
      m_axi_gmem_rid     <= m_axi_gmem_arid;
      read_count         <= 0;
      rd_a               <= (m_axi_gmem_araddr == ADDR_A);
      rd_b               <= (m_axi_gmem_araddr == ADDR_B);
      m_axi_gmem_rvalid  <= 1;
      
      // Load first beat data immediately

      base = 0;
      for (i = 0; i < 16; i = i + 1) begin
        m_axi_gmem_rdata[i*8 +: 8] <= (m_axi_gmem_araddr == ADDR_A) ? mat_a[i] : mat_b[i];
      end
      m_axi_gmem_rlast <= (8'd0 == 8'd15);  // Check if single beat transfer
    end else begin
      m_axi_gmem_arready <= 0;
    end

    // Handle data transfer and burst advancement
    if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
      if (m_axi_gmem_rlast) begin
        // End of burst
        m_axi_gmem_rvalid <= 0;
        m_axi_gmem_rlast  <= 0;
      end else begin
        // Advance to next beat
        read_count <= read_count + 1;
        
        // Prepare next beat data

        next_base = (read_count + 1) * 16;
        for (j = 0; j < 16; j = j + 1) begin
          m_axi_gmem_rdata[j*8 +: 8] <= rd_a ? mat_a[next_base + j] : mat_b[next_base + j];
        end
        m_axi_gmem_rlast <= ((read_count + 1) == 8'd15);  // Check if next beat is last
      end
    end
  end
end

  //-------------------------------------------------------------------------
  // AXI write-response model (unchanged)
  //-------------------------------------------------------------------------
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      m_axi_gmem_awready <= 0;
      m_axi_gmem_wready  <= 0;
      m_axi_gmem_bvalid  <= 0;
      m_axi_gmem_bresp   <= 2'b00;
      m_axi_gmem_bid     <= 0;
      write_count        <= 0;
    end else begin
      if (m_axi_gmem_awvalid && !m_axi_gmem_awready) begin
        m_axi_gmem_awready <= 1;
        m_axi_gmem_bid     <= m_axi_gmem_awid;
        write_count        <= 0;
      end else begin
        m_axi_gmem_awready <= 0;
      end

      if (m_axi_gmem_awready)
        m_axi_gmem_wready <= 1;

      if (m_axi_gmem_wvalid && m_axi_gmem_wready) begin
        integer base, i;
        base = write_count * 8;
        for (i = 0; i < 8; i = i + 1) begin
          mat_c_act[base + i] = {{16{m_axi_gmem_wdata[i*16+15]}},
                                 m_axi_gmem_wdata[i*16 +:16]};
        end
        if (m_axi_gmem_wlast) begin
          m_axi_gmem_wready <= 0;
          m_axi_gmem_bvalid <= 1;
        end else begin
          write_count <= write_count + 1;
        end
      end

      if (m_axi_gmem_bvalid && m_axi_gmem_bready)
        m_axi_gmem_bvalid <= 0;
    end
  end

  //-------------------------------------------------------------------------
  // Wait for DONE bit-0
  //-------------------------------------------------------------------------
  task wait_done;
    reg [31:0] st;
    integer    to;
    begin
      to = 0;
      do begin
        #100;
        axi_lite_rd(ADDR_STATUS, st);
        to = to + 1;
        if (to > 10000) begin
          $display("ERROR: done timeout");
          $finish;
        end
      end while ((st & 32'h1) != 32'h1);
      $display(">>> Accelerator DONE @ %0t", $time);
    end
  endtask

  //-------------------------------------------------------------------------
  // Verify results
  //-------------------------------------------------------------------------
  task verify;
    integer i, r, c;
    begin
      errors = 0;
      for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin
        if (mat_c_act[i] !== mat_c_exp[i]) begin
          r = i / MATRIX_SIZE;
          c = i % MATRIX_SIZE;
          $display("ERR [%0d,%0d]: exp=%0d got=%0d",
                   r, c, mat_c_exp[i], mat_c_act[i]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("+++ PASS: all outputs match");
      else
        $display("*** FAIL: %0d mismatches", errors);
    end
  endtask

  //-------------------------------------------------------------------------
  // Main Test
  //-------------------------------------------------------------------------
  initial begin
    ap_rst_n             = 0;
    s_axi_control_awvalid = 0;
    s_axi_control_wvalid  = 0;
    s_axi_control_bready  = 0;
    s_axi_control_arvalid = 0;
    s_axi_control_rready  = 0;
    #100;
    ap_rst_n = 1;

    init_matrices();

    // Program A, B, C bases
    axi_lite_wr(A_LSB, ADDR_A[31:0]);
    axi_lite_wr(A_MSB, ADDR_A[63:32]);
    axi_lite_wr(B_LSB, ADDR_B[31:0]);
    axi_lite_wr(B_MSB, ADDR_B[63:32]);
    axi_lite_wr(C_LSB, ADDR_C[31:0]);
    axi_lite_wr(C_MSB, ADDR_C[63:32]);

    // Kick off
    axi_lite_wr(ADDR_CTRL, 32'h1);

    wait_done();
    verify();

    if (errors == 0)
      $display("=== TEST PASSED ===");
    else
      $display("=== TEST FAILED: %0d errors ===", errors);

    $finish;
  end

  //-------------------------------------------------------------------------
  // Timeout watchdog
  //-------------------------------------------------------------------------
  initial begin
    #50_000_000;
    $display("ERROR: simulation timed out");
    $finish;
  end

endmodule
