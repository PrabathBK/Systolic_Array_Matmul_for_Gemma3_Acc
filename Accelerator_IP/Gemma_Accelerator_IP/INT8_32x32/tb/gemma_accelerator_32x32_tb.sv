`timescale 1ns / 1ps

module gemma_accelerator_32x32_tb;

  //-------------------------------------------------------------------------
  // Parameters
  //-------------------------------------------------------------------------
  parameter integer ID_WIDTH           = 12;
  parameter integer BUFFER_DEPTH       = 80;
  parameter integer BUFFER_ADDR_WIDTH  = $clog2(BUFFER_DEPTH);
  parameter integer SYSTOLIC_SIZE      = 32;
  parameter integer DATA_WIDTH         = 8;
  parameter integer ACCUM_WIDTH        = 32;
  parameter integer MATRIX_SIZE        = 32;
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
  reg   [7:0]         s_axi_control_awaddr;
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
  reg   [7:0]         s_axi_control_araddr;
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

  localparam [7:0]  ADDR_CTRL   = 8'h00;
  localparam [7:0]  ADDR_STATUS = 8'h04;
  localparam [7:0]  A_LSB       = 8'h10;
  localparam [7:0]  A_MSB       = 8'h14;
  localparam [7:0]  B_LSB       = 8'h18;
  localparam [7:0]  B_MSB       = 8'h1C;
  localparam [7:0]  C_LSB       = 8'h20;
  localparam [7:0]  C_MSB       = 8'h24;

  //-------------------------------------------------------------------------
  // TB state
  //-------------------------------------------------------------------------
  reg  [7:0] read_count, write_count;
  reg        rd_a, rd_b;
  integer    errors;

  //-------------------------------------------------------------------------
  // DUT instantiation
  //-------------------------------------------------------------------------
  gemma_accelerator_32x32 #(
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

//  //-------------------------------------------------------------------------
//  // Initialize matrices (ramp + identity)
//  //-------------------------------------------------------------------------
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
// Initialize matrices (ramp + identity)  <-- keep comment
  task init_matrices;
    integer r, c, k;
    integer sum;
    begin
      // Fill Matrix A with simple incremental pattern for easy verification
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          mat_a[r*MATRIX_SIZE + c] = (r * MATRIX_SIZE + c) & 8'hFF;  // Values 1 to 127
        end
      end
      
      // Fill Matrix B with pure identity matrix for easier verification
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          if (r == c)
            mat_b[r*MATRIX_SIZE + c] = 8'sd1;
          else
            mat_b[r*MATRIX_SIZE + c] = 8'sd0;
        end
      end

      // Compute golden C = A×B
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          sum = 0;
          for (k = 0; k < MATRIX_SIZE; k = k + 1) begin
            sum = sum + mat_a[r*MATRIX_SIZE + k] * mat_b[k*MATRIX_SIZE + c];
          end
          mat_c_exp[r*MATRIX_SIZE + c] = sum;
        end
      end
    end
  endtask



//  task init_matrices;
//    integer r, c, k;
//    integer sum;
//    begin
//       // Fill Matrix A - using correct signed 8-bit notation
//      // Row 0
//      mat_a[0] = -14;  mat_a[1] = -50;  mat_a[2] = -12;  mat_a[3] = 88;
//      mat_a[4] = -17;  mat_a[5] = -111;  mat_a[6] = -79;  mat_a[7] = 119;
//      mat_a[8] = 123;  mat_a[9] = -39;  mat_a[10] = 82;  mat_a[11] = 86;
//      mat_a[12] = -43;  mat_a[13] = -59;  mat_a[14] = 72;  mat_a[15] = 126;
//      // Row 1
//      mat_a[16] = 68;  mat_a[17] = 7;  mat_a[18] = -47;  mat_a[19] = 37;
//      mat_a[20] = -122;  mat_a[21] = 53;  mat_a[22] = -42;  mat_a[23] = -45;
//      mat_a[24] = 52;  mat_a[25] = 117;  mat_a[26] = -25;  mat_a[27] = 102;
//      mat_a[28] = 114;  mat_a[29] = -108;  mat_a[30] = -91;  mat_a[31] = -17;
//      // Row 2
//      mat_a[32] = -109;  mat_a[33] = 21;  mat_a[34] = 65;  mat_a[35] = 69;
//      mat_a[36] = 6;  mat_a[37] = 36;  mat_a[38] = -70;  mat_a[39] = 74;
//      mat_a[40] = 109;  mat_a[41] = 33;  mat_a[42] = -115;  mat_a[43] = 75;
//      mat_a[44] = 2;  mat_a[45] = -73;  mat_a[46] = -97;  mat_a[47] = 78;
//      // Row 3
//      mat_a[48] = 126;  mat_a[49] = -27;  mat_a[50] = 35;  mat_a[51] = 82;
//      mat_a[52] = -17;  mat_a[53] = -112;  mat_a[54] = 99;  mat_a[55] = -12;
//      mat_a[56] = 20;  mat_a[57] = -17;  mat_a[58] = -80;  mat_a[59] = 2;
//      mat_a[60] = -71;  mat_a[61] = -106;  mat_a[62] = 38;  mat_a[63] = -2;
//      // Row 4
//      mat_a[64] = 91;  mat_a[65] = -70;  mat_a[66] = -67;  mat_a[67] = -72;
//      mat_a[68] = -45;  mat_a[69] = -84;  mat_a[70] = 125;  mat_a[71] = 86;
//      mat_a[72] = -40;  mat_a[73] = 61;  mat_a[74] = -9;  mat_a[75] = -35;
//      mat_a[76] = -115;  mat_a[77] = 28;  mat_a[78] = 21;  mat_a[79] = -93;
//      // Row 5
//      mat_a[80] = 60;  mat_a[81] = -24;  mat_a[82] = -68;  mat_a[83] = 0;
//      mat_a[84] = -2;  mat_a[85] = 29;  mat_a[86] = 106;  mat_a[87] = 83;
//      mat_a[88] = 101;  mat_a[89] = -110;  mat_a[90] = -76;  mat_a[91] = -73;
//      mat_a[92] = -90;  mat_a[93] = -21;  mat_a[94] = -66;  mat_a[95] = -58;
//      // Row 6
//      mat_a[96] = -78;  mat_a[97] = 114;  mat_a[98] = 122;  mat_a[99] = -37;
//      mat_a[100] = 83;  mat_a[101] = 91;  mat_a[102] = -83;  mat_a[103] = 62;
//      mat_a[104] = 47;  mat_a[105] = -61;  mat_a[106] = 73;  mat_a[107] = -71;
//      mat_a[108] = -22;  mat_a[109] = 122;  mat_a[110] = -30;  mat_a[111] = 82;
//      // Row 7
//      mat_a[112] = 57;  mat_a[113] = -91;  mat_a[114] = 80;  mat_a[115] = 45;
//      mat_a[116] = 107;  mat_a[117] = 104;  mat_a[118] = 76;  mat_a[119] = -65;
//      mat_a[120] = 12;  mat_a[121] = 60;  mat_a[122] = -97;  mat_a[123] = -91;
//      mat_a[124] = -103;  mat_a[125] = -24;  mat_a[126] = 27;  mat_a[127] = 62;
//      // Row 8
//      mat_a[128] = -63;  mat_a[129] = 62;  mat_a[130] = -50;  mat_a[131] = -112;
//      mat_a[132] = -108;  mat_a[133] = 21;  mat_a[134] = 10;  mat_a[135] = 35;
//      mat_a[136] = 21;  mat_a[137] = 119;  mat_a[138] = 53;  mat_a[139] = 41;
//      mat_a[140] = -90;  mat_a[141] = -76;  mat_a[142] = -101;  mat_a[143] = 23;
//      // Row 9
//      mat_a[144] = 69;  mat_a[145] = -65;  mat_a[146] = -101;  mat_a[147] = 112;
//      mat_a[148] = 103;  mat_a[149] = -20;  mat_a[150] = -19;  mat_a[151] = -70;
//      mat_a[152] = -32;  mat_a[153] = -62;  mat_a[154] = 7;  mat_a[155] = -117;
//      mat_a[156] = -67;  mat_a[157] = -52;  mat_a[158] = -7;  mat_a[159] = -11;
//      // Row 10
//      mat_a[160] = -82;  mat_a[161] = 94;  mat_a[162] = -87;  mat_a[163] = -73;
//      mat_a[164] = 36;  mat_a[165] = -12;  mat_a[166] = 37;  mat_a[167] = 56;
//      mat_a[168] = -119;  mat_a[169] = 41;  mat_a[170] = -76;  mat_a[171] = 122;
//      mat_a[172] = -83;  mat_a[173] = -65;  mat_a[174] = 57;  mat_a[175] = -29;
//      // Row 11
//      mat_a[176] = -88;  mat_a[177] = 37;  mat_a[178] = -128;  mat_a[179] = -110;
//      mat_a[180] = -27;  mat_a[181] = 70;  mat_a[182] = -123;  mat_a[183] = -110;
//      mat_a[184] = -126;  mat_a[185] = -121;  mat_a[186] = -114;  mat_a[187] = -11;
//      mat_a[188] = 103;  mat_a[189] = 16;  mat_a[190] = -77;  mat_a[191] = 15;
//      // Row 12
//      mat_a[192] = -22;  mat_a[193] = 14;  mat_a[194] = -52;  mat_a[195] = 121;
//      mat_a[196] = 77;  mat_a[197] = 125;  mat_a[198] = 104;  mat_a[199] = 109;
//      mat_a[200] = -44;  mat_a[201] = 14;  mat_a[202] = -46;  mat_a[203] = 56;
//      mat_a[204] = -72;  mat_a[205] = 37;  mat_a[206] = -60;  mat_a[207] = 86;
//      // Row 13
//      mat_a[208] = -11;  mat_a[209] = 23;  mat_a[210] = 65;  mat_a[211] = -85;
//      mat_a[212] = -80;  mat_a[213] = 54;  mat_a[214] = 16;  mat_a[215] = -95;
//      mat_a[216] = -19;  mat_a[217] = 26;  mat_a[218] = 86;  mat_a[219] = 124;
//      mat_a[220] = -90;  mat_a[221] = 73;  mat_a[222] = -113;  mat_a[223] = 6;
//      // Row 14
//      mat_a[224] = -77;  mat_a[225] = 85;  mat_a[226] = -42;  mat_a[227] = -124;
//      mat_a[228] = -84;  mat_a[229] = -93;  mat_a[230] = 84;  mat_a[231] = -28;
//      mat_a[232] = 59;  mat_a[233] = 94;  mat_a[234] = -41;  mat_a[235] = -74;
//      mat_a[236] = -75;  mat_a[237] = -21;  mat_a[238] = -45;  mat_a[239] = -26;
//      // Row 15
//      mat_a[240] = -52;  mat_a[241] = -40;  mat_a[242] = -71;  mat_a[243] = 2;
//      mat_a[244] = -109;  mat_a[245] = -49;  mat_a[246] = -35;  mat_a[247] = -5;
//      mat_a[248] = -5;  mat_a[249] = 41;  mat_a[250] = -46;  mat_a[251] = -30;
//      mat_a[252] = -124;  mat_a[253] = 109;  mat_a[254] = 109;  mat_a[255] = -103;

//      // Fill Matrix B
//      // Row 0
//      mat_b[0] = 102;  mat_b[1] = 51;  mat_b[2] = -83;  mat_b[3] = -109;
//      mat_b[4] = -26;  mat_b[5] = -110;  mat_b[6] = 98;  mat_b[7] = -114;
//      mat_b[8] = 51;  mat_b[9] = -59;  mat_b[10] = -88;  mat_b[11] = -22;
//      mat_b[12] = 79;  mat_b[13] = -117;  mat_b[14] = 65;  mat_b[15] = 0;
//      // Row 1
//      mat_b[16] = 1;  mat_b[17] = -42;  mat_b[18] = -88;  mat_b[19] = 51;
//      mat_b[20] = 25;  mat_b[21] = -3;  mat_b[22] = -42;  mat_b[23] = -29;
//      mat_b[24] = 111;  mat_b[25] = -82;  mat_b[26] = -106;  mat_b[27] = 113;
//      mat_b[28] = -23;  mat_b[29] = -7;  mat_b[30] = -84;  mat_b[31] = -87;
//      // Row 2
//      mat_b[32] = 96;  mat_b[33] = -98;  mat_b[34] = 88;  mat_b[35] = 119;
//      mat_b[36] = -4;  mat_b[37] = -87;  mat_b[38] = -115;  mat_b[39] = -50;
//      mat_b[40] = 122;  mat_b[41] = 8;  mat_b[42] = 32;  mat_b[43] = 5;
//      mat_b[44] = -112;  mat_b[45] = -9;  mat_b[46] = 46;  mat_b[47] = 95;
//      // Row 3
//      mat_b[48] = -8;  mat_b[49] = 74;  mat_b[50] = -100;  mat_b[51] = -73;
//      mat_b[52] = -24;  mat_b[53] = 72;  mat_b[54] = 60;  mat_b[55] = -31;
//      mat_b[56] = 84;  mat_b[57] = -76;  mat_b[58] = -92;  mat_b[59] = -60;
//      mat_b[60] = 66;  mat_b[61] = 4;  mat_b[62] = 18;  mat_b[63] = -48;
//      // Row 4
//      mat_b[64] = -95;  mat_b[65] = -48;  mat_b[66] = 53;  mat_b[67] = 34;
//      mat_b[68] = -20;  mat_b[69] = -118;  mat_b[70] = -95;  mat_b[71] = -31;
//      mat_b[72] = 0;  mat_b[73] = -24;  mat_b[74] = 78;  mat_b[75] = -116;
//      mat_b[76] = -27;  mat_b[77] = 29;  mat_b[78] = 103;  mat_b[79] = 23;
//      // Row 5
//      mat_b[80] = 79;  mat_b[81] = 69;  mat_b[82] = 108;  mat_b[83] = 48;
//      mat_b[84] = -119;  mat_b[85] = -64;  mat_b[86] = -52;  mat_b[87] = -52;
//      mat_b[88] = -44;  mat_b[89] = -117;  mat_b[90] = -68;  mat_b[91] = -60;
//      mat_b[92] = -46;  mat_b[93] = -56;  mat_b[94] = 31;  mat_b[95] = -55;
//      // Row 6
//      mat_b[96] = 124;  mat_b[97] = -61;  mat_b[98] = 22;  mat_b[99] = -30;
//      mat_b[100] = 79;  mat_b[101] = 5;  mat_b[102] = 54;  mat_b[103] = 28;
//      mat_b[104] = -65;  mat_b[105] = 18;  mat_b[106] = -100;  mat_b[107] = -35;
//      mat_b[108] = -47;  mat_b[109] = 85;  mat_b[110] = 121;  mat_b[111] = 102;
//      // Row 7
//      mat_b[112] = 6;  mat_b[113] = 45;  mat_b[114] = 1;  mat_b[115] = -3;
//      mat_b[116] = 21;  mat_b[117] = -87;  mat_b[118] = 39;  mat_b[119] = 49;
//      mat_b[120] = -120;  mat_b[121] = -76;  mat_b[122] = -72;  mat_b[123] = -108;
//      mat_b[124] = -49;  mat_b[125] = -118;  mat_b[126] = -31;  mat_b[127] = 27;
//      // Row 8
//      mat_b[128] = 38;  mat_b[129] = -30;  mat_b[130] = -24;  mat_b[131] = -113;
//      mat_b[132] = 123;  mat_b[133] = -100;  mat_b[134] = -104;  mat_b[135] = 5;
//      mat_b[136] = -88;  mat_b[137] = 108;  mat_b[138] = -91;  mat_b[139] = 103;
//      mat_b[140] = 42;  mat_b[141] = -85;  mat_b[142] = -91;  mat_b[143] = -3;
//      // Row 9
//      mat_b[144] = -27;  mat_b[145] = -58;  mat_b[146] = 118;  mat_b[147] = -42;
//      mat_b[148] = 65;  mat_b[149] = 102;  mat_b[150] = -71;  mat_b[151] = 108;
//      mat_b[152] = -86;  mat_b[153] = 73;  mat_b[154] = 51;  mat_b[155] = 104;
//      mat_b[156] = -89;  mat_b[157] = 123;  mat_b[158] = 28;  mat_b[159] = -5;
//      // Row 10
//      mat_b[160] = 59;  mat_b[161] = -4;  mat_b[162] = 85;  mat_b[163] = -100;
//      mat_b[164] = 58;  mat_b[165] = 90;  mat_b[166] = -63;  mat_b[167] = -108;
//      mat_b[168] = 42;  mat_b[169] = 121;  mat_b[170] = 20;  mat_b[171] = -49;
//      mat_b[172] = -104;  mat_b[173] = -95;  mat_b[174] = 57;  mat_b[175] = 66;
//      // Row 11
//      mat_b[176] = 19;  mat_b[177] = -119;  mat_b[178] = 118;  mat_b[179] = -112;
//      mat_b[180] = -39;  mat_b[181] = 25;  mat_b[182] = -54;  mat_b[183] = -3;
//      mat_b[184] = 127;  mat_b[185] = -62;  mat_b[186] = -76;  mat_b[187] = 54;
//      mat_b[188] = 78;  mat_b[189] = -75;  mat_b[190] = -71;  mat_b[191] = 122;
//      // Row 12
//      mat_b[192] = 41;  mat_b[193] = 98;  mat_b[194] = -57;  mat_b[195] = -71;
//      mat_b[196] = 63;  mat_b[197] = 61;  mat_b[198] = -76;  mat_b[199] = -115;
//      mat_b[200] = 5;  mat_b[201] = 116;  mat_b[202] = 24;  mat_b[203] = 119;
//      mat_b[204] = -61;  mat_b[205] = 70;  mat_b[206] = -66;  mat_b[207] = -128;
//      // Row 13
//      mat_b[208] = 91;  mat_b[209] = -41;  mat_b[210] = -24;  mat_b[211] = -15;
//      mat_b[212] = -84;  mat_b[213] = 121;  mat_b[214] = -88;  mat_b[215] = 4;
//      mat_b[216] = 113;  mat_b[217] = -8;  mat_b[218] = -29;  mat_b[219] = -114;
//      mat_b[220] = -87;  mat_b[221] = 24;  mat_b[222] = 24;  mat_b[223] = -90;
//      // Row 14
//      mat_b[224] = 47;  mat_b[225] = -74;  mat_b[226] = -62;  mat_b[227] = -76;
//      mat_b[228] = 107;  mat_b[229] = 58;  mat_b[230] = -39;  mat_b[231] = -81;
//      mat_b[232] = -15;  mat_b[233] = 123;  mat_b[234] = -8;  mat_b[235] = 88;
//      mat_b[236] = -88;  mat_b[237] = 120;  mat_b[238] = -120;  mat_b[239] = 46;
//      // Row 15
//      mat_b[240] = 32;  mat_b[241] = -86;  mat_b[242] = -9;  mat_b[243] = -60;
//      mat_b[244] = 48;  mat_b[245] = 98;  mat_b[246] = -95;  mat_b[247] = 6;
//      mat_b[248] = -66;  mat_b[249] = 16;  mat_b[250] = -42;  mat_b[251] = -76;
//      mat_b[252] = 116;  mat_b[253] = 26;  mat_b[254] = -53;  mat_b[255] = -56;

// //      //------ Compute golden C = A×B ------//
// //      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
// //        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
// //          sum = 0;
// //          for (k = 0; k < MATRIX_SIZE; k = k + 1) begin
// //            sum = sum + mat_a[r*MATRIX_SIZE + k] * mat_b[k*MATRIX_SIZE + c];
// //          end
// //          mat_c_exp[r*MATRIX_SIZE + c] = sum;
// //        end
// //      end
//    end
//  endtask

  //-------------------------------------------------------------------------
  // AXI-Lite write (blocking assigns)
  //-------------------------------------------------------------------------
  task axi_lite_wr(input [7:0] addr, input [31:0] data);
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
  task axi_lite_rd(input [7:0] addr, output [31:0] data);
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
     m_axi_gmem_rlast <= (8'd0 == 8'd63);  // Check if single beat transfer
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
       m_axi_gmem_rlast <= ((read_count + 1) == 8'd63);  // Check if next beat is last (64 beats total)
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
        if (to > 20000) begin
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
    #200_000_000;
    $display("ERROR: simulation timed out");
    $finish;
  end

endmodule
