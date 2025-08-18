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
  // Local "memory" models - Memory sizing verification
  //-------------------------------------------------------------------------
  // Memory Requirements for 32x32 matrix with byte addressing:
  // - Matrix A: 2 tile_rows × 2 inner_k × 256 bytes = 1024 bytes max
  // - Matrix B: 2 inner_k × 2 tile_cols × 256 bytes = 1024 bytes max
  // - Matrix C: 32×32×4 bytes = 4096 bytes
  // - Base addresses: A=0x1000(4KB), B=0x2000(8KB), C=0x3000(12KB)
  // - Maximum address: 0x3000 + 4096 = 16384 bytes (16KB)
  // - Memory size 64KB is more than sufficient
  parameter MEMORY_SIZE = 65536;  // 64KB memory space - verified sufficient
  reg [7:0]           memory       [0:MEMORY_SIZE-1]; // Memory array [0:65535]
  reg signed [7:0]    mat_a        [0:NUM_ELEMENTS-1];   // Source matrix A
  reg signed [7:0]    mat_b        [0:NUM_ELEMENTS-1];   // Source matrix B
  reg signed [31:0]   mat_c_exp    [0:NUM_ELEMENTS-1];   // expected
  reg signed [31:0]   mat_c_act    [0:NUM_ELEMENTS-1];   // captured

  //-------------------------------------------------------------------------
  // Addresses & Offsets
  //-------------------------------------------------------------------------
  localparam [63:0] ADDR_A      = 64'h00001000;  // 4KB - fits in 64KB memory
  localparam [63:0] ADDR_B      = 64'h00002000;  // 8KB - fits in 64KB memory
  localparam [63:0] ADDR_C      = 64'h00003000;  // 12KB - fits in 64KB memory

  localparam [7:0]  ADDR_CTRL   = 8'h00;
  localparam [7:0]  ADDR_STATUS = 8'h00;
  localparam [7:0]  A_LSB       = 8'h10;
  localparam [7:0]  A_MSB       = 8'h14;
  localparam [7:0]  B_LSB       = 8'h1C;
  localparam [7:0]  B_MSB       = 8'h20;
  localparam [7:0]  C_LSB       = 8'h28;
  localparam [7:0]  C_MSB       = 8'h2C;

  // Matrix chaining control registers
  localparam [7:0]  ACT_BASE_LSB = 8'h60;
  localparam [7:0]  ACT_BASE_MSB = 8'h64;
  localparam [7:0]  WGT_BASE_LSB = 8'h68;
  localparam [7:0]  WGT_BASE_MSB = 8'h6C;
  localparam [7:0]  OUT_BASE_LSB = 8'h70;
  localparam [7:0]  OUT_BASE_MSB = 8'h74;
  localparam [7:0]  MATRIX_DIMS  = 8'h78;
  localparam [7:0]  CHAIN_CTRL   = 8'h80;

  //-------------------------------------------------------------------------
  // TB state
  //-------------------------------------------------------------------------
  reg  [7:0] read_count, write_count;
  reg  [7:0] captured_arlen;
  reg        rd_a, rd_b;
  reg [63:0] latched_araddr;  // Store original address for multi-beat reads
  reg [63:0] captured_awaddr; // Store AXI write address during AW handshake
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
      //------ Fill Matrix A (32x32 pattern) ------//
      // Initialize with simple pattern for easier debugging
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          mat_a[r*MATRIX_SIZE + c] = (r + c + 1) % 256;
        end
      end
      // Debug Matrix A initialization
      $display("DEBUG_MATRIX_A: First row A[0][0:7] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
               mat_a[0], mat_a[1], mat_a[2], mat_a[3], mat_a[4], mat_a[5], mat_a[6], mat_a[7]);
      $display("DEBUG_MATRIX_A: A[0][0] = (0+0+1)%%256 = %0d (expected: 1)", mat_a[0]);
      $display("DEBUG_MATRIX_A: A[0][15] = (0+15+1)%%256 = %0d (expected: 16)", mat_a[15]);
      $display("DEBUG_MATRIX_A: A[0][16] = (0+16+1)%%256 = %0d (expected: 17)", mat_a[16]);
      $display("DEBUG_MATRIX_A: A[1][0] = (1+0+1)%%256 = %0d (expected: 2)", mat_a[32]);

      //------ Fill Matrix B (32x32 pattern) ------//
      // Initialize with simple pattern for easier debugging
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          mat_b[r*MATRIX_SIZE + c] = (r * 2 + c + 1) % 256;
        end
      end
      // Debug Matrix B initialization
      $display("DEBUG_MATRIX_B: First row B[0][0:7] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
               mat_b[0], mat_b[1], mat_b[2], mat_b[3], mat_b[4], mat_b[5], mat_b[6], mat_b[7]);
      $display("DEBUG_MATRIX_B: B[0][0] = (0*2+0+1)%%256 = %0d (expected: 1)", mat_b[0]);
      $display("DEBUG_MATRIX_B: B[0][1] = (0*2+1+1)%%256 = %0d (expected: 2)", mat_b[1]);
      $display("DEBUG_MATRIX_B: B[1][0] = (1*2+0+1)%%256 = %0d (expected: 3)", mat_b[32]);
      $display("DEBUG_MATRIX_B: B[1][1] = (1*2+1+1)%%256 = %0d (expected: 4)", mat_b[33]);


      //------ Compute golden C = A×B ------//
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          sum = 0;
          for (k = 0; k < MATRIX_SIZE; k = k + 1) begin
            sum = sum + $signed(mat_a[r*MATRIX_SIZE + k]) * $signed(mat_b[k*MATRIX_SIZE + c]);
          end
          mat_c_exp[r*MATRIX_SIZE + c] = sum;
          // Debug first few golden reference calculations
          if (r < 2 && c < 4) begin
            $display("DEBUG_GOLDEN: C[%0d][%0d] = %0d", r, c, mat_c_exp[r*MATRIX_SIZE + c]);
          end
        end
      end

      // Manual verification of C[0][0] calculation
      begin
        integer manual_sum, debug_k;
        manual_sum = 0;
        $display("DEBUG_GOLDEN: Manual calculation of C[0][0]:");
        for (debug_k = 0; debug_k < 8; debug_k = debug_k + 1) begin
          integer a_val, b_val, product;
          a_val = $signed(mat_a[0*MATRIX_SIZE + debug_k]);
          b_val = $signed(mat_b[debug_k*MATRIX_SIZE + 0]);
          product = a_val * b_val;
          manual_sum = manual_sum + product;
          $display("  A[0][%0d] * B[%0d][0] = %0d * %0d = %0d, running_sum = %0d",
                   debug_k, debug_k, a_val, b_val, product, manual_sum);
        end
        $display("DEBUG_GOLDEN: Partial sum for first 8 terms = %0d", manual_sum);
      end

      $display("Matrix initialization complete for 32x32 with chaining");

      // Debug matrix initialization - show key values
      $display("DEBUG_MATRIX_A: First row [0:3] = %0d, %0d, %0d, %0d", mat_a[0], mat_a[1], mat_a[2], mat_a[3]);
      $display("DEBUG_MATRIX_A: Second row [32:35] = %0d, %0d, %0d, %0d", mat_a[32], mat_a[33], mat_a[34], mat_a[35]);
      $display("DEBUG_MATRIX_B: First row [0:3] = %0d, %0d, %0d, %0d", mat_b[0], mat_b[1], mat_b[2], mat_b[3]);
      $display("DEBUG_MATRIX_B: First col [0,32,64,96] = %0d, %0d, %0d, %0d", mat_b[0], mat_b[32], mat_b[64], mat_b[96]);

      // Simple debug: Expected C[0][0] calculation
      $display("DEBUG_EXPECTED: Golden reference C[0][0] = %0d", mat_c_exp[0]);
      $display("DEBUG_EXPECTED: Expected pattern: (1*1 + 2*2 + ... + 32*32) = 11440");
      $display("DEBUG_EXPECTED: For 32x32 chaining: 2 tiles x 2 inner_k = 4 total operations");

      $display("Sample A values: %0d, %0d, %0d, %0d", mat_a[0], mat_a[1], mat_a[2], mat_a[3]);
      $display("Sample B values: %0d, %0d, %0d, %0d", mat_b[0], mat_b[1], mat_b[2], mat_b[3]);
      $display("Sample expected C: %0d, %0d, %0d, %0d", mat_c_exp[0], mat_c_exp[1], mat_c_exp[2], mat_c_exp[3]);

      // Additional debug for matrix patterns
      $display("DEBUG_PATTERN: Matrix A pattern verification:");
      $display("  A[0][0:3] = %0d,%0d,%0d,%0d (should be 1,2,3,4)", mat_a[0], mat_a[1], mat_a[2], mat_a[3]);
      $display("  A[1][0:3] = %0d,%0d,%0d,%0d (should be 2,3,4,5)", mat_a[32], mat_a[33], mat_a[34], mat_a[35]);
      $display("DEBUG_PATTERN: Matrix B pattern verification:");
      $display("  B[0][0:3] = %0d,%0d,%0d,%0d (should be 1,2,3,4)", mat_b[0], mat_b[1], mat_b[2], mat_b[3]);
      $display("  B[1][0:3] = %0d,%0d,%0d,%0d (should be 3,4,5,6)", mat_b[32], mat_b[33], mat_b[34], mat_b[35]);
    end
  endtask

  //-------------------------------------------------------------------------
  // Memory Verification Task
  //-------------------------------------------------------------------------
  task verify_memory_data;
    integer addr_offset, expected_value;
    begin
      $display("=== Verifying Memory Data at Key Addresses ===");

      // Verify A matrix tile (0,0) inner_k=0 data
      $display("DEBUG_MEMORY_VERIFY: A matrix tile(0,0) inner_k=0 at 0x%h:", ADDR_A);
      for (integer i = 0; i < 16; i = i + 1) begin
        addr_offset = ADDR_A + i;
        expected_value = i + 1; // Should be 1,2,3,4,...,16
        if (memory[addr_offset] != expected_value) begin
          $display("  ERROR: memory[0x%h] = %d, expected %d", addr_offset, memory[addr_offset], expected_value);
        end else if (i < 4) begin
          $display("  OK: memory[0x%h] = %d", addr_offset, memory[addr_offset]);
        end
      end

      // Verify A matrix tile (0,0) inner_k=1 data
      $display("DEBUG_MEMORY_VERIFY: A matrix tile(0,0) inner_k=1 at 0x%h:", ADDR_A + 16);
      for (integer i = 0; i < 16; i = i + 1) begin
        addr_offset = ADDR_A + 16 + i;
        expected_value = 16 + i + 1; // Should be 17,18,19,20,...,32
        if (memory[addr_offset] != expected_value) begin
          $display("  ERROR: memory[0x%h] = %d, expected %d", addr_offset, memory[addr_offset], expected_value);
        end else if (i < 4) begin
          $display("  OK: memory[0x%h] = %d", addr_offset, memory[addr_offset]);
        end
      end

      // Verify B matrix tile (0,0) inner_k=0 data
      $display("DEBUG_MEMORY_VERIFY: B matrix tile(0,0) inner_k=0 at 0x%h:", ADDR_B);
      for (integer i = 0; i < 16; i = i + 1) begin
        addr_offset = ADDR_B + i; // Consecutive bytes in tiled format
        expected_value = (i % 16) + 1; // Should be 1,2,3,4,...,16 for first row
        if (memory[addr_offset] != expected_value) begin
          $display("  ERROR: memory[0x%h] = %d, expected %d", addr_offset, memory[addr_offset], expected_value);
        end else if (i < 4) begin
          $display("  OK: memory[0x%h] = %d", addr_offset, memory[addr_offset]);
        end
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Wait for accelerator completion
  //-------------------------------------------------------------------------
  task load_matrices_to_memory;
    integer r, c, mem_addr, tile_row, tile_col, inner_k, accelerator_addr;
    begin
      $display("Loading matrices into memory using BYTE ADDRESSING...");

      // Initialize entire memory to zero first
      for (mem_addr = 0; mem_addr < MEMORY_SIZE; mem_addr = mem_addr + 1) begin
        memory[mem_addr] = 8'h00;
      end

      // NEW BYTE ADDRESSING SCHEME:
      // Matrix A: base + (tile_row * 16 * total_cols) + (inner_k * 16)
      // Matrix B: base + (inner_k * 16 * total_cols) + (tile_col * 16)

      // Load Matrix A using byte addressing
      for (tile_row = 0; tile_row < 2; tile_row = tile_row + 1) begin
        for (inner_k = 0; inner_k < 2; inner_k = inner_k + 1) begin
          // Calculate base address for this tile_row and inner_k (BYTE ADDRESSING)
          // FIXED: Use non-overlapping addressing - each inner_k gets 256 bytes
          accelerator_addr = ADDR_A[15:0] + (tile_row * 16 * 32) + (inner_k * 16 * 16);

          // Place 16x16 tile elements row by row
          for (r = 0; r < 16; r = r + 1) begin
            for (c = 0; c < 16; c = c + 1) begin
              mem_addr = accelerator_addr + (r * 16) + c;
              if (mem_addr < MEMORY_SIZE) begin
                // Calculate source matrix indices
                integer src_row, src_col;
                src_row = tile_row * 16 + r;
                src_col = inner_k * 16 + c;
                if (src_row < MATRIX_SIZE && src_col < MATRIX_SIZE) begin
                  memory[mem_addr] = mat_a[src_row * MATRIX_SIZE + src_col];
                end
              end
            end
          end
        end
      end

      // Load Matrix B using byte addressing - COLUMN-WISE LAYOUT FOR SYSTOLIC ARRAY  
      for (inner_k = 0; inner_k < 2; inner_k = inner_k + 1) begin
        for (tile_col = 0; tile_col < 2; tile_col = tile_col + 1) begin
          // Calculate base address to avoid overlap between tiles
          // Use 256-byte spacing between tiles (tile_col * 256) to avoid AXI read overlap
          accelerator_addr = ADDR_B[15:0] + (inner_k * 16 * 32) + (tile_col * 256);

          // Store 16x16 tile in column-major order as expected by accelerator
          for (c = 0; c < 16; c = c + 1) begin         // For each column in the tile
            for (r = 0; r < 16; r = r + 1) begin       // For each row in that column
              mem_addr = accelerator_addr + (c * 16) + r;  // Column-major addressing
              if (mem_addr < MEMORY_SIZE) begin
                // Calculate correct source matrix indices for B[k][j] access pattern
                integer src_row, src_col;
                src_row = inner_k * 16 + r; // Row index in original matrix B
                src_col = tile_col * 16 + c; // Column index in original matrix B
                if (src_row < MATRIX_SIZE && src_col < MATRIX_SIZE) begin
                  memory[mem_addr] = mat_b[src_row * MATRIX_SIZE + src_col];
                end
              end
            end
          end
        end
      end

      $display("Memory loading complete with BYTE ADDRESSING");
      $display("Matrix A tile(0,0), inner_k=0 at 0x%h: %0d,%0d,%0d,%0d",
               ADDR_A[15:0], memory[ADDR_A[15:0]], memory[ADDR_A[15:0]+1],
               memory[ADDR_A[15:0]+2], memory[ADDR_A[15:0]+3]);
      $display("Matrix A tile(0,0), inner_k=1 at 0x%h: %0d,%0d,%0d,%0d",
               ADDR_A[15:0]+16, memory[ADDR_A[15:0]+16], memory[ADDR_A[15:0]+17],
               memory[ADDR_A[15:0]+18], memory[ADDR_A[15:0]+19]);

      // Verify memory layout for byte addressing
      $display("Verification: Matrix A[0][0-3] = %0d,%0d,%0d,%0d (should be 1,2,3,4)",
               memory[ADDR_A[15:0]], memory[ADDR_A[15:0]+1], memory[ADDR_A[15:0]+2], memory[ADDR_A[15:0]+3]);
      $display("Verification: Matrix A[0][16-19] = %0d,%0d,%0d,%0d (should be 17,18,19,20)",
               memory[ADDR_A[15:0]+16], memory[ADDR_A[15:0]+17], memory[ADDR_A[15:0]+18], memory[ADDR_A[15:0]+19]);
      $display("Verification: Matrix B[0:3][0] = %0d,%0d,%0d,%0d (should be 1,3,5,7 - column-wise)",
               memory[ADDR_B[15:0]], memory[ADDR_B[15:0]+1], memory[ADDR_B[15:0]+2], memory[ADDR_B[15:0]+3]);

      // Additional memory verification
      $display("DEBUG_MEMORY: Detailed memory layout verification:");
      $display("  Memory A tile(0,0) inner_k=0 at 0x%h:", ADDR_A[15:0]);
      for (integer mem_i = 0; mem_i < 16; mem_i = mem_i + 1) begin
        $display("    Row 0: [%0d:%0d] = %0d,%0d,%0d,%0d",
                 mem_i*16, mem_i*16+3,
                 memory[ADDR_A[15:0] + mem_i*16], memory[ADDR_A[15:0] + mem_i*16 + 1],
                 memory[ADDR_A[15:0] + mem_i*16 + 2], memory[ADDR_A[15:0] + mem_i*16 + 3]);
        if (mem_i >= 2) break; // Only show first few rows
      end

      // Memory bounds verification
      begin
        integer max_addr_a, max_addr_b, max_addr_c;
        max_addr_a = ADDR_A[15:0] + (1 * 16 * 32) + (1 * 16) + 255; // Worst case A
        max_addr_b = ADDR_B[15:0] + (1 * 16 * 32) + (1 * 16) + 255; // Worst case B
        max_addr_c = ADDR_C[15:0] + 4095; // 32x32x4 bytes for C

        $display("MEMORY VERIFICATION:");
        $display("  Memory size: %0d bytes (0x%h)", MEMORY_SIZE, MEMORY_SIZE);
        $display("  Max addr A: %0d (0x%h)", max_addr_a, max_addr_a);
        $display("  Max addr B: %0d (0x%h)", max_addr_b, max_addr_b);
        $display("  Max addr C: %0d (0x%h)", max_addr_c, max_addr_c);

        if (max_addr_a >= MEMORY_SIZE || max_addr_b >= MEMORY_SIZE || max_addr_c >= MEMORY_SIZE) begin
          $display("ERROR: Address exceeds memory bounds!");
          $finish;
        end else begin
          $display("PASS: All addresses within memory bounds");
        end
      end

      // Force memory update to ensure all writes are completed
      $display("Memory loading completed. Forcing memory update...");
      #1; // Small delay to ensure all assignments complete
    end
  endtask

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
    captured_arlen     <= 8'hFF;  // Initialize to invalid value to debug
    rd_a               <= 0;
    rd_b               <= 0;
    latched_araddr     <= 64'h0;
  end else begin
    // AR handshake + start R burst
    if (m_axi_gmem_arvalid && !m_axi_gmem_arready) begin
      $display("AXI_AR: addr=0x%h len=%0d type=%s time=%0t",
               m_axi_gmem_araddr, m_axi_gmem_arlen,
               (m_axi_gmem_araddr >= ADDR_A && m_axi_gmem_araddr < ADDR_B) ? "ACT" : "WGT", $time);
      m_axi_gmem_arready <= 1;
      m_axi_gmem_rid     <= m_axi_gmem_arid;
      read_count         <= 0;
      captured_arlen     <= m_axi_gmem_arlen;
      latched_araddr     <= m_axi_gmem_araddr;  // Latch address for multi-beat reads
      $display("AXI_AR_LATCH: arlen=%0d addr=0x%h time=%0t", m_axi_gmem_arlen, m_axi_gmem_araddr, $time);
      m_axi_gmem_rvalid  <= 1;

      // Load first beat data immediately - read from memory array with proper addressing
      if (m_axi_gmem_araddr >= ADDR_A && m_axi_gmem_araddr < ADDR_B) begin
        // Reading activation data - each beat reads 16 consecutive bytes
        integer byte_offset;
        integer mem_addr;
        byte_offset = (m_axi_gmem_araddr - ADDR_A);
        for (i = 0; i < 16; i = i + 1) begin
          mem_addr = ADDR_A[15:0] + byte_offset + i;
          if (mem_addr < MEMORY_SIZE) begin
            m_axi_gmem_rdata[i*8 +: 8] = memory[mem_addr];
          end else begin
            m_axi_gmem_rdata[i*8 +: 8] = 8'd0;
          end
        end
        rd_a <= 1'b1;
        rd_b <= 1'b0;
        $display("MEM_READ_ACT: addr=0x%h byte_off=%0d mem_base=0x%h time=%0t",
                 m_axi_gmem_araddr, byte_offset, ADDR_A[15:0] + byte_offset, $time);
        $display("MEM_DATA_ACT: [%0d:%0d] = [%0d,%0d,%0d,%0d] data=0x%h",
                 ADDR_A[15:0] + byte_offset, ADDR_A[15:0] + byte_offset + 3,
                 memory[ADDR_A[15:0] + byte_offset],
                 memory[ADDR_A[15:0] + byte_offset + 1],
                 memory[ADDR_A[15:0] + byte_offset + 2],
                 memory[ADDR_A[15:0] + byte_offset + 3],
                 {memory[ADDR_A[15:0] + byte_offset + 15], memory[ADDR_A[15:0] + byte_offset + 14],
                  memory[ADDR_A[15:0] + byte_offset + 13], memory[ADDR_A[15:0] + byte_offset + 12],
                  memory[ADDR_A[15:0] + byte_offset + 11], memory[ADDR_A[15:0] + byte_offset + 10],
                  memory[ADDR_A[15:0] + byte_offset + 9], memory[ADDR_A[15:0] + byte_offset + 8],
                  memory[ADDR_A[15:0] + byte_offset + 7], memory[ADDR_A[15:0] + byte_offset + 6],
                  memory[ADDR_A[15:0] + byte_offset + 5], memory[ADDR_A[15:0] + byte_offset + 4],
                  memory[ADDR_A[15:0] + byte_offset + 3], memory[ADDR_A[15:0] + byte_offset + 2],
                  memory[ADDR_A[15:0] + byte_offset + 1], memory[ADDR_A[15:0] + byte_offset]});

        // Debug: Verify first 16 bytes match expected pattern
        if (byte_offset == 0) begin
          $display("DEBUG_AXI_ACT: First beat verification (should be A[0][0:15]):");
          $display("  Expected: 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16");
          $display("  Actual:   %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                   memory[ADDR_A[15:0]], memory[ADDR_A[15:0]+1], memory[ADDR_A[15:0]+2], memory[ADDR_A[15:0]+3],
                   memory[ADDR_A[15:0]+4], memory[ADDR_A[15:0]+5], memory[ADDR_A[15:0]+6], memory[ADDR_A[15:0]+7],
                   memory[ADDR_A[15:0]+8], memory[ADDR_A[15:0]+9], memory[ADDR_A[15:0]+10], memory[ADDR_A[15:0]+11],
                   memory[ADDR_A[15:0]+12], memory[ADDR_A[15:0]+13], memory[ADDR_A[15:0]+14], memory[ADDR_A[15:0]+15]);
        end
      end else if (m_axi_gmem_araddr >= ADDR_B && m_axi_gmem_araddr < ADDR_C) begin
        // Reading weight data - each beat reads 16 consecutive bytes
        integer byte_offset;
        integer mem_addr;
        byte_offset = (m_axi_gmem_araddr - ADDR_B);
        for (i = 0; i < 16; i = i + 1) begin
          mem_addr = ADDR_B[15:0] + byte_offset + i;
          if (mem_addr < MEMORY_SIZE) begin
            m_axi_gmem_rdata[i*8 +: 8] = memory[mem_addr];
          end else begin
            m_axi_gmem_rdata[i*8 +: 8] = 8'd0;
          end
        end
        rd_a <= 1'b0;
        rd_b <= 1'b1;
        $display("MEM_READ_WGT: addr=0x%h byte_off=%0d mem_base=0x%h time=%0t",
                 m_axi_gmem_araddr, byte_offset, ADDR_B[15:0] + byte_offset, $time);
        $display("MEM_DATA_WGT: [%0d:%0d] = [%0d,%0d,%0d,%0d] data=0x%h",
                 ADDR_B[15:0] + byte_offset, ADDR_B[15:0] + byte_offset + 3,
                 memory[ADDR_B[15:0] + byte_offset],
                 memory[ADDR_B[15:0] + byte_offset + 1],
                 memory[ADDR_B[15:0] + byte_offset + 2],
                 memory[ADDR_B[15:0] + byte_offset + 3],
                 {memory[ADDR_B[15:0] + byte_offset + 15], memory[ADDR_B[15:0] + byte_offset + 14],
                  memory[ADDR_B[15:0] + byte_offset + 13], memory[ADDR_B[15:0] + byte_offset + 12],
                  memory[ADDR_B[15:0] + byte_offset + 11], memory[ADDR_B[15:0] + byte_offset + 10],
                  memory[ADDR_B[15:0] + byte_offset + 9], memory[ADDR_B[15:0] + byte_offset + 8],
                  memory[ADDR_B[15:0] + byte_offset + 7], memory[ADDR_B[15:0] + byte_offset + 6],
                  memory[ADDR_B[15:0] + byte_offset + 5], memory[ADDR_B[15:0] + byte_offset + 4],
                  memory[ADDR_B[15:0] + byte_offset + 3], memory[ADDR_B[15:0] + byte_offset + 2],
                  memory[ADDR_B[15:0] + byte_offset + 1], memory[ADDR_B[15:0] + byte_offset]});
      end else begin
        m_axi_gmem_rdata = 128'h0;
        rd_a <= 1'b0;
        rd_b <= 1'b0;
      end
      m_axi_gmem_rlast <= (m_axi_gmem_arlen == 8'd0);  // Use arlen directly for timing
      $display("AXI_R_FIRST: data=0x%h arlen=%0d rlast=%0d time=%0t", m_axi_gmem_rdata, m_axi_gmem_arlen, (m_axi_gmem_arlen == 8'd0), $time);
    end else begin
      m_axi_gmem_arready <= 0;
    end

    // Handle data transfer and burst advancement - FIXED TIMING
    if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
      $display("AXI_R_XFER: beat=%0d data=0x%h rlast=%0d time=%0t", read_count, m_axi_gmem_rdata, m_axi_gmem_rlast, $time);
      if (m_axi_gmem_rlast) begin
        // End of burst
        m_axi_gmem_rvalid <= 0;
        m_axi_gmem_rlast  <= 0;
        $display("AXI_R_DONE: burst complete beat=%0d time=%0t", read_count, $time);
      end else begin
        // Advance to next beat
        read_count <= read_count + 1;

        // Set rlast for next beat
        m_axi_gmem_rlast <= ((read_count + 1) >= captured_arlen);
        $display("AXI_R_NEXT: beat=%0d->%0d arlen=%0d rlast_next=%0d time=%0t",
                 read_count, read_count+1, captured_arlen, ((read_count + 1) >= captured_arlen), $time);
      end
    end

    // Prepare next beat data with proper timing
    if (m_axi_gmem_rvalid && m_axi_gmem_rready && !m_axi_gmem_rlast) begin
      if (rd_a) begin
        integer byte_base;
        integer mem_addr;
        integer addr_diff;
        integer beat_offset;
        addr_diff = latched_araddr - ADDR_A;
        beat_offset = (read_count + 1) * 16;
        byte_base = addr_diff + beat_offset;
        $display("AXI_R_NEXT_ACT: araddr=0x%h diff=%0d beat_off=%0d byte_base=%0d time=%0t",
                 latched_araddr, addr_diff, beat_offset, byte_base, $time);
        for (j = 0; j < 16; j = j + 1) begin
          mem_addr = ADDR_A[15:0] + byte_base + j;
          if (mem_addr < MEMORY_SIZE) begin
            m_axi_gmem_rdata[j*8 +: 8] <= memory[mem_addr];
          end else begin
            m_axi_gmem_rdata[j*8 +: 8] <= 8'd0;
          end
        end
        $display("AXI_R_NEXT_ACT_MEM: mem_base=0x%h bytes[%0d:%0d] time=%0t",
                 ADDR_A[15:0] + byte_base, byte_base, byte_base + 15, $time);
      end else if (rd_b) begin
        integer byte_base;
        integer mem_addr;
        integer addr_diff;
        integer beat_offset;
        addr_diff = latched_araddr - ADDR_B;
        beat_offset = (read_count + 1) * 16;
        byte_base = addr_diff + beat_offset;
        $display("AXI_R_NEXT_WGT: araddr=0x%h diff=%0d beat_off=%0d byte_base=%0d time=%0t",
                 latched_araddr, addr_diff, beat_offset, byte_base, $time);
        for (j = 0; j < 16; j = j + 1) begin
          mem_addr = ADDR_B[15:0] + byte_base + j;
          if (mem_addr < MEMORY_SIZE) begin
            m_axi_gmem_rdata[j*8 +: 8] <= memory[mem_addr];
          end else begin
            m_axi_gmem_rdata[j*8 +: 8] <= 8'd0;
          end
        end
        $display("AXI_R_NEXT_WGT_MEM: mem_base=0x%h bytes[%0d:%0d] time=%0t",
                 ADDR_B[15:0] + byte_base, byte_base, byte_base + 15, $time);
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
      captured_awaddr    <= 64'h0;
    end else begin
      if (m_axi_gmem_awvalid && !m_axi_gmem_awready) begin
        $display("AXI_AW: addr=0x%h len=%0d time=%0t", m_axi_gmem_awaddr, m_axi_gmem_awlen, $time);
        m_axi_gmem_awready <= 1;
        m_axi_gmem_bid     <= m_axi_gmem_awid;
        captured_awaddr    <= m_axi_gmem_awaddr;  // Capture the write address
        write_count        <= 0;
      end else begin
        m_axi_gmem_awready <= 0;
      end

      if (m_axi_gmem_awready) begin
        m_axi_gmem_wready <= 1;
        $display("DEBUG: WREADY asserted");
      end

      if (m_axi_gmem_wvalid && m_axi_gmem_wready) begin
        integer tile_addr_offset, tile_row, tile_col, base_row, base_col;
        integer linear_offset, i, matrix_idx;

        // Calculate which tile this address corresponds to using captured address
        tile_addr_offset = (captured_awaddr - ADDR_C);
        tile_row = tile_addr_offset / (16 * MATRIX_SIZE * 4);  // Which 16-row block
        tile_col = (tile_addr_offset % (16 * MATRIX_SIZE * 4)) / (16 * 4);  // Which 16-col block

        $display("DEBUG: Write beat %0d, data=0x%h, wlast=%0d", write_count, m_axi_gmem_wdata, m_axi_gmem_wlast);
        $display("DEBUG: Captured addr=0x%h, offset=0x%h, tile_row=%0d, tile_col=%0d", captured_awaddr, tile_addr_offset, tile_row, tile_col);

        // Each beat contains 4 consecutive 32-bit values within the current tile row
        for (i = 0; i < 4; i = i + 1) begin
          // Calculate position within the tile (16x16 elements per tile)
          base_row = tile_row * 16 + (write_count * 4 + i) / 16;  // Which row in the full matrix
          base_col = tile_col * 16 + (write_count * 4 + i) % 16;  // Which col in the full matrix

          // Convert to linear index in row-major order
          matrix_idx = base_row * MATRIX_SIZE + base_col;

          if (matrix_idx < NUM_ELEMENTS && base_row < MATRIX_SIZE && base_col < MATRIX_SIZE) begin
            mat_c_act[matrix_idx] = $signed(m_axi_gmem_wdata[i*32 +: 32]);
            $display("DEBUG: mat_c_act[%0d] = %0d (tile[%0d,%0d] pos[%0d,%0d] from data[%0d:%0d])",
                     matrix_idx, $signed(m_axi_gmem_wdata[i*32 +: 32]),
                     tile_row, tile_col, base_row, base_col, i*32+31, i*32);
          end
        end
        if (m_axi_gmem_wlast) begin
          m_axi_gmem_wready <= 0;
          m_axi_gmem_bvalid <= 1;
          $display("DEBUG: Write burst complete, asserting BVALID");
        end else begin
          write_count <= write_count + 1;
        end
      end

      if (m_axi_gmem_bvalid && m_axi_gmem_bready) begin
        m_axi_gmem_bvalid <= 0;
        $display("DEBUG: B handshake complete");
      end
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
        $display("DEBUG: Status read: 0x%h, done_bit=%0d, busy_bit=%0d, state=%0d",
                 st, st[0], st[1], dut.current_state);
        $display("DEBUG: Read addr=0x%h, state=%0d",
                 dut.s_axi_control_araddr, dut.current_state);
        to = to + 1;
        if (to > 100000) begin  // Timeout for 32x32 matrix chaining (4 tiles)
          $display("ERROR: done timeout");
          $finish;
        end
      end while ((st & 32'h1) != 32'h1);
      $display(">>> Accelerator DONE @ %0t", $time);
    end
  endtask

  //-------------------------------------------------------------------------
  // Matrix Printing Tasks
  //-------------------------------------------------------------------------
  task print_matrix_a();
    integer r, c;
    $display("\n=== MATRIX A (32x32) ===");
    for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
      $write("A[%2d]: ", r);
      for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
        $write("%3d ", mat_a[r * MATRIX_SIZE + c]);
      end
      $display("");
    end
    $display("=== END MATRIX A ===\n");
  endtask

  task print_matrix_b();
    integer r, c;
    $display("\n=== MATRIX B (32x32) ===");
    for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
      $write("B[%2d]: ", r);
      for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
        $write("%3d ", mat_b[r * MATRIX_SIZE + c]);
      end
      $display("");
    end
    $display("=== END MATRIX B ===\n");
  endtask

  task print_expected_result();
    integer r, c;
    $display("\n=== EXPECTED RESULT C = A × B (32x32) ===");
    for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
      $write("C_exp[%2d]: ", r);
      for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
        $write("%6d ", mat_c_exp[r * MATRIX_SIZE + c]);
      end
      $display("");
    end
    $display("=== END EXPECTED RESULT ===\n");
  endtask

  task print_actual_result();
    integer r, c;
    $display("\n=== ACTUAL RESULT FROM ACCELERATOR (32x32) ===");
    for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
      $write("C_act[%2d]: ", r);
      for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
        $write("%6d ", mat_c_act[r * MATRIX_SIZE + c]);
      end
      $display("");
    end
    $display("=== END ACTUAL RESULT ===\n");
  endtask

  task compare_matrices();
    integer r, c, errors;
    reg [31:0] expected_val, actual_val;
    real error_ratio;
    errors = 0;
    
    $display("\n=== ELEMENT-BY-ELEMENT COMPARISON ===");
    $display("Format: C[row][col]: expected=XXXX actual=XXXX ratio=X.XXX [STATUS]");
    
    for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
      for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
        expected_val = mat_c_exp[r * MATRIX_SIZE + c];
        actual_val = mat_c_act[r * MATRIX_SIZE + c];
        
        if (expected_val != 0) begin
          error_ratio = $itor(actual_val) / $itor(expected_val);
        end else begin
          error_ratio = (actual_val == 0) ? 1.0 : 999.0;
        end
        
        if (actual_val == expected_val) begin
          $display("C[%2d][%2d]: expected=%6d actual=%6d ratio=1.000 [PASS]", 
                   r, c, expected_val, actual_val);
        end else begin
          $display("C[%2d][%2d]: expected=%6d actual=%6d ratio=%5.3f [FAIL]", 
                   r, c, expected_val, actual_val, error_ratio);
          errors = errors + 1;
        end
      end
    end
    
    $display("\n=== COMPARISON SUMMARY ===");
    if (errors == 0) begin
      $display("? PERFECT! All %d elements match exactly! ?", MATRIX_SIZE * MATRIX_SIZE);
      $display("Matrix multiplication is 100%% accurate");
    end else begin
      $display("Found %d errors out of %d elements", errors, MATRIX_SIZE * MATRIX_SIZE);
      $display("Accuracy: %.2f%%", (1.0 - ($itor(errors) / $itor(MATRIX_SIZE * MATRIX_SIZE))) * 100.0);
    end
    $display("=== END COMPARISON ===\n");
  endtask

  //-------------------------------------------------------------------------
  // Verify results with comprehensive debug
  //-------------------------------------------------------------------------
  task verify;
    integer i, r, c;
    begin
      errors = 0;
      $display("=== Verification Starting ===");

      // Print complete matrices for manual verification
      print_matrix_a();
      print_matrix_b();
      print_expected_result();
      print_actual_result();
      
      // Perform detailed element-by-element comparison
      compare_matrices();

      // Debug: Manual calculation verification
      $display("DEBUG_VERIFICATION: Manual calculation check:");
      $display("  Expected C[0][0] = %0d (calculated during init)", mat_c_exp[0]);
      $display("  Actual C[0][0] = %0d (from accelerator)", mat_c_act[0]);
      $display("  Ratio = %0f", real'(mat_c_act[0]) / real'(mat_c_exp[0]));

      // Debug: Pattern analysis
      $display("DEBUG_VERIFICATION: Pattern analysis:");
      $display("  First row expected: %0d, %0d, %0d, %0d",
               mat_c_exp[0], mat_c_exp[1], mat_c_exp[2], mat_c_exp[3]);
      $display("  First row actual:   %0d, %0d, %0d, %0d",
               mat_c_act[0], mat_c_act[1], mat_c_act[2], mat_c_act[3]);
      $display("  Second row expected: %0d, %0d, %0d, %0d",
               mat_c_exp[32], mat_c_exp[33], mat_c_exp[34], mat_c_exp[35]);
      $display("  Second row actual:   %0d, %0d, %0d, %0d",
               mat_c_act[32], mat_c_act[33], mat_c_act[34], mat_c_act[35]);

      // Debug: Scaling factor analysis
      if (mat_c_exp[0] != 0 && mat_c_act[0] != 0) begin
        real scaling_factor;
        scaling_factor = real'(mat_c_act[0]) / real'(mat_c_exp[0]);
        $display("DEBUG_VERIFICATION: Scaling factor = %0f", scaling_factor);
        if (scaling_factor > 2.8 && scaling_factor < 3.2) begin
          $display("DEBUG_VERIFICATION: Results appear to be scaled by ~3x");
          $display("  Corrected C[0][0] = %0d (should be close to %0d)",
                   mat_c_act[0]/3, mat_c_exp[0]);
        end
      end

      $display("First few expected results: %0d, %0d, %0d, %0d",
               mat_c_exp[0], mat_c_exp[1], mat_c_exp[2], mat_c_exp[3]);
      $display("First few actual results: %0d, %0d, %0d, %0d",
               mat_c_act[0], mat_c_act[1], mat_c_act[2], mat_c_act[3]);

      for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin
        if (mat_c_act[i] !== mat_c_exp[i]) begin
          r = i / MATRIX_SIZE;
          c = i % MATRIX_SIZE;
          if (errors < 10) begin  // Limit error output for readability
            real ratio;
            ratio = (mat_c_exp[i] != 0) ? real'(mat_c_act[i]) / real'(mat_c_exp[i]) : 0.0;
            $display("ERR [%0d,%0d]: exp=%0d got=%0d ratio=%0f",
                     r, c, mat_c_exp[i], mat_c_act[i], ratio);
          end
          errors = errors + 1;
        end
      end
      // DEBUG: Statistical analysis of errors
      if (errors > 0) begin
        integer total_expected, total_actual;
        total_expected = 0;
        total_actual = 0;
        for (i = 0; i < 16; i = i + 1) begin  // Sample first 16 elements
          total_expected = total_expected + mat_c_exp[i];
          total_actual = total_actual + mat_c_act[i];
        end
        $display("DEBUG_VERIFY: Sample statistics (first 16 elements):");
        $display("  Total expected = %0d", total_expected);
        $display("  Total actual   = %0d", total_actual);
        $display("  Average scaling = %.3f", $itor(total_actual) / $itor(total_expected));
      end

      if (errors == 0)
        $display("*** PASS: All results match");
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

    // Initialize mat_c_act to known values to detect if writes occur
    for (integer init_i = 0; init_i < NUM_ELEMENTS; init_i = init_i + 1) begin
      mat_c_act[init_i] = 32'hDEADBEEF;
    end

    init_matrices();
    load_matrices_to_memory();

    // Wait for memory writes to complete before starting accelerator
    #100;
    $display("=== Memory loading delay completed ===");

    // Verify memory data before starting accelerator
    verify_memory_data();

    // Additional debug: track tile stepping
    $display("=== Starting accelerator with comprehensive debug ===");
    $display("DEBUG: Initial tile position: (%d,%d) inner_k=%d",
             dut.current_tile_row, dut.current_tile_col, dut.current_inner_k);

    $display("=== Matrix initialization complete (32x32) ===");
    $display("Sample A values: %0d, %0d, %0d, %0d", mat_a[0], mat_a[1], mat_a[2], mat_a[3]);
    $display("Sample B values: %0d, %0d, %0d, %0d", mat_b[0], mat_b[1], mat_b[2], mat_b[3]);
    $display("Sample expected C: %0d, %0d, %0d, %0d", mat_c_exp[0], mat_c_exp[1], mat_c_exp[2], mat_c_exp[3]);

    // Test matrix chaining mode for 32x32 (2x2 tiles) to validate multi-tile chaining
    $display("=== Testing Matrix Chaining Mode for 32x32 ===");

    // Configure matrix chaining for 32x32 operation
    axi_lite_wr(ACT_BASE_LSB, ADDR_A[31:0]);
    axi_lite_wr(ACT_BASE_MSB, ADDR_A[63:32]);
    axi_lite_wr(WGT_BASE_LSB, ADDR_B[31:0]);
    axi_lite_wr(WGT_BASE_MSB, ADDR_B[63:32]);
    axi_lite_wr(OUT_BASE_LSB, ADDR_C[31:0]);
    axi_lite_wr(OUT_BASE_MSB, ADDR_C[63:32]);
    axi_lite_wr(MATRIX_DIMS, (MATRIX_SIZE << 16) | MATRIX_SIZE);  // 32x32
    axi_lite_wr(CHAIN_CTRL, 32'h1);  // Enable chaining mode

    // Kick off
    $display("=== Starting accelerator operation ===");
    $display("DEBUG: Initial state = %0d", dut.current_state);
    axi_lite_wr(ADDR_CTRL, 32'h1);
    $display("DEBUG: State after start = %0d", dut.current_state);

    $display("=== Waiting for completion ===");
    wait_done();

    $display("=== Starting verification ===");
    verify();

    if (errors == 0)
      $display("=== TEST PASSED ===");
    else
      $display("=== TEST FAILED: %0d errors ===", errors);

    $finish;
  end

  //-------------------------------------------------------------------------
  // Debug monitor for accelerator state transitions
  //-------------------------------------------------------------------------
  always @(posedge ap_clk) begin
    if (ap_rst_n) begin
      // Simple test to verify monitoring works
      if ($time == 125000) $display("DEBUG: Monitor is working at time %0t", $time);

      // Monitor start pulse generation
      if (dut.start_pulse && !$past(dut.start_pulse)) begin
        $display("DEBUG: Start pulse generated at time %0t", $time);
      end

      if (dut.current_state != $past(dut.current_state)) begin
        case (dut.current_state)
          dut.S_IDLE:             $display("STATE: -> IDLE");
          dut.S_FETCH_ACT_ADDR:   $display("STATE: -> FETCH_ACT_ADDR");
          dut.S_FETCH_ACT_DATA:   $display("STATE: -> FETCH_ACT_DATA");
          dut.S_FETCH_WGT_ADDR:   $display("STATE: -> FETCH_WGT_ADDR");
          dut.S_FETCH_WGT_DATA:   $display("STATE: -> FETCH_WGT_DATA");
          dut.S_SYSTOLIC_COMPUTE: begin
            $display("STATE: -> SYSTOLIC_COMPUTE");
            $display("  activation_loaded=%0d, weight_loaded=%0d, matrices_loaded=%0d",
                     dut.activation_loaded, dut.weight_loaded, dut.matrices_loaded);
          end
          dut.S_WRITE_OUT_ADDR:   $display("STATE: -> WRITE_OUT_ADDR");
          dut.S_WRITE_OUT_DATA:   $display("STATE: -> WRITE_OUT_DATA");
          dut.S_WAIT_WRITE_END:   $display("STATE: -> WAIT_WRITE_END");
          dut.S_DONE:             $display("STATE: -> DONE");
          default:                $display("STATE: -> UNKNOWN(%0d)", dut.current_state);
        endcase
      end

      // Monitor critical flags during computation
      if (dut.current_state == dut.S_SYSTOLIC_COMPUTE) begin
        if (dut.systolic_cycle_count == 8'd35) begin
          $display("COMPUTE: cycle=35, capture_results=%0d, matrices_loaded=%0d",
                   dut.capture_results, dut.matrices_loaded);
        end
        if (dut.systolic_cycle_count == 8'd65) begin
          $display("COMPUTE: cycle=65, capture_results=%0d, packed_ready=%0d",
                   dut.capture_results, dut.packed_ready);
        end
        if (dut.systolic_cycle_count == 8'd70) begin
          $display("COMPUTE: cycle=70, packed_ready=%0d, transition condition=%0d",
                   dut.packed_ready, (dut.systolic_cycle_count >= 8'd70 && dut.packed_ready));
        end
      end

      // Monitor accelerator done flag changes
      if (dut.accelerator_done && !$past(dut.accelerator_done)) begin
        $display("DEBUG: Accelerator DONE flag set at time %0t, state=%0d", $time, dut.current_state);
      end

      // Monitor AXI-Lite read transactions
      if (s_axi_control_arvalid && s_axi_control_arready) begin
        $display("DEBUG: AXI-Lite AR: addr=0x%h", s_axi_control_araddr);
      end
      if (s_axi_control_rvalid && s_axi_control_rready) begin
        $display("DEBUG: AXI-Lite R: data=0x%h", s_axi_control_rdata);
      end

      // Monitor read signals from accelerator
      if (m_axi_gmem_arvalid && !$past(m_axi_gmem_arvalid)) begin
        $display("ACCEL: AR request - addr=0x%h, len=%0d", m_axi_gmem_araddr, m_axi_gmem_arlen);
      end
      if (m_axi_gmem_rready && !$past(m_axi_gmem_rready)) begin
        $display("ACCEL: RREADY asserted");
      end

      // Monitor write signals from accelerator
      if (m_axi_gmem_awvalid && !$past(m_axi_gmem_awvalid)) begin
        $display("ACCEL: AW request - addr=0x%h", m_axi_gmem_awaddr);
      end
      if (m_axi_gmem_wvalid && !$past(m_axi_gmem_wvalid)) begin
        $display("ACCEL: W valid asserted");
      end
    end
  end

  //-------------------------------------------------------------------------
  // Timeout watchdog - 16x16 matrix with chaining
  //-------------------------------------------------------------------------
  // State transition monitoring for debug
  reg [3:0] prev_state = 4'h0;
  integer state_transition_count = 0;
  integer computation_count = 0;

  always @(posedge ap_clk) begin
    if (dut.current_state != prev_state) begin
      state_transition_count = state_transition_count + 1;
      $display("STATE_TRANS[%0d]: %0d->%0d tile(%d,%d) inner_k=%d time=%0t",
               state_transition_count, prev_state, dut.current_state,
               dut.current_tile_row, dut.current_tile_col, dut.current_inner_k, $time);
      prev_state = dut.current_state;

      // Track computation starts
      if (dut.current_state == 5) begin // S_SYSTOLIC_COMPUTE = 5
        computation_count = computation_count + 1;
        $display("COMPUTATION_START[%0d]: tile(%d,%d) inner_k=%d time=%0t",
                 computation_count, dut.current_tile_row, dut.current_tile_col, dut.current_inner_k, $time);
      end
    end
  end

  initial begin
    #500_000_000;  // 500ms for 32x32 matrix chaining (4 tiles)
    $display("ERROR: simulation timed out");
    $finish;
  end

endmodule