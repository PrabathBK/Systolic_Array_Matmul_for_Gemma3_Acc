// `timescale 1ns / 1ps

// module gemma_accelerator_tb;

//   //-------------------------------------------------------------------------
//   // Parameters
//   //-------------------------------------------------------------------------
//   parameter integer ID_WIDTH           = 12;
//   parameter integer BUFFER_DEPTH       = 20;
//   parameter integer BUFFER_ADDR_WIDTH  = $clog2(BUFFER_DEPTH);
//   parameter integer SYSTOLIC_SIZE      = 16;
//   parameter integer DATA_WIDTH         = 8;
//   parameter integer ACCUM_WIDTH        = 20;
//   parameter integer MATRIX_SIZE        = 16;
//   parameter integer NUM_ELEMENTS       = MATRIX_SIZE * MATRIX_SIZE;

//   //-------------------------------------------------------------------------
//   // Clock & Reset
//   //-------------------------------------------------------------------------
//   reg ap_clk;
//   reg ap_rst_n;

//   initial begin
//     ap_clk = 0;
//     forever #5 ap_clk = ~ap_clk;  // 100 MHz
//   end

//   //-------------------------------------------------------------------------
//   // DUT I/O
//   //-------------------------------------------------------------------------
//   // AXI-Lite control port
//   reg                 s_axi_control_awvalid;
//   wire                s_axi_control_awready;
//   reg   [5:0]         s_axi_control_awaddr;
//   reg                 s_axi_control_wvalid;
//   wire                s_axi_control_wready;
//   reg   [31:0]        s_axi_control_wdata;
//   reg   [3:0]         s_axi_control_wstrb;
//   wire                s_axi_control_bvalid;
//   reg                 s_axi_control_bready;
//   wire  [1:0]         s_axi_control_bresp;
//   reg   [0:0]         s_axi_control_awid;
//   wire  [0:0]         s_axi_control_bid;
//   reg                 s_axi_control_arvalid;
//   wire                s_axi_control_arready;
//   reg   [5:0]         s_axi_control_araddr;
//   wire                s_axi_control_rvalid;
//   reg                 s_axi_control_rready;
//   wire  [31:0]        s_axi_control_rdata;
//   wire  [1:0]         s_axi_control_rresp;
//   reg   [0:0]         s_axi_control_arid;
//   wire  [0:0]         s_axi_control_rid;

//   // AXI-4 master port
//   wire [ID_WIDTH-1:0] m_axi_gmem_awid;
//   reg  [ID_WIDTH-1:0] m_axi_gmem_bid;
//   wire                m_axi_gmem_awvalid;
//   reg                 m_axi_gmem_awready;
//   wire [63:0]         m_axi_gmem_awaddr;
//   wire  [7:0]         m_axi_gmem_awlen;
//   wire  [2:0]         m_axi_gmem_awsize;
//   wire  [1:0]         m_axi_gmem_awburst;
//   wire                m_axi_gmem_wvalid;
//   reg                 m_axi_gmem_wready;
//   wire [127:0]        m_axi_gmem_wdata;
//   wire  [15:0]        m_axi_gmem_wstrb;
//   wire                m_axi_gmem_wlast;
//   reg                 m_axi_gmem_bvalid;
//   wire                m_axi_gmem_bready;
//   reg   [1:0]         m_axi_gmem_bresp;
//   wire [ID_WIDTH-1:0] m_axi_gmem_arid;
//   reg  [ID_WIDTH-1:0] m_axi_gmem_rid;
//   wire                m_axi_gmem_arvalid;
//   reg                 m_axi_gmem_arready;
//   wire [63:0]         m_axi_gmem_araddr;
//   wire  [7:0]         m_axi_gmem_arlen;
//   wire  [2:0]         m_axi_gmem_arsize;
//   wire  [1:0]         m_axi_gmem_arburst;
//   reg                 m_axi_gmem_rvalid;
//   wire                m_axi_gmem_rready;
//   reg  [127:0]        m_axi_gmem_rdata;
//   reg                 m_axi_gmem_rlast;
//   reg   [1:0]         m_axi_gmem_rresp;

//   //-------------------------------------------------------------------------
//   // Local "memory" models
//   //-------------------------------------------------------------------------
//   reg signed [7:0]    mat_a     [0:NUM_ELEMENTS-1];   // identity
//   reg signed [7:0]    mat_b     [0:NUM_ELEMENTS-1];   // ramp
//   reg signed [31:0]   mat_c_exp [0:NUM_ELEMENTS-1];   // expected
//   reg signed [31:0]   mat_c_act [0:NUM_ELEMENTS-1];   // captured

//   //-------------------------------------------------------------------------
//   // Addresses & Offsets
//   //-------------------------------------------------------------------------
//   localparam [63:0] ADDR_A      = 64'h00021000;
//   localparam [63:0] ADDR_B      = 64'h00022000;
//   localparam [63:0] ADDR_C      = 64'h00023000;

//   localparam [5:0]  ADDR_CTRL   = 6'h00;
//   localparam [5:0]  ADDR_STATUS = 6'h04;
//   localparam [5:0]  A_LSB       = 6'h10;
//   localparam [5:0]  A_MSB       = 6'h14;
//   localparam [5:0]  B_LSB       = 6'h18;
//   localparam [5:0]  B_MSB       = 6'h1C;
//   localparam [5:0]  C_LSB       = 6'h20;
//   localparam [5:0]  C_MSB       = 6'h24;

//   //-------------------------------------------------------------------------
//   // TB state
//   //-------------------------------------------------------------------------
//   reg  [7:0] read_count, write_count;
//   reg        rd_a, rd_b;
//   integer    errors;

//   //-------------------------------------------------------------------------
//   // DUT instantiation
//   //-------------------------------------------------------------------------
//   gemma_accelerator #(
//     .ID_WIDTH           (ID_WIDTH),
//     .BUFFER_DEPTH       (BUFFER_DEPTH),
//     .BUFFER_ADDR_WIDTH  (BUFFER_ADDR_WIDTH),
//     .SYSTOLIC_SIZE      (SYSTOLIC_SIZE),
//     .DATA_WIDTH         (DATA_WIDTH),
//     .ACCUM_WIDTH        (ACCUM_WIDTH)
//   ) dut (
//     .ap_clk               (ap_clk),
//     .ap_rst_n             (ap_rst_n),
//     // AXI-Lite
//     .s_axi_control_awvalid(s_axi_control_awvalid),
//     .s_axi_control_awready(s_axi_control_awready),
//     .s_axi_control_awaddr (s_axi_control_awaddr),
//     .s_axi_control_wvalid (s_axi_control_wvalid),
//     .s_axi_control_wready (s_axi_control_wready),
//     .s_axi_control_wdata  (s_axi_control_wdata),
//     .s_axi_control_wstrb  (s_axi_control_wstrb),
//     .s_axi_control_bvalid (s_axi_control_bvalid),
//     .s_axi_control_bready (s_axi_control_bready),
//     .s_axi_control_bresp  (s_axi_control_bresp),
//     .s_axi_control_awid   (s_axi_control_awid),
//     .s_axi_control_bid    (s_axi_control_bid),
//     .s_axi_control_arvalid(s_axi_control_arvalid),
//     .s_axi_control_arready(s_axi_control_arready),
//     .s_axi_control_araddr (s_axi_control_araddr),
//     .s_axi_control_rvalid (s_axi_control_rvalid),
//     .s_axi_control_rready (s_axi_control_rready),
//     .s_axi_control_rdata  (s_axi_control_rdata),
//     .s_axi_control_rresp  (s_axi_control_rresp),
//     .s_axi_control_arid   (s_axi_control_arid),
//     .s_axi_control_rid    (s_axi_control_rid),
//     // AXI-4 master
//     .m_axi_gmem_awid      (m_axi_gmem_awid),
//     .m_axi_gmem_bid       (m_axi_gmem_bid),
//     .m_axi_gmem_awvalid   (m_axi_gmem_awvalid),
//     .m_axi_gmem_awready   (m_axi_gmem_awready),
//     .m_axi_gmem_awaddr    (m_axi_gmem_awaddr),
//     .m_axi_gmem_awlen     (m_axi_gmem_awlen),
//     .m_axi_gmem_awsize    (m_axi_gmem_awsize),
//     .m_axi_gmem_awburst   (m_axi_gmem_awburst),
//     .m_axi_gmem_wvalid    (m_axi_gmem_wvalid),
//     .m_axi_gmem_wready    (m_axi_gmem_wready),
//     .m_axi_gmem_wdata     (m_axi_gmem_wdata),
//     .m_axi_gmem_wstrb     (m_axi_gmem_wstrb),
//     .m_axi_gmem_wlast     (m_axi_gmem_wlast),
//     .m_axi_gmem_bvalid    (m_axi_gmem_bvalid),
//     .m_axi_gmem_bready    (m_axi_gmem_bready),
//     .m_axi_gmem_bresp     (m_axi_gmem_bresp),
//     .m_axi_gmem_arid      (m_axi_gmem_arid),
//     .m_axi_gmem_rid       (m_axi_gmem_rid),
//     .m_axi_gmem_arvalid   (m_axi_gmem_arvalid),
//     .m_axi_gmem_arready   (m_axi_gmem_arready),
//     .m_axi_gmem_araddr    (m_axi_gmem_araddr),
//     .m_axi_gmem_arlen     (m_axi_gmem_arlen),
//     .m_axi_gmem_arsize    (m_axi_gmem_arsize),
//     .m_axi_gmem_arburst   (m_axi_gmem_arburst),
//     .m_axi_gmem_rvalid    (m_axi_gmem_rvalid),
//     .m_axi_gmem_rready    (m_axi_gmem_rready),
//     .m_axi_gmem_rdata     (m_axi_gmem_rdata),
//     .m_axi_gmem_rlast     (m_axi_gmem_rlast),
//     .m_axi_gmem_rresp     (m_axi_gmem_rresp)
//   );

//   //-------------------------------------------------------------------------
//   // Initialize matrices (ramp + identity)
//   //-------------------------------------------------------------------------
//   task init_matrices;
//   integer i, r, c;
//   begin
//     for (i = 0; i < NUM_ELEMENTS; i = i + 1)
//       mat_b[i] = i[7:0];
//     for (r = 0; r < MATRIX_SIZE; r = r + 1)
//       for (c = 0; c < MATRIX_SIZE; c = c + 1)
//         mat_a[r*MATRIX_SIZE + c] = (r==c) ? 8'sd1 : 8'sd0;
//     for (i = 0; i < NUM_ELEMENTS; i = i + 1)
//       mat_c_exp[i] = {{16{mat_b[i][7]}}, mat_b[i]};
//   end
//   endtask

//   //-------------------------------------------------------------------------
//   // AXI-Lite write (blocking assigns)
//   //-------------------------------------------------------------------------
//   task axi_lite_wr(input [5:0] addr, input [31:0] data);
//   begin
//     @(posedge ap_clk);
//       s_axi_control_awvalid = 1;
//       s_axi_control_awaddr  = addr;
//       s_axi_control_awid    = 0;
//       s_axi_control_wvalid  = 1;
//       s_axi_control_wdata   = data;
//       s_axi_control_wstrb   = 4'hF;
//       s_axi_control_bready  = 1;
//     wait (s_axi_control_awready && s_axi_control_wready);
//     @(posedge ap_clk);
//       s_axi_control_awvalid = 0;
//       s_axi_control_wvalid  = 0;
//     wait (s_axi_control_bvalid);
//     @(posedge ap_clk);
//       s_axi_control_bready  = 0;
//   end
//   endtask

//   //-------------------------------------------------------------------------
//   // AXI-Lite read (blocking assigns)
//   //-------------------------------------------------------------------------
//   task axi_lite_rd(input [5:0] addr, output [31:0] data);
//   begin
//     @(posedge ap_clk);
//       s_axi_control_arvalid = 1;
//       s_axi_control_araddr  = addr;
//       s_axi_control_arid    = 0;
//       s_axi_control_rready  = 1;
//     wait (s_axi_control_arready);
//     @(posedge ap_clk);
//       s_axi_control_arvalid = 0;
//     wait (s_axi_control_rvalid);
//       data = s_axi_control_rdata;
//     @(posedge ap_clk);
//       s_axi_control_rready  = 0;
//   end
//   endtask

// //  //-------------------------------------------------------------------------
// //  // AXI read-response model (fixed to emit beat 0)
// //  //-------------------------------------------------------------------------
// //  always @(posedge ap_clk) begin
// //    if (!ap_rst_n) begin
// //      m_axi_gmem_arready <= 0;
// //      m_axi_gmem_rvalid  <= 0;
// //      m_axi_gmem_rdata   <= 0;
// //      m_axi_gmem_rlast   <= 0;
// //      m_axi_gmem_rresp   <= 2'b00;
// //      m_axi_gmem_rid     <= 0;
// //      read_count         <= 0;
// //      rd_a               <= 0;
// //      rd_b               <= 0;
// //    end else begin
// //      // AR handshake + start R burst
// //      if (m_axi_gmem_arvalid && !m_axi_gmem_arready) begin
// //        m_axi_gmem_arready <= 1;
// //        m_axi_gmem_rid     <= m_axi_gmem_arid;
// //        read_count         <= 0;
// //        rd_a               <= (m_axi_gmem_araddr == ADDR_A);
// //        rd_b               <= (m_axi_gmem_araddr == ADDR_B);
// //        m_axi_gmem_rvalid  <= 1;
// //      end else begin
// //        m_axi_gmem_arready <= 0;
// //      end

// //      // Drive RDATA & RLAST whenever RVALID
// //      if (m_axi_gmem_rvalid) begin
// //        integer base, i;
// //        base = read_count * 16;
// //        for (i = 0; i < 16; i = i + 1) begin
// //          m_axi_gmem_rdata[i*8 +: 8] <= rd_a ? mat_a[base+i] : mat_b[base+i];
// //        end
// //        m_axi_gmem_rlast <= (read_count == 8'd15);

// //        // Advance or end burst
// //        if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
// //          if (m_axi_gmem_rlast) begin
// //            m_axi_gmem_rvalid <= 0;
// //            m_axi_gmem_rlast  <= 0;
// //          end else begin
// //            read_count <= read_count + 1;
// //          end
// //        end
// //      end
// //    end
// //  end
  
//   //-------------------------------------------------------------------------
// // AXI read-response model (FIXED)
// //-------------------------------------------------------------------------
//  integer next_base, j;
//  integer base, i;
 
// always @(posedge ap_clk) begin
//   if (!ap_rst_n) begin
//     m_axi_gmem_arready <= 0;
//     m_axi_gmem_rvalid  <= 0;
//     m_axi_gmem_rdata   <= 0;
//     m_axi_gmem_rlast   <= 0;
//     m_axi_gmem_rresp   <= 2'b00;
//     m_axi_gmem_rid     <= 0;
//     read_count         <= 0;
//     rd_a               <= 0;
//     rd_b               <= 0;
//   end else begin
//     // AR handshake + start R burst
//     if (m_axi_gmem_arvalid && !m_axi_gmem_arready) begin
//       m_axi_gmem_arready <= 1;
//       m_axi_gmem_rid     <= m_axi_gmem_arid;
//       read_count         <= 0;
//       rd_a               <= (m_axi_gmem_araddr == ADDR_A);
//       rd_b               <= (m_axi_gmem_araddr == ADDR_B);
//       m_axi_gmem_rvalid  <= 1;
      
//       // Load first beat data immediately

//       base = 0;
//       for (i = 0; i < 16; i = i + 1) begin
//         m_axi_gmem_rdata[i*8 +: 8] <= (m_axi_gmem_araddr == ADDR_A) ? mat_a[i] : mat_b[i];
//       end
//       m_axi_gmem_rlast <= (8'd0 == 8'd15);  // Check if single beat transfer
//     end else begin
//       m_axi_gmem_arready <= 0;
//     end

//     // Handle data transfer and burst advancement
//     if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
//       if (m_axi_gmem_rlast) begin
//         // End of burst
//         m_axi_gmem_rvalid <= 0;
//         m_axi_gmem_rlast  <= 0;
//       end else begin
//         // Advance to next beat
//         read_count <= read_count + 1;
        
//         // Prepare next beat data

//         next_base = (read_count + 1) * 16;
//         for (j = 0; j < 16; j = j + 1) begin
//           m_axi_gmem_rdata[j*8 +: 8] <= rd_a ? mat_a[next_base + j] : mat_b[next_base + j];
//         end
//         m_axi_gmem_rlast <= ((read_count + 1) == 8'd15);  // Check if next beat is last
//       end
//     end
//   end
// end

//   //-------------------------------------------------------------------------
//   // AXI write-response model (unchanged)
//   //-------------------------------------------------------------------------
//   always @(posedge ap_clk) begin
//     if (!ap_rst_n) begin
//       m_axi_gmem_awready <= 0;
//       m_axi_gmem_wready  <= 0;
//       m_axi_gmem_bvalid  <= 0;
//       m_axi_gmem_bresp   <= 2'b00;
//       m_axi_gmem_bid     <= 0;
//       write_count        <= 0;
//     end else begin
//       if (m_axi_gmem_awvalid && !m_axi_gmem_awready) begin
//         m_axi_gmem_awready <= 1;
//         m_axi_gmem_bid     <= m_axi_gmem_awid;
//         write_count        <= 0;
//       end else begin
//         m_axi_gmem_awready <= 0;
//       end

//       if (m_axi_gmem_awready)
//         m_axi_gmem_wready <= 1;

//       if (m_axi_gmem_wvalid && m_axi_gmem_wready) begin
//         integer base, i;
//         base = write_count * 8;
//         for (i = 0; i < 8; i = i + 1) begin
//           mat_c_act[base + i] = {{16{m_axi_gmem_wdata[i*16+15]}},
//                                  m_axi_gmem_wdata[i*16 +:16]};
//         end
//         if (m_axi_gmem_wlast) begin
//           m_axi_gmem_wready <= 0;
//           m_axi_gmem_bvalid <= 1;
//         end else begin
//           write_count <= write_count + 1;
//         end
//       end

//       if (m_axi_gmem_bvalid && m_axi_gmem_bready)
//         m_axi_gmem_bvalid <= 0;
//     end
//   end

//   //-------------------------------------------------------------------------
//   // Wait for DONE bit-0
//   //-------------------------------------------------------------------------
//   task wait_done;
//     reg [31:0] st;
//     integer    to;
//     begin
//       to = 0;
//       do begin
//         #100;
//         axi_lite_rd(ADDR_STATUS, st);
//         to = to + 1;
//         if (to > 10000) begin
//           $display("ERROR: done timeout");
//           $finish;
//         end
//       end while ((st & 32'h1) != 32'h1);
//       $display(">>> Accelerator DONE @ %0t", $time);
//     end
//   endtask

//   //-------------------------------------------------------------------------
//   // Verify results
//   //-------------------------------------------------------------------------
//   task verify;
//     integer i, r, c;
//     begin
//       errors = 0;
//       for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin
//         if (mat_c_act[i] !== mat_c_exp[i]) begin
//           r = i / MATRIX_SIZE;
//           c = i % MATRIX_SIZE;
//           $display("ERR [%0d,%0d]: exp=%0d got=%0d",
//                    r, c, mat_c_exp[i], mat_c_act[i]);
//           errors = errors + 1;
//         end
//       end
//       if (errors == 0)
//         $display("+++ PASS: all outputs match");
//       else
//         $display("*** FAIL: %0d mismatches", errors);
//     end
//   endtask

//   //-------------------------------------------------------------------------
//   // Main Test
//   //-------------------------------------------------------------------------
//   initial begin
//     ap_rst_n             = 0;
//     s_axi_control_awvalid = 0;
//     s_axi_control_wvalid  = 0;
//     s_axi_control_bready  = 0;
//     s_axi_control_arvalid = 0;
//     s_axi_control_rready  = 0;
//     #100;
//     ap_rst_n = 1;

//     init_matrices();

//     // Program A, B, C bases
//     axi_lite_wr(A_LSB, ADDR_A[31:0]);
//     axi_lite_wr(A_MSB, ADDR_A[63:32]);
//     axi_lite_wr(B_LSB, ADDR_B[31:0]);
//     axi_lite_wr(B_MSB, ADDR_B[63:32]);
//     axi_lite_wr(C_LSB, ADDR_C[31:0]);
//     axi_lite_wr(C_MSB, ADDR_C[63:32]);

//     // Kick off
//     axi_lite_wr(ADDR_CTRL, 32'h1);

//     wait_done();
//     verify();

//     if (errors == 0)
//       $display("=== TEST PASSED ===");
//     else
//       $display("=== TEST FAILED: %0d errors ===", errors);

//     $finish;
//   end

//   //-------------------------------------------------------------------------
//   // Timeout watchdog
//   //-------------------------------------------------------------------------
//   initial begin
//     #50_000_000;
//     $display("ERROR: simulation timed out");
//     $finish;
//   end

// endmodule

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
  parameter integer ACCUM_WIDTH        = 32;
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
//  task init_matrices;
//  integer i, r, c;
//  begin
//    for (i = 0; i < NUM_ELEMENTS; i = i + 1)
//      mat_a[i] = i[7:0];
//    for (r = 0; r < MATRIX_SIZE; r = r + 1)
//      for (c = 0; c < MATRIX_SIZE; c = c + 1)
//        mat_b[r*MATRIX_SIZE + c] = (r==c) ? 8'sd1 : 8'sd0;
//    for (i = 0; i < NUM_ELEMENTS; i = i + 1)
//      mat_c_exp[i] = {{16{mat_b[i][7]}}, mat_b[i]};
//  end
//  endtask

  task init_matrices;
    integer r, c, k;
    integer sum;
    begin
      //------ Fill Matrix A ------//
      // Row 0
      mat_a[ 0] = 8'd43;  mat_a[ 1] = 8'd97;  mat_a[ 2] = 8'd12;  mat_a[ 3] = 8'd188;
      mat_a[ 4] = 8'd144; mat_a[ 5] = 8'd73;  mat_a[ 6] = 8'd25;  mat_a[ 7] = 8'd86;
      mat_a[ 8] = 8'd37;  mat_a[ 9] = 8'd245; mat_a[10] = 8'd59;  mat_a[11] = 8'd18;
      mat_a[12] = 8'd198; mat_a[13] = 8'd62;  mat_a[14] = 8'd211; mat_a[15] = 8'd156;
      // Row 1
      mat_a[16] = 8'd6;   mat_a[17] = 8'd129; mat_a[18] = 8'd94;  mat_a[19] = 8'd250;
      mat_a[20] = 8'd223; mat_a[21] = 8'd88;  mat_a[22] = 8'd39;  mat_a[23] = 8'd45;
      mat_a[24] = 8'd67;  mat_a[25] = 8'd74;  mat_a[26] = 8'd85;  mat_a[27] = 8'd199;
      mat_a[28] = 8'd204; mat_a[29] = 8'd56;  mat_a[30] = 8'd30;  mat_a[31] = 8'd221;
      // Row 2
      mat_a[32] = 8'd76;  mat_a[33] = 8'd52;  mat_a[34] = 8'd81;  mat_a[35] = 8'd66;
      mat_a[36] = 8'd49;  mat_a[37] = 8'd152; mat_a[38] = 8'd118; mat_a[39] = 8'd19;
      mat_a[40] = 8'd237; mat_a[41] = 8'd119; mat_a[42] = 8'd40;  mat_a[43] = 8'd93;
      mat_a[44] = 8'd77;  mat_a[45] = 8'd128; mat_a[46] = 8'd53;  mat_a[47] = 8'd102;
      // Row 3
      mat_a[48] = 8'd180; mat_a[49] = 8'd23;  mat_a[50] = 8'd96;  mat_a[51] = 8'd71;
      mat_a[52] = 8'd27;  mat_a[53] = 8'd78;  mat_a[54] = 8'd14;  mat_a[55] = 8'd90;
      mat_a[56] = 8'd68;  mat_a[57] = 8'd46;  mat_a[58] = 8'd254; mat_a[59] = 8'd33;
      mat_a[60] = 8'd112; mat_a[61] = 8'd41;  mat_a[62] = 8'd64;  mat_a[63] = 8'd84;
      // Row 4
      mat_a[64] = 8'd149; mat_a[65] = 8'd99;  mat_a[66] = 8'd186; mat_a[67] = 8'd16;
      mat_a[68] = 8'd212; mat_a[69] = 8'd54;  mat_a[70] = 8'd241; mat_a[71] = 8'd21;
      mat_a[72] = 8'd201; mat_a[73] = 8'd34;  mat_a[74] = 8'd125; mat_a[75] = 8'd192;
      mat_a[76] = 8'd35;  mat_a[77] = 8'd250; mat_a[78] = 8'd137; mat_a[79] = 8'd31;
      // Row 5
      mat_a[80] = 8'd247; mat_a[81] = 8'd183; mat_a[82] = 8'd60;  mat_a[83] = 8'd164;
      mat_a[84] = 8'd50;  mat_a[85] = 8'd111; mat_a[86] = 8'd133; mat_a[87] = 8'd79;
      mat_a[88] = 8'd29;  mat_a[89] = 8'd26;  mat_a[90] = 8'd139; mat_a[91] = 8'd42;
      mat_a[92] = 8'd219; mat_a[93] = 8'd36;  mat_a[94] = 8'd13;  mat_a[95] = 8'd95;
      // Row 6
      mat_a[96] = 8'd174; mat_a[97] = 8'd115; mat_a[98] = 8'd205; mat_a[99] = 8'd108;
      mat_a[100]= 8'd103; mat_a[101]= 8'd32;  mat_a[102]= 8'd191; mat_a[103]= 8'd189;
      mat_a[104]= 8'd130; mat_a[105]= 8'd246; mat_a[106]= 8'd17;  mat_a[107]= 8'd28;
      mat_a[108]= 8'd184; mat_a[109]= 8'd63;  mat_a[110]= 8'd159; mat_a[111]= 8'd83;
      // Row 7
      mat_a[112]= 8'd9;   mat_a[113]= 8'd24;  mat_a[114]= 8'd158; mat_a[115]= 8'd80;
      mat_a[116]= 8'd20;  mat_a[117]= 8'd157; mat_a[118]= 8'd22;  mat_a[119]= 8'd82;
      mat_a[120]= 8'd226; mat_a[121]= 8'd61;  mat_a[122]= 8'd11;  mat_a[123]= 8'd48;
      mat_a[124]= 8'd243; mat_a[125]= 8'd147; mat_a[126]= 8'd72;  mat_a[127]= 8'd145;
      // Row 8
      mat_a[128]= 8'd92;  mat_a[129]= 8'd206; mat_a[130]= 8'd208; mat_a[131]= 8'd51;
      mat_a[132]= 8'd44;  mat_a[133]= 8'd179; mat_a[134]= 8'd98;  mat_a[135]= 8'd195;
      mat_a[136]= 8'd47;  mat_a[137]= 8'd218; mat_a[138]= 8'd217; mat_a[139]= 8'd91;
      mat_a[140]= 8'd197; mat_a[141]= 8'd143; mat_a[142]= 8'd153; mat_a[143]= 8'd65;
      // Row 9
      mat_a[144]= 8'd150; mat_a[145]= 8'd134; mat_a[146]= 8'd215; mat_a[147]= 8'd240;
      mat_a[148]= 8'd70;  mat_a[149]= 8'd244; mat_a[150]= 8'd57;  mat_a[151]= 8'd15;
      mat_a[152]= 8'd75;  mat_a[153]= 8'd136; mat_a[154]= 8'd110; mat_a[155]= 8'd210;
      mat_a[156]= 8'd178; mat_a[157]= 8'd38;  mat_a[158]= 8'd154; mat_a[159]= 8'd209;
      // Row 10
      mat_a[160]= 8'd187; mat_a[161]= 8'd200; mat_a[162]= 8'd176; mat_a[163]= 8'd214;
      mat_a[164]= 8'd140; mat_a[165]= 8'd10;  mat_a[166]= 8'd55;  mat_a[167]= 8'd116;
      mat_a[168]= 8'd141; mat_a[169]= 8'd87;  mat_a[170]= 8'd225; mat_a[171]= 8'd138;
      mat_a[172]= 8'd89;  mat_a[173]= 8'd42;  mat_a[174]= 8'd167; mat_a[175]= 8'd109;
      // Row 11
      mat_a[176]= 8'd163; mat_a[177]= 8'd97;  mat_a[178]= 8'd248; mat_a[179]= 8'd169;
      mat_a[180]= 8'd12;  mat_a[181]= 8'd235; mat_a[182]= 8'd43;  mat_a[183]= 8'd249;
      mat_a[184]= 8'd58;  mat_a[185]= 8'd190; mat_a[186]= 8'd132; mat_a[187]= 8'd156;
      mat_a[188]= 8'd94;  mat_a[189]= 8'd255; mat_a[190]= 8'd67;  mat_a[191]= 8'd113;
      // Row 12
      mat_a[192]= 8'd4;   mat_a[193]= 8'd68;  mat_a[194]= 8'd220; mat_a[195]= 8'd170;
      mat_a[196]= 8'd122; mat_a[197]= 8'd15;  mat_a[198]= 8'd126; mat_a[199]= 8'd85;
      mat_a[200]= 8'd104; mat_a[201]= 8'd175; mat_a[202]= 8'd76;  mat_a[203]= 8'd206;
      mat_a[204]= 8'd232; mat_a[205]= 8'd181; mat_a[206]= 8'd228; mat_a[207]= 8'd216;
      // Row 13
      mat_a[208]= 8'd3;   mat_a[209]= 8'd27;  mat_a[210]= 8'd233; mat_a[211]= 8'd146;
      mat_a[212]= 8'd114; mat_a[213]= 8'd42;  mat_a[214]= 8'd14;  mat_a[215]= 8'd142;
      mat_a[216]= 8'd93;  mat_a[217]= 8'd101; mat_a[218]= 8'd231; mat_a[219]= 8'd95;
      mat_a[220]= 8'd117; mat_a[221]= 8'd64;  mat_a[222]= 8'd82;  mat_a[223]= 8'd123;
      // Row 14
      mat_a[224]= 8'd53;  mat_a[225]= 8'd227; mat_a[226]= 8'd171; mat_a[227]= 8'd18;
      mat_a[228]= 8'd31;  mat_a[229]= 8'd46;  mat_a[230]= 8'd97;  mat_a[231]= 8'd199;
      mat_a[232]= 8'd33;  mat_a[233]= 8'd40;  mat_a[234]= 8'd60;  mat_a[235]= 8'd52;
      mat_a[236]= 8'd73;  mat_a[237]= 8'd11;  mat_a[238]= 8'd88;  mat_a[239]= 8'd45;
      // Row 15
      mat_a[240]= 8'd69;  mat_a[241]= 8'd77;  mat_a[242]= 8'd182; mat_a[243]= 8'd74;
      mat_a[244]= 8'd83;  mat_a[245]= 8'd26;  mat_a[246]= 8'd105; mat_a[247]= 8'd185;
      mat_a[248]= 8'd35;  mat_a[249]= 8'd222; mat_a[250]= 8'd41;  mat_a[251]= 8'd127;
      mat_a[252]= 8'd30;  mat_a[253]= 8'd131; mat_a[254]= 8'd66;  mat_a[255]= 8'd202;

      //------ Fill Matrix B ------//
      // Row 0
      mat_b[ 0] = 8'd5;   mat_b[ 1] = 8'd60;  mat_b[ 2] = 8'd98;  mat_b[ 3] = 8'd212;
      mat_b[ 4] = 8'd21;  mat_b[ 5] = 8'd96;  mat_b[ 6] = 8'd174; mat_b[ 7] = 8'd37;
      mat_b[ 8] = 8'd59;  mat_b[ 9] = 8'd71;  mat_b[10] = 8'd183; mat_b[11] = 8'd41;
      mat_b[12] = 8'd77;  mat_b[13] = 8'd12;  mat_b[14] = 8'd101; mat_b[15] = 8'd200;
      // Row 1
      mat_b[16] = 8'd184; mat_b[17] = 8'd132; mat_b[18] = 8'd24;  mat_b[19] = 8'd86;
      mat_b[20] = 8'd47;  mat_b[21] = 8'd141; mat_b[22] = 8'd31;  mat_b[23] = 8'd39;
      mat_b[24] = 8'd42;  mat_b[25] = 8'd65;  mat_b[26] = 8'd84;  mat_b[27] = 8'd236;
      mat_b[28] = 8'd53;  mat_b[29] = 8'd221; mat_b[30] = 8'd249; mat_b[31] = 8'd50;
      // Row 2
      mat_b[32] = 8'd91;  mat_b[33] = 8'd57;  mat_b[34] = 8'd16;  mat_b[35] = 8'd122;
      mat_b[36] = 8'd138; mat_b[37] = 8'd32;  mat_b[38] = 8'd19;  mat_b[39] = 8'd62;
      mat_b[40] = 8'd69;  mat_b[41] = 8'd14;  mat_b[42] = 8'd117; mat_b[43] = 8'd201;
      mat_b[44] = 8'd55;  mat_b[45] = 8'd208; mat_b[46] = 8'd218; mat_b[47] = 8'd145;
      // Row 3
      mat_b[48] = 8'd180; mat_b[49] = 8'd10;  mat_b[50] = 8'd85;  mat_b[51] = 8'd176;
      mat_b[52] = 8'd13;  mat_b[53] = 8'd26;  mat_b[54] = 8'd128; mat_b[55] = 8'd188;
      mat_b[56] = 8'd157; mat_b[57] = 8'd159; mat_b[58] = 8'd247; mat_b[59] = 8'd23;
      mat_b[60] = 8'd144; mat_b[61] = 8'd199; mat_b[62] = 8'd34;  mat_b[63] = 8'd94;
      // Row 4
      mat_b[64] = 8'd29;  mat_b[65] = 8'd89;  mat_b[66] = 8'd44;  mat_b[67] = 8'd116;
      mat_b[68] = 8'd68;  mat_b[69] = 8'd99;  mat_b[70] = 8'd120; mat_b[71] = 8'd64;
      mat_b[72] = 8'd38;  mat_b[73] = 8'd226; mat_b[74] = 8'd190; mat_b[75] = 8'd40;
      mat_b[76] = 8'd51;  mat_b[77] = 8'd76;  mat_b[78] = 8'd54;  mat_b[79] = 8'd130;
      // Row 5
      mat_b[80] = 8'd146; mat_b[81] = 8'd205; mat_b[82] = 8'd61;  mat_b[83] = 8'd30;
      mat_b[84] = 8'd233; mat_b[85] = 8'd106; mat_b[86] = 8'd153; mat_b[87] = 8'd168;
      mat_b[88] = 8'd227; mat_b[89] = 8'd72;  mat_b[90] = 8'd250; mat_b[91] = 8'd18;
      mat_b[92] = 8'd255; mat_b[93] = 8'd35;  mat_b[94] = 8'd28;  mat_b[95] = 8'd90;
      // Row 6
      mat_b[96] = 8'd20;  mat_b[97] = 8'd56;  mat_b[98] = 8'd93;  mat_b[99] = 8'd11;
      mat_b[100]= 8'd78;  mat_b[101]= 8'd126; mat_b[102]= 8'd83;  mat_b[103]= 8'd49;
      mat_b[104]= 8'd43;  mat_b[105]= 8'd36;  mat_b[106]= 8'd27;  mat_b[107]= 8'd97;
      mat_b[108]= 8'd22;  mat_b[109]= 8'd48;  mat_b[110]= 8'd108; mat_b[111]= 8'd46;
      // Row 7
      mat_b[112]= 8'd240; mat_b[113]= 8'd15;  mat_b[114]= 8'd92;  mat_b[115]= 8'd25;
      mat_b[116]= 8'd88;  mat_b[117]= 8'd229; mat_b[118]= 8'd75;  mat_b[119]= 8'd111;
      mat_b[120]= 8'd161; mat_b[121]= 8'd238; mat_b[122]= 8'd181; mat_b[123]= 8'd80;
      mat_b[124]= 8'd66;  mat_b[125]= 8'd58;  mat_b[126]= 8'd112; mat_b[127]= 8'd247;
      // Row 8
      mat_b[128]= 8'd7;   mat_b[129]= 8'd129; mat_b[130]= 8'd186; mat_b[131]= 8'd81;
      mat_b[132]= 8'd216; mat_b[133]= 8'd52;  mat_b[134]= 8'd219; mat_b[135]= 8'd17;
      mat_b[136]= 8'd198; mat_b[137]= 8'd206; mat_b[138]= 8'd87;  mat_b[139]= 8'd70;
      mat_b[140]= 8'd207; mat_b[141]= 8'd232; mat_b[142]= 8'd151; mat_b[143]= 8'd136;
      // Row 9
      mat_b[144]= 8'd162; mat_b[145]= 8'd187; mat_b[146]= 8'd79;  mat_b[147]= 8'd142;
      mat_b[148]= 8'd74;  mat_b[149]= 8'd169; mat_b[150]= 8'd244; mat_b[151]= 8'd95;
      mat_b[152]= 8'd150; mat_b[153]= 8'd248; mat_b[154]= 8'd67;  mat_b[155]= 8'd63;
      mat_b[156]= 8'd155; mat_b[157]= 8'd33;  mat_b[158]= 8'd45;  mat_b[159]= 8'd124;
      // Row 10
      mat_b[160]= 8'd135; mat_b[161]= 8'd73;  mat_b[162]= 8'd36;  mat_b[163]= 8'd82;
      mat_b[164]= 8'd14;  mat_b[165]= 8'd121; mat_b[166]= 8'd29;  mat_b[167]= 8'd182;
      mat_b[168]= 8'd12;  mat_b[169]= 8'd55;  mat_b[170]= 8'd230; mat_b[171]= 8'd214;
      mat_b[172]= 8'd15;  mat_b[173]= 8'd103; mat_b[174]= 8'd148; mat_b[175]= 8'd172;
      // Row 11
      mat_b[176]= 8'd211; mat_b[177]= 8'd178; mat_b[178]= 8'd125; mat_b[179]= 8'd67;
      mat_b[180]= 8'd110; mat_b[181]= 8'd224; mat_b[182]= 8'd97;  mat_b[183]= 8'd131;
      mat_b[184]= 8'd146; mat_b[185]= 8'd105; mat_b[186]= 8'd20;  mat_b[187]= 8'd193;
      mat_b[188]= 8'd156; mat_b[189]= 8'd37;  mat_b[190]= 8'd47;  mat_b[191]= 8'd118;
      // Row 12
      mat_b[192]= 8'd4;   mat_b[193]= 8'd202; mat_b[194]= 8'd19;  mat_b[195]= 8'd100;
      mat_b[196]= 8'd185; mat_b[197]= 8'd160; mat_b[198]= 8'd109; mat_b[199]= 8'd139;
      mat_b[200]= 8'd192; mat_b[201]= 8'd42;  mat_b[202]= 8'd53;  mat_b[203]= 8'd71;
      mat_b[204]= 8'd41;  mat_b[205]= 8'd137; mat_b[206]= 8'd39;  mat_b[207]= 8'd140;
      // Row 13
      mat_b[208]= 8'd9;   mat_b[209]= 8'd86;  mat_b[210]= 8'd70;  mat_b[211]= 8'd50;
      mat_b[212]= 8'd25;  mat_b[213]= 8'd44;  mat_b[214]= 8'd18;  mat_b[215]= 8'd213;
      mat_b[216]= 8'd56;  mat_b[217]= 8'd48;  mat_b[218]= 8'd16;  mat_b[219]= 8'd249;
      mat_b[220]= 8'd60;  mat_b[221]= 8'd34;  mat_b[222]= 8'd84;  mat_b[223]= 8'd141;
      // Row 14
      mat_b[224]= 8'd196; mat_b[225]= 8'd154; mat_b[226]= 8'd228; mat_b[227]= 8'd31;
      mat_b[228]= 8'd243; mat_b[229]= 8'd173; mat_b[230]= 8'd104; mat_b[231]= 8'd180;
      mat_b[232]= 8'd57;  mat_b[233]= 8'd26;  mat_b[234]= 8'd38;  mat_b[235]= 8'd40;
      mat_b[236]= 8'd194; mat_b[237]= 8'd52;  mat_b[238]= 8'd72;  mat_b[239]= 8'd13;
      // Row 15
      mat_b[240]= 8'd152; mat_b[241]= 8'd189; mat_b[242]= 8'd203; mat_b[243]= 8'd170;
      mat_b[244]= 8'd242; mat_b[245]= 8'd33;  mat_b[246]= 8'd65;  mat_b[247]= 8'd135;
      mat_b[248]= 8'd165; mat_b[249]= 8'd10;  mat_b[250]= 8'd32;  mat_b[251]= 8'd119;
      mat_b[252]= 8'd123; mat_b[253]= 8'd159; mat_b[254]= 8'd81;  mat_b[255]= 8'd209;

//      //------ Compute golden C = A×B ------//
//      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
//        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
//          sum = 0;
//          for (k = 0; k < MATRIX_SIZE; k = k + 1) begin
//            sum = sum + mat_a[r*MATRIX_SIZE + k] * mat_b[k*MATRIX_SIZE + c];
//          end
//          mat_c_exp[r*MATRIX_SIZE + c] = sum;
//        end
//      end
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


  //-------------------------------------------------------------------------
// AXI read-response model
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
