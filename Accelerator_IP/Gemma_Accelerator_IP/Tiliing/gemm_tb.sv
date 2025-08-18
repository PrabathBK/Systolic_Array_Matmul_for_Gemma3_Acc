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
  // Matrix Printing Verbosity Control
  //-------------------------------------------------------------------------
  // PRINT_LEVEL controls the amount of matrix data printed to simulation log:
  //   0 = MINIMAL:  Only pass/fail results, minimal debug output
  //   1 = SUMMARY:  Key values (C[0][0]), final summary table, compact format
  //   2 = FULL:     Complete 32x32 matrices for all sets, detailed comparison
  //
  // Note: PRINT_LEVEL=2 generates large log files (~50MB) but provides
  // complete visibility into all input/output matrices for debugging
  parameter integer PRINT_LEVEL        = 2;  // 0=minimal, 1=summary, 2=full matrices

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

  // Streaming status output signals
  wire                result_ready_interrupt;
  wire                ping_buffer_ready;
  wire                pong_buffer_ready;
  wire                ping_result_available;
  wire                pong_result_available;

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
  reg [7:0]             memory       [0:MEMORY_SIZE-1]; // Memory array [0:65535]

  // Multiple matrix sets for streaming test
  parameter NUM_MATRIX_SETS = 5;
  reg signed [7:0]    mat_a_sets   [0:NUM_MATRIX_SETS-1][0:NUM_ELEMENTS-1];   // Source matrix A sets
  reg signed [7:0]    mat_b_sets   [0:NUM_MATRIX_SETS-1][0:NUM_ELEMENTS-1];   // Source matrix B sets
  reg signed [31:0]   mat_c_exp_sets [0:NUM_MATRIX_SETS-1][0:NUM_ELEMENTS-1]; // expected results
  reg signed [31:0]   mat_c_act_sets [0:NUM_MATRIX_SETS-1][0:NUM_ELEMENTS-1]; // captured results

  // Streaming control variables
  reg [2:0]           matrices_sent;     // Count of matrices sent (0-4)
  reg [2:0]           matrices_completed; // Count of matrices completed (0-4)
  reg [2:0]           current_set;       // Current matrix set being processed
  reg [2:0]           current_write_set; // Matrix set currently being written by accelerator
  reg                 pipeline_active;   // Pipeline operation active

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
  localparam [7:0]  CHAIN_STATUS = 8'h84;

  // Streaming control registers
  localparam [7:0]  BUFFER_STATUS   = 8'h88;
  localparam [7:0]  COMPUTATION_ID  = 8'h8C;
  localparam [7:0]  BUFFER_CTRL     = 8'h90;
  localparam [7:0]  STREAM_CONFIG   = 8'h94;

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
    .m_axi_gmem_rresp     (m_axi_gmem_rresp),
    // Streaming status outputs
    .result_ready_interrupt(result_ready_interrupt),
    .ping_buffer_ready    (ping_buffer_ready),
    .pong_buffer_ready    (pong_buffer_ready),
    .ping_result_available(ping_result_available),
    .pong_result_available(pong_result_available)
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
    integer set, r, c, k;
    integer sum;
    begin
      $display("=== Initializing %0d matrix sets for streaming test ===", NUM_MATRIX_SETS);

      // Initialize all matrix sets
      for (set = 0; set < NUM_MATRIX_SETS; set = set + 1) begin
        $display("Initializing matrix set %0d...", set);

        //------ Fill Matrix A (32x32 pattern with set variation) ------//
        for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
          for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
            // Add set index to create different patterns for each set
            mat_a_sets[set][r*MATRIX_SIZE + c] = ((r + c + 1) + (set * 7)) % 256;
          end
        end

        //------ Fill Matrix B (32x32 pattern with set variation) ------//
        for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
          for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
            // Add set index to create different patterns for each set
            mat_b_sets[set][r*MATRIX_SIZE + c] = ((r * 2 + c + 1) + (set * 11)) % 256;
          end
        end

        //------ Compute golden C = A×B for each set ------//
        // Calculate expected result for full 32x32 matrix multiplication with chaining
        for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
          for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
            sum = 0;
            for (k = 0; k < MATRIX_SIZE; k = k + 1) begin
              sum = sum + $signed(mat_a_sets[set][r*MATRIX_SIZE + k]) * $signed(mat_b_sets[set][k*MATRIX_SIZE + c]);
            end
            mat_c_exp_sets[set][r*MATRIX_SIZE + c] = sum;
          end
        end

        // Debug first set details
        if (set == 0) begin
          $display("DEBUG_SET_0: A[0][0:3] = %0d,%0d,%0d,%0d",
                   mat_a_sets[0][0], mat_a_sets[0][1], mat_a_sets[0][2], mat_a_sets[0][3]);
          $display("DEBUG_SET_0: B[0][0:3] = %0d,%0d,%0d,%0d",
                   mat_b_sets[0][0], mat_b_sets[0][1], mat_b_sets[0][2], mat_b_sets[0][3]);
          $display("DEBUG_SET_0: Expected C[0][0] = %0d", mat_c_exp_sets[0][0]);
        end

        $display("Set %0d: A[0][0]=%0d, B[0][0]=%0d, Expected C[0][0]=%0d",
                 set, mat_a_sets[set][0], mat_b_sets[set][0], mat_c_exp_sets[set][0]);

        // Print complete matrices for each set (if verbosity enabled)
        if (PRINT_LEVEL >= 2) begin
          $display("Printing complete input matrices for set %0d:", set);
          print_matrix_a(set);
          print_matrix_b(set);
          print_matrix_c_expected(set);
        end
      end

      // Initialize streaming control variables
      matrices_sent = 0;
      matrices_completed = 0;
      current_set = 0;
      pipeline_active = 0;

      $display("Matrix initialization complete for streaming test with %0d sets (32x32 matrices)", NUM_MATRIX_SETS);
      $display("IMPORTANT: Hardware will compute full 32x32 matrices using chaining mode");
    end
  endtask

  //-------------------------------------------------------------------------
  // Matrix Printing Tasks for Complete Visibility
  //-------------------------------------------------------------------------
  // These tasks provide comprehensive matrix printing capabilities:
  //   - print_matrix_a/b/c_*: Print individual 32x32 matrices in formatted layout
  //   - print_matrix_comparison: Show element-wise differences between expected/actual
  //   - print_all_matrices: Complete dump of all matrices for a given set
  //   - print_final_summary: Compact overview of all 5 matrix sets
  //
  // Matrix format: 32x32 with 4-digit signed integers for inputs (A,B)
  //                and 8-digit signed integers for outputs (C)
  //-------------------------------------------------------------------------
  task print_matrix_a;
    input integer set_id;
    integer r, c;
    begin
      $display("=== INPUT MATRIX A (SET %0d) ===", set_id);
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        $write("A[%2d]: ", r);
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          $write("%4d ", $signed(mat_a_sets[set_id][r*MATRIX_SIZE + c]));
        end
        $display("");
      end
      $display("");
    end
  endtask

  task print_matrix_b;
    input integer set_id;
    integer r, c;
    begin
      $display("=== INPUT MATRIX B (SET %0d) ===", set_id);
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        $write("B[%2d]: ", r);
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          $write("%4d ", $signed(mat_b_sets[set_id][r*MATRIX_SIZE + c]));
        end
        $display("");
      end
      $display("");
    end
  endtask

  task print_matrix_c_expected;
    input integer set_id;
    integer r, c;
    begin
      $display("=== EXPECTED OUTPUT MATRIX C (SET %0d) ===", set_id);
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        $write("C_exp[%2d]: ", r);
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          $write("%8d ", mat_c_exp_sets[set_id][r*MATRIX_SIZE + c]);
        end
        $display("");
      end
      $display("");
    end
  endtask

  task print_matrix_c_actual;
    input integer set_id;
    integer r, c;
    begin
      $display("=== ACTUAL OUTPUT MATRIX C (SET %0d) ===", set_id);
      for (r = 0; r < MATRIX_SIZE; r = r + 1) begin
        $write("C_act[%2d]: ", r);
        for (c = 0; c < MATRIX_SIZE; c = c + 1) begin
          $write("%8d ", mat_c_act_sets[set_id][r*MATRIX_SIZE + c]);
        end
        $display("");
      end
      $display("");
    end
  endtask

  task print_matrix_comparison;
    input integer set_id;
    integer r, c, idx;
    integer errors_shown;
    begin
      $display("=== MATRIX COMPARISON (SET %0d) ===", set_id);
      $display("Format: [row,col] Expected -> Actual (Difference)");
      errors_shown = 0;

      for (r = 0; r < MATRIX_SIZE && errors_shown < 20; r = r + 1) begin
        for (c = 0; c < MATRIX_SIZE && errors_shown < 20; c = c + 1) begin
          idx = r * MATRIX_SIZE + c;
          if (mat_c_exp_sets[set_id][idx] != mat_c_act_sets[set_id][idx]) begin
            $display("  [%2d,%2d] %8d -> %8d (diff: %8d)",
                     r, c,
                     mat_c_exp_sets[set_id][idx],
                     mat_c_act_sets[set_id][idx],
                     mat_c_act_sets[set_id][idx] - mat_c_exp_sets[set_id][idx]);
            errors_shown = errors_shown + 1;
          end
        end
      end

      if (errors_shown == 0) begin
        $display("  ALL ELEMENTS MATCH PERFECTLY!");
      end else if (errors_shown >= 20) begin
        $display("  ... (showing first 20 mismatches only)");
      end
      $display("");
    end
  endtask

  task print_all_matrices;
    input integer set_id;
    begin
      $display("================================================================================");
      $display("                           COMPLETE MATRIX DUMP FOR SET %0d", set_id);
      $display("================================================================================");

      print_matrix_a(set_id);
      print_matrix_b(set_id);
      print_matrix_c_expected(set_id);
      print_matrix_c_actual(set_id);
      print_matrix_comparison(set_id);

      $display("================================================================================");
      $display("                         END MATRIX DUMP FOR SET %0d", set_id);
      $display("================================================================================");
      $display("");
    end
  endtask

  //-------------------------------------------------------------------------
  // Final Summary Printing Task
  //-------------------------------------------------------------------------
  task print_final_summary;
    integer set_id;
    begin
      $display("");
      $display("################################################################################");
      $display("#                    FINAL TEST SUMMARY (PRINT_LEVEL=%0d)                   #", PRINT_LEVEL);
      $display("#                                                                            #");
      $display("# This summary shows key results for all 5 matrix sets:                     #");
      $display("# - Input matrices A[0][0:3] and B[0][0:3] (first 4 elements)              #");
      $display("# - Expected vs Actual C[0][0] values                                       #");
      $display("# - PASS/FAIL status for each set                                           #");
      $display("#                                                                            #");
      $display("################################################################################");
      $display("");

      for (set_id = 0; set_id < NUM_MATRIX_SETS; set_id = set_id + 1) begin
        $display("=== MATRIX SET %0d SUMMARY ===", set_id);
        $display("Input A[0][0:3]: %4d %4d %4d %4d",
                 $signed(mat_a_sets[set_id][0]), $signed(mat_a_sets[set_id][1]),
                 $signed(mat_a_sets[set_id][2]), $signed(mat_a_sets[set_id][3]));
        $display("Input B[0][0:3]: %4d %4d %4d %4d",
                 $signed(mat_b_sets[set_id][0]), $signed(mat_b_sets[set_id][1]),
                 $signed(mat_b_sets[set_id][2]), $signed(mat_b_sets[set_id][3]));
        $display("Expected C[0][0]: %8d", mat_c_exp_sets[set_id][0]);
        $display("Actual   C[0][0]: %8d", mat_c_act_sets[set_id][0]);
        if (mat_c_exp_sets[set_id][0] == mat_c_act_sets[set_id][0]) begin
          $display("Result: PASS ✓");
        end else begin
          $display("Result: FAIL ✗ (Error: %0d)",
                   mat_c_act_sets[set_id][0] - mat_c_exp_sets[set_id][0]);
        end
        $display("");
      end

      $display("################################################################################");
      $display("#                        END FINAL TEST SUMMARY                              #");
      $display("################################################################################");
      $display("");
    end
  endtask

  //-------------------------------------------------------------------------
  // Enhanced streaming state monitoring and reset
  //-------------------------------------------------------------------------
  task monitor_systolic_state;
    input string prefix;
    begin
      $display("%s: Monitoring accelerator state at time %0t", prefix, $time);
      $display("  Current state = %0d", dut.current_state);
      $display("  Start pulse = %b", dut.start_pulse);
      $display("  Done flag = %b", dut.accelerator_done);
    end
  endtask

  task ensure_clean_start;
    input integer set_id;
    begin
      $display("STREAMING: Ensuring clean start for set %0d", set_id);

      // Monitor state before cleanup
      monitor_systolic_state("PRE-CLEANUP");

      // Wait for any ongoing computation to complete
      while (dut.current_state != dut.S_IDLE) begin
        #1000;
        $display("STREAMING: Waiting for accelerator to return to IDLE, current_state=%0d", dut.current_state);
      end

      // Additional delay to ensure complete state cleanup
      #5000;

      // Monitor state after cleanup
      monitor_systolic_state("POST-CLEANUP");
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
    input integer set_index; // Which matrix set to load
    integer r, c, mem_addr, tile_row, tile_col, inner_k, accelerator_addr;
    begin
      $display("Loading matrix set %0d into memory using BYTE ADDRESSING...", set_index);

      // Initialize entire memory to zero first (only for first set)
      if (set_index == 0) begin
        for (mem_addr = 0; mem_addr < MEMORY_SIZE; mem_addr = mem_addr + 1) begin
          memory[mem_addr] = 8'h00;
        end
      end

      // Load Matrix A using byte addressing
      for (tile_row = 0; tile_row < 2; tile_row = tile_row + 1) begin
        for (inner_k = 0; inner_k < 2; inner_k = inner_k + 1) begin
          // Calculate base address for this tile_row and inner_k (BYTE ADDRESSING)
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
                  memory[mem_addr] = mat_a_sets[set_index][src_row * MATRIX_SIZE + src_col];
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
                  memory[mem_addr] = mat_b_sets[set_index][src_row * MATRIX_SIZE + src_col];
                end
              end
            end
          end
        end
      end

      $display("Memory loading complete for set %0d", set_index);
      $display("Set %0d A[0][0-3] = %0d,%0d,%0d,%0d", set_index,
               memory[ADDR_A[15:0]], memory[ADDR_A[15:0]+1], memory[ADDR_A[15:0]+2], memory[ADDR_A[15:0]+3]);

      // Force memory update to ensure all writes are completed
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
            // Store result in the correct matrix set based on which one is currently being written
            // Update result matrices during write operations
            if (matrices_completed >= 0 && matrices_completed < NUM_MATRIX_SETS) begin
              mat_c_act_sets[matrices_completed][matrix_idx] = $signed(m_axi_gmem_wdata[i*32 +: 32]);
              if (matrix_idx < 10) begin  // Only debug first few elements
                $display("DEBUG: mat_c_act_sets[%0d][%0d] = %0d (tile[%0d,%0d] pos[%0d,%0d])",
                         matrices_completed, matrix_idx, $signed(m_axi_gmem_wdata[i*32 +: 32]),
                         tile_row, tile_col, base_row, base_col);
              end
            end
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
  // Wait for DONE bit-0 with Matrix Chaining Support
  //-------------------------------------------------------------------------
  task wait_done;
    input integer set_id; // Which matrix set we're waiting for
    reg [31:0] st, chain_status;
    integer    to;
    reg        seen_busy, chain_complete;
    begin
      to = 0;
      seen_busy = 0;
      chain_complete = 0;

      $display("CHAINING: Waiting for 32x32 matrix chaining completion for set %0d", set_id);

      // First wait for the accelerator to become busy (avoid race condition)
      do begin
        #100;
        axi_lite_rd(ADDR_STATUS, st);
        if ((st & 32'h2) == 32'h2) begin  // Check busy bit (bit 1)
          seen_busy = 1;
          $display("CHAINING: Set %0d started processing (busy detected)", set_id);
        end
        to = to + 1;
        if (to > 10000) begin
          $display("ERROR: timeout waiting for set %0d to start", set_id);
          $finish;
        end
      end while (!seen_busy);

      // Now wait for matrix chaining completion
      to = 0;
      do begin
        #500;  // Longer polling interval for chaining
        axi_lite_rd(ADDR_STATUS, st);
        axi_lite_rd(CHAIN_STATUS, chain_status);

        // Check for chain completion (bit 1 = chain_complete)
        chain_complete = (chain_status & 32'h2) == 32'h2;

        if (to % 500 == 0) begin  // Reduce debug output
          $display("CHAINING: Set %0d progress - status=0x%h, chain_status=0x%h, state=%0d, iter=%0d, chain_complete=%b",
                   set_id, st, chain_status, dut.current_state, to, chain_complete);
        end
        to = to + 1;
        if (to > 200000) begin  // Extended timeout for 32x32 matrix chaining (4 tiles)
          $display("ERROR: timeout waiting for set %0d chaining completion", set_id);
          $display("Final status: basic=0x%h, chain=0x%h, state=%0d", st, chain_status, dut.current_state);
          $finish;
        end
      end while (!chain_complete && !((st & 32'h1) == 32'h1 && (st & 32'h2) == 32'h0));

      $display(">>> CHAINING: Set %0d COMPLETED @ %0t (status=0x%h, chain_status=0x%h)",
               set_id, $time, st, chain_status);

      // Extended delay to ensure all tiles are written to memory
      #5000;
    end
  endtask

  //-------------------------------------------------------------------------
  // Hybrid wait using proven basic status with streaming register monitoring
  //-------------------------------------------------------------------------
  task wait_done_streaming;
    input integer set_id; // Which matrix set we're waiting for
    reg [31:0] st, buffer_status, comp_id;
    integer    to;
    reg        seen_busy;
    begin
      to = 0;
      seen_busy = 0;

      $display("HYBRID: Waiting for set %0d completion using proven basic status method", set_id);

      // First wait for the accelerator to become busy (avoid race condition)
      do begin
        #100;
        axi_lite_rd(ADDR_STATUS, st);
        if ((st & 32'h2) == 32'h2) begin  // Check busy bit (bit 1)
          seen_busy = 1;
          $display("HYBRID: Set %0d started processing (busy detected)", set_id);
        end
        to = to + 1;
        if (to > 10000) begin
          $display("ERROR: timeout waiting for set %0d to start", set_id);
          $finish;
        end
      end while (!seen_busy);

      // Now wait for completion (done bit set and not busy)
      to = 0;
      do begin
        #100;
        axi_lite_rd(ADDR_STATUS, st);

        // Monitor streaming registers for debugging (non-blocking)
        if (to % 1000 == 0) begin
          axi_lite_rd(BUFFER_STATUS, buffer_status);
          axi_lite_rd(COMPUTATION_ID, comp_id);
          $display("HYBRID: Set %0d progress - basic_status=0x%h, buffer_status=0x%h, comp_id=0x%h, iter=%0d",
                   set_id, st, buffer_status, comp_id, to);
        end

        to = to + 1;
        if (to > 100000) begin  // Timeout for 32x32 matrix chaining (4 tiles)
          $display("ERROR: timeout waiting for set %0d completion", set_id);
          $finish;
        end
      end while (!((st & 32'h1) == 32'h1 && (st & 32'h2) == 32'h0));  // Done=1 and Busy=0

      // Final streaming register read for validation
      axi_lite_rd(BUFFER_STATUS, buffer_status);
      axi_lite_rd(COMPUTATION_ID, comp_id);
      $display(">>> HYBRID: Set %0d COMPLETED @ %0t (basic_status=0x%h, buffer_status=0x%h, comp_id=0x%h)",
               set_id, $time, st, buffer_status, comp_id);

      // Small delay to ensure done signal is stable before next operation
      #1000;
    end
  endtask

  //-------------------------------------------------------------------------
  // Verify results with comprehensive debug
  //-------------------------------------------------------------------------
  task verify;
    input integer set_id; // Which matrix set to verify
    integer i, r, c, local_errors;
    begin
      local_errors = 0;
      $display("=== Verification Starting for Set %0d (32x32 matrix with chaining) ===", set_id);

      // Debug: Manual calculation verification
      $display("DEBUG_VERIFICATION_SET_%0d: Manual calculation check:", set_id);
      $display("  Expected C[0][0] = %0d (calculated for 32x32 matrix)", mat_c_exp_sets[set_id][0]);
      $display("  Actual C[0][0] = %0d (from accelerator)", mat_c_act_sets[set_id][0]);
      if (mat_c_exp_sets[set_id][0] != 0) begin
        $display("  Ratio = %0f", real'(mat_c_act_sets[set_id][0]) / real'(mat_c_exp_sets[set_id][0]));
      end

      // Debug: Pattern analysis for 32x32 matrix
      $display("DEBUG_VERIFICATION_SET_%0d: Pattern analysis (32x32 matrix):", set_id);
      $display("  First row expected: %0d, %0d, %0d, %0d",
               mat_c_exp_sets[set_id][0], mat_c_exp_sets[set_id][1],
               mat_c_exp_sets[set_id][2], mat_c_exp_sets[set_id][3]);
      $display("  First row actual:   %0d, %0d, %0d, %0d",
               mat_c_act_sets[set_id][0], mat_c_act_sets[set_id][1],
               mat_c_act_sets[set_id][2], mat_c_act_sets[set_id][3]);

      for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin
        if (mat_c_act_sets[set_id][i] !== mat_c_exp_sets[set_id][i]) begin
          r = i / MATRIX_SIZE;
          c = i % MATRIX_SIZE;
          if (local_errors < 10) begin  // Limit error output for readability
            real ratio;
            ratio = (mat_c_exp_sets[set_id][i] != 0) ?
                   real'(mat_c_act_sets[set_id][i]) / real'(mat_c_exp_sets[set_id][i]) : 0.0;
            $display("SET_%0d ERR [%0d,%0d]: exp=%0d got=%0d ratio=%0f",
                     set_id, r, c, mat_c_exp_sets[set_id][i], mat_c_act_sets[set_id][i], ratio);
          end
          local_errors = local_errors + 1;
        end
      end

      if (local_errors == 0) begin
        $display("*** SET %0d PASS: All results match", set_id);
      end else begin
        $display("*** SET %0d FAIL: %0d mismatches", set_id, local_errors);
        errors = errors + local_errors;
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Debug task to display all streaming control registers
  //-------------------------------------------------------------------------
  task display_streaming_status;
    input string prefix;
    reg [31:0] buffer_status, comp_id, buffer_ctrl, stream_config;
    begin
      axi_lite_rd(BUFFER_STATUS, buffer_status);
      axi_lite_rd(COMPUTATION_ID, comp_id);
      axi_lite_rd(BUFFER_CTRL, buffer_ctrl);
      axi_lite_rd(STREAM_CONFIG, stream_config);

      $display("%s STREAMING STATUS:", prefix);
      $display("  BUFFER_STATUS=0x%h (ping_avail=%b, pong_avail=%b, ping_result=%b, pong_result=%b)",
               buffer_status, buffer_status[0], buffer_status[1], buffer_status[2], buffer_status[3]);
      $display("  COMPUTATION_ID=0x%h (ping_id=%h, pong_id=%h)",
               comp_id, comp_id[15:0], comp_id[31:16]);
      $display("  BUFFER_CTRL=0x%h", buffer_ctrl);
      $display("  STREAM_CONFIG=0x%h", stream_config);
      $display("  Interrupt signals: result_ready=%b, ping_ready=%b, pong_ready=%b, ping_result=%b, pong_result=%b",
               result_ready_interrupt, ping_buffer_ready, pong_buffer_ready, ping_result_available, pong_result_available);
    end
  endtask

  //-------------------------------------------------------------------------
  // Hybrid Matrix Processing Task - Basic start with streaming monitoring
  //-------------------------------------------------------------------------
  task stream_next_matrix;
    input integer next_set;
    reg [31:0] buffer_status, comp_id, status_before, status_after;
    begin
      $display("=== SEQUENTIAL: Loading and starting matrix set %0d ===", next_set);

      // Check status before starting
      axi_lite_rd(ADDR_STATUS, status_before);
      $display("SEQUENTIAL: Status before loading set %0d: 0x%h", next_set, status_before);

      // Load matrices to memory
      load_matrices_to_memory(next_set);

      // Small delay to ensure memory loading is complete
      #1000;

      // CRITICAL FIX: Configure all registers for 32x32 matrix chaining
      $display("SEQUENTIAL: Configuring address registers and chaining mode for set %0d", next_set);
      axi_lite_wr(A_LSB, ADDR_A[31:0]);
      axi_lite_wr(A_MSB, ADDR_A[63:32]);
      axi_lite_wr(B_LSB, ADDR_B[31:0]);
      axi_lite_wr(B_MSB, ADDR_B[63:32]);
      axi_lite_wr(C_LSB, ADDR_C[31:0]);
      axi_lite_wr(C_MSB, ADDR_C[63:32]);

      // Configure matrix chaining for 32x32 operation
      axi_lite_wr(ACT_BASE_LSB, ADDR_A[31:0]);
      axi_lite_wr(ACT_BASE_MSB, ADDR_A[63:32]);
      axi_lite_wr(WGT_BASE_LSB, ADDR_B[31:0]);
      axi_lite_wr(WGT_BASE_MSB, ADDR_B[63:32]);
      axi_lite_wr(OUT_BASE_LSB, ADDR_C[31:0]);
      axi_lite_wr(OUT_BASE_MSB, ADDR_C[63:32]);
      axi_lite_wr(MATRIX_DIMS, {16'd32, 16'd32});  // Set 32x32 dimensions
      axi_lite_wr(CHAIN_CTRL, 32'h1);              // Enable chaining mode

      // CRITICAL FIX: Ensure clean state before each matrix set
      if (next_set > 0) begin
        ensure_clean_start(next_set);
      end

      // Small delay to ensure register writes complete
      #1000;

      // Start accelerator
      $display("SEQUENTIAL: Starting accelerator for set %0d", next_set);
      axi_lite_wr(ADDR_CTRL, 32'h1);

      // Verify that the accelerator started
      #500;
      axi_lite_rd(ADDR_STATUS, status_after);
      $display("SEQUENTIAL: Set %0d started, status after start=0x%h", next_set, status_after);

      // Monitor streaming registers for validation
      axi_lite_rd(BUFFER_STATUS, buffer_status);
      axi_lite_rd(COMPUTATION_ID, comp_id);
      $display("SEQUENTIAL: Streaming status - buffer_status=0x%h, comp_id=0x%h", buffer_status, comp_id);

      // Wait a bit to ensure the operation has properly started
      #1000;
    end
  endtask

  //-------------------------------------------------------------------------
  // Main Streaming Test
  //-------------------------------------------------------------------------
  initial begin
    integer set_idx;

    ap_rst_n             = 0;
    s_axi_control_awvalid = 0;
    s_axi_control_wvalid  = 0;
    s_axi_control_bready  = 0;
    s_axi_control_arvalid = 0;
    s_axi_control_rready  = 0;
    errors = 0;
    #100;
    ap_rst_n = 1;

    // Initialize all result matrices to known values to detect writes
    for (set_idx = 0; set_idx < NUM_MATRIX_SETS; set_idx = set_idx + 1) begin
      for (integer init_i = 0; init_i < NUM_ELEMENTS; init_i = init_i + 1) begin
        mat_c_act_sets[set_idx][init_i] = 32'hDEADBEEF;
      end
    end

    // Initialize all matrix sets
    init_matrices();

    // Configure accelerator for 32x32 matrix chaining
    $display("=== Configuring accelerator for 32x32 matrix chaining operation ===");

    $display("=== Starting 32x32 matrix processing with chaining and %0d sets ===", NUM_MATRIX_SETS);
    $display("SEQUENTIAL: Using matrix chaining mode for full 32x32 computation");

    pipeline_active = 1;

    // Start first matrix
    $display("SEQUENTIAL: Starting initial matrix set 0");
    stream_next_matrix(0);

    // Sequential processing loop - process one matrix at a time
    while (matrices_completed < NUM_MATRIX_SETS) begin
      // Wait for current matrix completion
      wait_done(matrices_completed);

      // Monitor final state after completion
      monitor_systolic_state($sformatf("COMPLETED SET %0d", matrices_completed));

      // Results are already captured in mat_c_act_sets during write process
      $display("SEQUENTIAL: Results captured for set %0d", matrices_completed);

      // Print complete matrix results before verification (based on verbosity level)
      // PRINT_LEVEL=0: Minimal output for automated testing
      // PRINT_LEVEL=1: Summary values for quick verification
      // PRINT_LEVEL=2: Full matrix dumps for detailed debugging
      case (PRINT_LEVEL)
        0: begin
          // Minimal printing - just pass/fail
          $display("MATRIX OUTPUT: Set %0d processing complete", matrices_completed);
        end
        1: begin
          // Summary printing - key values only
          $display("MATRIX OUTPUT: Set %0d summary:", matrices_completed);
          $display("  Expected C[0][0]: %8d", mat_c_exp_sets[matrices_completed][0]);
          $display("  Actual   C[0][0]: %8d", mat_c_act_sets[matrices_completed][0]);
        end
        2: begin
          // Full printing - complete matrices (WARNING: Large log output)
          $display("MATRIX OUTPUT: Printing complete 32x32 matrices for set %0d", matrices_completed);
          $display("NOTE: Full matrix dump follows - each matrix is 32x32 = 1024 elements");
          print_all_matrices(matrices_completed);
        end
      endcase

      // Verify completed set
      verify(matrices_completed);

      matrices_completed = matrices_completed + 1;
      matrices_sent = matrices_completed;
      $display("SEQUENTIAL: Progress - completed=%0d, sent=%0d", matrices_completed, matrices_sent);

      // If more matrices to send, start the next one
      if (matrices_sent < NUM_MATRIX_SETS) begin
        // Add delay between operations to ensure clean state
        #5000;
        stream_next_matrix(matrices_sent);
      end
    end

    pipeline_active = 0;

    // Final verification summary
    $display("=== 32x32 MATRIX CHAINING TEST COMPLETE ===");
    $display("Total matrix sets processed: %0d", NUM_MATRIX_SETS);
    $display("Total errors across all sets: %0d", errors);

    if (errors == 0) begin
      $display("=== 32x32 MATRIX CHAINING TEST PASSED: All %0d matrix sets verified successfully ===", NUM_MATRIX_SETS);
      $display("=== STREAMING REGISTERS: Successfully monitored throughout test ===");
      if (PRINT_LEVEL >= 1) begin
        $display("=== FINAL SUMMARY: All input/output matrices printed above for complete verification ===");
      end
    end else begin
      $display("=== 32x32 MATRIX CHAINING TEST FAILED: %0d total errors across all sets ===", errors);
      if (PRINT_LEVEL >= 1) begin
        $display("=== FINAL SUMMARY: Failed matrix sets have detailed printouts above for debugging ===");
      end
    end

    // Print final summary of all matrix sets (based on verbosity level)
    if (PRINT_LEVEL >= 1) begin
      print_final_summary();
    end

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

          // Monitor streaming status signals
          if (result_ready_interrupt && !$past(result_ready_interrupt)) begin
            $display("DEBUG: Result ready interrupt asserted at time %0t", $time);
          end

          if (result_ready_interrupt && $past(result_ready_interrupt) && !result_ready_interrupt) begin
            $display("DEBUG: Result ready interrupt deasserted at time %0t", $time);
          end

          if (ping_buffer_ready != $past(ping_buffer_ready)) begin
            $display("DEBUG: Ping buffer ready changed to %b at time %0t", ping_buffer_ready, $time);
          end

          if (pong_buffer_ready != $past(pong_buffer_ready)) begin
            $display("DEBUG: Pong buffer ready changed to %b at time %0t", pong_buffer_ready, $time);
          end

          if (ping_result_available != $past(ping_result_available)) begin
            $display("DEBUG: Ping result available changed to %b at time %0t", ping_result_available, $time);
          end

          if (pong_result_available != $past(pong_result_available)) begin
            $display("DEBUG: Pong result available changed to %b at time %0t", pong_result_available, $time);
          end

          // Monitor buffer state changes
          if (dut.ping_state != $past(dut.ping_state)) begin
            $display("DEBUG: Ping buffer state changed from %0d to %0d at time %0t",
                     $past(dut.ping_state), dut.ping_state, $time);
          end

          if (dut.pong_state != $past(dut.pong_state)) begin
            $display("DEBUG: Pong buffer state changed from %0d to %0d at time %0t",
                     $past(dut.pong_state), dut.pong_state, $time);
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


//-------------------------------------------------------------------------
// Interrupt monitoring task for enhanced streaming
//-------------------------------------------------------------------------
initial begin
  forever begin
    @(posedge result_ready_interrupt);
    $display("INTERRUPT: Result ready interrupt detected at time %0t", $time);

    // Log current buffer status when interrupt occurs
    #100;  // Small delay to allow register updates
    axi_lite_rd(BUFFER_STATUS, captured_awaddr);  // Reuse existing reg for temp storage
    $display("INTERRUPT: Buffer status at interrupt time: 0x%h", captured_awaddr);

    axi_lite_rd(COMPUTATION_ID, captured_awaddr);  // Reuse existing reg for temp storage
    $display("INTERRUPT: Computation ID at interrupt time: 0x%h", captured_awaddr);
  end
end

//-------------------------------------------------------------------------
// Buffer availability monitoring for streaming optimization
//-------------------------------------------------------------------------
always @(posedge ap_clk) begin
  if (ap_rst_n && pipeline_active) begin
    // Log buffer availability changes during active streaming
    if ((ping_buffer_ready || pong_buffer_ready) &&
        !(($past(ping_buffer_ready) || $past(pong_buffer_ready)))) begin
      $display("STREAMING: Buffer became available - ping=%b, pong=%b at time %0t",
               ping_buffer_ready, pong_buffer_ready, $time);
    end

    // Warn if both buffers become unavailable during streaming
    if (!ping_buffer_ready && !pong_buffer_ready &&
        ($past(ping_buffer_ready) || $past(pong_buffer_ready))) begin
      $display("STREAMING: WARNING - Both buffers unavailable at time %0t", $time);
    end
  end
end

endmodule
