
`timescale 1ns / 1ps

module gemma_accelerator #(
  parameter integer ID_WIDTH = 12,
  parameter integer BUFFER_DEPTH = 20,
  parameter integer BUFFER_ADDR_WIDTH = $clog2(BUFFER_DEPTH),
  parameter integer SYSTOLIC_SIZE = 16,
  parameter integer DATA_WIDTH = 8,
  parameter integer ACCUM_WIDTH = 32
)(
  input  wire                  ap_clk,
  input  wire                  ap_rst_n,
  // AXI-Lite Control Interface
  input  wire                  s_axi_control_awvalid,
  output wire                  s_axi_control_awready,
  input  wire [7:0]            s_axi_control_awaddr,
  input  wire                  s_axi_control_wvalid,
  output wire                  s_axi_control_wready,
  input  wire [31:0]           s_axi_control_wdata,
  input  wire [3:0]            s_axi_control_wstrb,
  output reg                   s_axi_control_bvalid,
  input  wire                  s_axi_control_bready,
  output wire [1:0]            s_axi_control_bresp,
  input  wire [0:0]            s_axi_control_awid,
  output wire [0:0]            s_axi_control_bid,
  input  wire                  s_axi_control_arvalid,
  output wire                  s_axi_control_arready,
  input  wire [7:0]            s_axi_control_araddr,
  output reg                   s_axi_control_rvalid,
  input  wire                  s_axi_control_rready,
  output reg  [31:0]           s_axi_control_rdata,
  output wire [1:0]            s_axi_control_rresp,
  input  wire [0:0]            s_axi_control_arid,
  output wire [0:0]            s_axi_control_rid,

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
  localparam [3:0]
    S_IDLE             = 4'd0,
    S_FETCH_ACT_ADDR   = 4'd1,
    S_FETCH_ACT_DATA   = 4'd2,
    S_FETCH_WGT_ADDR   = 4'd3,
    S_FETCH_WGT_DATA   = 4'd4,
    S_SYSTOLIC_COMPUTE = 4'd5,
    S_WRITE_OUT_ADDR   = 4'd6,
    S_WRITE_OUT_DATA   = 4'd7,
    S_WAIT_WRITE_END   = 4'd8,
    S_DONE             = 4'd9,
    S_CHAIN_NEXT_TILE  = 4'd10,
    S_CHAIN_UPDATE_ADDR = 4'd11;

// Systolic array timing constants
localparam [7:0]
  SYSTOLIC_LATENCY = 8'd124,  // Original working timing
  PACK_CYCLE = 8'd122;        // When to pack results (2 cycles before completion)

localparam [7:0]
  // existing control/status + pointers
  ADDR_CTRL   = 8'h00,  ADDR_STATUS = 8'h00,
  A_LSB       = 8'h10,  A_MSB       = 8'h14,
  B_LSB       = 8'h1C,  B_MSB       = 8'h20,
  C_LSB       = 8'h28,  C_MSB       = 8'h2C,

  // compact debug window
  DBG_BUF_INDEX   = 8'h30,  // write: select which buffer line to peek
  DBG_BUF_DATA_LS = 8'h34,  // read:  act_buf_rd_data[31:0]   (or a chosen slice)
  DBG_BUF_DATA_MS = 8'h38,  // read:  act_buf_rd_data[63:32]
  DBG_AXI_RDATA0  = 8'h3C,  // read:  debug_last_rdata[31:0]
  DBG_AXI_RDATA1  = 8'h40,  // read:  debug_last_rdata[63:32]
  DBG_AXI_RDATA2  = 8'h44,  // read:  debug_last_rdata[95:64]
  DBG_AXI_RDATA3  = 8'h48,  // read:  debug_last_rdata[127:96]
  DBG_AXI_ADDR    = 8'h4C,  // read:  debug_last_addr
  DBG_AXI_BEAT    = 8'h50,  // read:  {24'd0, debug_beat_count}

  // Matrix chaining control registers
  ACT_BASE_LSB    = 8'h60,  // Activation base address [31:0]
  ACT_BASE_MSB    = 8'h64,  // Activation base address [63:32]
  WGT_BASE_LSB    = 8'h68,  // Weight base address [31:0]
  WGT_BASE_MSB    = 8'h6C,  // Weight base address [63:32]
  OUT_BASE_LSB    = 8'h70,  // Output base address [31:0]
  OUT_BASE_MSB    = 8'h74,  // Output base address [63:32]
  MATRIX_DIMS     = 8'h78,  // {total_cols[15:0], total_rows[15:0]}
  TILE_POS        = 8'h7C,  // {current_tile_col[15:0], current_tile_row[15:0]}
  CHAIN_CTRL      = 8'h80,  // {31'b0, chain_mode_en}
  CHAIN_STATUS    = 8'h84;  // {30'b0, chain_complete, chain_active}


  reg [3:0]   current_state, next_state;
  reg [7:0]   beat_counter;
  reg [63:0]  addr_a_reg, addr_b_reg, addr_c_reg;
  reg         start_pulse;
  reg         accelerator_done;  // FIXED: Add done signal

  // Matrix chaining control registers
  reg [63:0]  act_base_addr;     // Base address for activation matrices
  reg [63:0]  wgt_base_addr;     // Base address for weight matrices
  reg [63:0]  out_base_addr;     // Base address for output matrices
  reg [15:0]  total_rows;        // Total rows in large matrix
  reg [15:0]  total_cols;        // Total cols in large matrix
  reg [15:0]  current_tile_row;  // Current output tile position (row)
  reg [15:0]  current_tile_col;  // Current output tile position (col)
  reg [15:0]  current_inner_k;   // Current inner dimension tile for accumulation
  reg         chain_mode_en;     // Enable autonomous chaining mode

  // Matrix chaining logic signals
  reg [15:0]  tiles_per_row;     // Number of tiles per matrix row
  reg [15:0]  tiles_per_col;     // Number of tiles per matrix column
  reg [15:0]  tiles_per_inner;   // Number of tiles per inner dimension (same as matrix size / 16)
  reg [63:0]  current_act_addr;  // Current activation tile address
  reg [63:0]  current_wgt_addr;  // Current weight tile address
  reg [63:0]  current_out_addr;  // Current output tile address
  reg         chain_complete;    // All tiles processed
  reg         chain_active;      // Matrix chaining operation active
  reg [7:0]   s_axi_control_araddr_latched;  // Latched read address for proper AXI-Lite read response

  // Duplicate fetch prevention
  reg [15:0]  last_fetched_tile_row;  // Last fetched tile row
  reg [15:0]  last_fetched_tile_col;  // Last fetched tile column
  reg [15:0]  last_fetched_inner_k;   // Last fetched inner_k
  reg         fetch_in_progress;      // Fetch currently in progress

  // Calculate tiles per row/column (each tile is 16x16)
  always @(*) begin
    tiles_per_row = (total_rows + 15) >> 4;  // Ceiling division by 16
    tiles_per_col = (total_cols + 15) >> 4;  // Ceiling division by 16
    tiles_per_inner = (total_cols + 15) >> 4; // Inner dimension same as cols
  end

  // Matrix chaining completion is now managed in the FSM logic

  // Address generation logic for current tile
  always @(*) begin
    if (chain_mode_en) begin
      // Calculate byte offsets for current tile position
      // FIXED: Proper matrix multiplication addressing
      // Activation: A[tile_row, inner_k] - rows from output, cols from inner dimension
      // Address = base + (tile_row * 16 * matrix_width) + (inner_k * 16) [BYTE ADDRESSING]
      current_act_addr = act_base_addr +
                        (current_tile_row * 16 * total_cols) +
                        (current_inner_k * 16 * 16);
      // DEBUG: Address calculation breakdown

      // Weight: B[inner_k, tile_col] - rows from inner dimension, cols from output
      // Address = base + (inner_k * 16 * matrix_width) + (tile_col * 256) [BYTE ADDRESSING]
      // Fixed: Use 256-byte spacing between tiles to avoid AXI read overlap
      current_wgt_addr = wgt_base_addr +
                        (current_inner_k * 16 * total_cols) +
                        (current_tile_col * 256);
      // Output: C[tile_row, tile_col] - SAME for all inner_k accumulations
      // Address = base + (tile_row * 16 * matrix_width * 4) + (tile_col * 16 * 4) [KEEP 4-BYTE FOR 32-BIT OUTPUT]
      current_out_addr = out_base_addr +
                        (current_tile_row * 16 * total_cols * 4) +
                        (current_tile_col * 16 * 4);
    end else begin
      // Use single-tile addresses from registers
      current_act_addr = addr_a_reg;
      current_wgt_addr = addr_b_reg;
      current_out_addr = addr_c_reg;
    end
  end

  // Double buffering control signals (for input buffers)
  reg         buffer_select;       // 0: use ping buffers, 1: use pong buffers
  reg         next_buffer_select;  // Buffer to use for next tile load
  reg         buffer_switched;     // Flag to prevent multiple switches per cycle

  // AXI-Lite write buffer
  reg         awvalid_seen, wvalid_seen;
  reg [7:0]   awaddr_latched;
  reg [31:0]  wdata_latched;

  // Loop variables for initializations
  integer buf_i;
  integer mux_i;
  integer skew_i;



  // Double buffer control signals for activation buffers (ping-pong)
  reg                           act_buf_ping_wr_en, act_buf_pong_wr_en;
  reg [BUFFER_ADDR_WIDTH-1:0]   act_buf_ping_wr_addr, act_buf_pong_wr_addr;
  reg [127:0]                   act_buf_ping_wr_data, act_buf_pong_wr_data;
  reg [BUFFER_ADDR_WIDTH-1:0]   act_buf_ping_rd_addr, act_buf_pong_rd_addr;
  wire [127:0]                  act_buf_ping_rd_data, act_buf_pong_rd_data;

  // Double buffer control signals for weight buffers (ping-pong)
  reg                           wgt_buf_ping_wr_en, wgt_buf_pong_wr_en;
  reg [BUFFER_ADDR_WIDTH-1:0]   wgt_buf_ping_wr_addr, wgt_buf_pong_wr_addr;
  reg [127:0]                   wgt_buf_ping_wr_data, wgt_buf_pong_wr_data;
  reg [BUFFER_ADDR_WIDTH-1:0]   wgt_buf_ping_rd_addr, wgt_buf_pong_rd_addr;
  wire [127:0]                  wgt_buf_ping_rd_data, wgt_buf_pong_rd_data;

  // Unified buffer access signals (muxed based on buffer_select)
  wire [127:0]                  act_buf_rd_data;
  wire [127:0]                  wgt_buf_rd_data;

  // Matrix data storage - unpacked from buffers for easier indexing
  reg signed [DATA_WIDTH-1:0]   activation_matrix [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1];
  reg signed [DATA_WIDTH-1:0]   weight_matrix [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1];

  // Systolic Array signals
  reg                           systolic_accum_reset;
  reg signed [DATA_WIDTH-1:0]   systolic_north_inputs [0:SYSTOLIC_SIZE-1];
  reg signed [DATA_WIDTH-1:0]   systolic_west_inputs [0:SYSTOLIC_SIZE-1];
  reg [SYSTOLIC_SIZE-1:0]       systolic_north_valid;
  reg [SYSTOLIC_SIZE-1:0]       systolic_west_valid;
  wire signed [SYSTOLIC_SIZE*SYSTOLIC_SIZE*ACCUM_WIDTH-1:0] systolic_results;

  // FIXED: Separate counters for proper timing control
  reg [7:0]                     systolic_cycle_count;
  reg [7:0]                     input_cycle_count;
  reg                           systolic_computing;
  reg                           matrices_loaded;
  reg                           activation_loaded;
  reg                           weight_loaded;

  // Result management
  reg signed [ACCUM_WIDTH-1:0]  result_matrix [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1];

  // Double buffer control signals for output buffers (ping-pong)
  reg [127:0]                   output_buf_ping [0:63];
  reg [127:0]                   output_buf_pong [0:63];
  reg                           output_buffer_select;     // 0: ping for write, 1: pong for write
  reg                           output_next_buffer_select; // Buffer to use for next output
  reg                           output_buffer_switched;   // Flag to prevent multiple switches
  reg                           read_buffer_select;       // Buffer to read from (captured at computation end)

  // Unified output buffer access (muxed based on output_buffer_select)
  reg [127:0]                   output_data_buffer [0:63]; // For computation writes
  reg [127:0]                   write_staging_buffer [0:63]; // For AXI writes

  reg [5:0]                     output_buffer_idx;
  reg                           capture_results;

  // Debug registers for AXI transaction analysis
  reg [127:0] debug_last_rdata;
  reg [7:0]   debug_beat_count;
  reg [31:0]  debug_last_addr;

  // Debug
  reg [31:0] debug_buffer_index;

// --- Write engine regs (new) ---
reg        wvalid_reg, wlast_reg;
reg [7:0]  wr_idx;
reg [127:0] wdata_reg;
reg [15:0]  wstrb_reg;

  // derive word-aligned addresses (byte addr -> zero low 2 bits)
wire [7:0] awaddr_word = {awaddr_latched[7:2], 2'b00};

  // Merge function to handle byte-wise writes
  function [31:0] merge_by_wstrb;
    input [31:0] oldw;
    input [31:0] neww;
    input [3:0]  wstrb;
    begin
      merge_by_wstrb = oldw;
      if (wstrb[0]) merge_by_wstrb[ 7: 0] = neww[ 7: 0];
      if (wstrb[1]) merge_by_wstrb[15: 8] = neww[15: 8];
      if (wstrb[2]) merge_by_wstrb[23:16] = neww[23:16];
      if (wstrb[3]) merge_by_wstrb[31:24] = neww[31:24];
    end
  endfunction
wire state_enter_write_data = (current_state == S_WRITE_OUT_ADDR) && m_axi_gmem_awready;

reg [7:0]   wbeats_sent;     // Debug counter for AXI write beats
reg [7:0]   debug_wbeats_sent; // Snapshot for debug reading

// Replace the existing write engine registers and logic:
// Remove the old write engine regs (wvalid_reg, wlast_reg, wr_idx, wdata_reg, wstrb_reg)
// Replace with this improved version:

reg         write_active;
reg [7:0]   write_beat_count;
reg [127:0] write_data_reg;
reg         write_last_reg;

  // Instantiate ping activation buffer (INT8, 128-bit width)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) activation_buffer_ping (
    .clk(ap_clk),
    .wr_en(act_buf_ping_wr_en),
    .wr_addr(act_buf_ping_wr_addr),
    .wr_data(act_buf_ping_wr_data),
    .rd_addr(act_buf_ping_rd_addr),
    .rd_data(act_buf_ping_rd_data)
  );

  // Instantiate pong activation buffer (INT8, 128-bit width)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) activation_buffer_pong (
    .clk(ap_clk),
    .wr_en(act_buf_pong_wr_en),
    .wr_addr(act_buf_pong_wr_addr),
    .wr_data(act_buf_pong_wr_data),
    .rd_addr(act_buf_pong_rd_addr),
    .rd_data(act_buf_pong_rd_data)
  );

  // Instantiate ping weight buffer (INT8, 128-bit width)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) weight_buffer_ping (
    .clk(ap_clk),
    .wr_en(wgt_buf_ping_wr_en),
    .wr_addr(wgt_buf_ping_wr_addr),
    .wr_data(wgt_buf_ping_wr_data),
    .rd_addr(wgt_buf_ping_rd_addr),
    .rd_data(wgt_buf_ping_rd_data)
  );

  // Instantiate pong weight buffer (INT8, 128-bit width)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) weight_buffer_pong (
    .clk(ap_clk),
    .wr_en(wgt_buf_pong_wr_en),
    .wr_addr(wgt_buf_pong_wr_addr),
    .wr_data(wgt_buf_pong_wr_data),
    .rd_addr(wgt_buf_pong_rd_addr),
    .rd_data(wgt_buf_pong_rd_data)
  );

  // Buffer selection multiplexers for read data
  assign act_buf_rd_data = buffer_select ? act_buf_pong_rd_data : act_buf_ping_rd_data;
  assign wgt_buf_rd_data = buffer_select ? wgt_buf_pong_rd_data : wgt_buf_ping_rd_data;

  // Pack systolic inputs for module interface
  wire signed [SYSTOLIC_SIZE*DATA_WIDTH-1:0] systolic_north_packed;
  wire signed [SYSTOLIC_SIZE*DATA_WIDTH-1:0] systolic_west_packed;

  genvar g;
  generate
    for (g = 0; g < SYSTOLIC_SIZE; g = g + 1) begin : pack_inputs
      assign systolic_north_packed[(g+1)*DATA_WIDTH-1:g*DATA_WIDTH] = systolic_north_inputs[g];
      assign systolic_west_packed[(g+1)*DATA_WIDTH-1:g*DATA_WIDTH] = systolic_west_inputs[g];
    end
  endgenerate

  // Systolic Array instantiation with valid signals
  systolic_array_16x16 #(
    .SIZE(SYSTOLIC_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACCUM_WIDTH(ACCUM_WIDTH)
  ) systolic_array_inst (
    .clk(ap_clk),
    .rst(~ap_rst_n),
    .accum_reset(systolic_accum_reset),
    .north_inputs(systolic_north_packed),
    .west_inputs(systolic_west_packed),
    .north_valid(systolic_north_valid),
    .west_valid(systolic_west_valid),
    .result_matrix(systolic_results)
  );

  // FIXED: State machine and counters with proper timing
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      current_state <= S_IDLE;
      beat_counter <= 8'd0;
      systolic_cycle_count <= 8'd0;
      input_cycle_count <= 8'd0;
      output_buffer_idx <= 6'd0;
      systolic_computing <= 1'b0;
      capture_results <= 1'b0;
      output_buffer_select <= 1'b0;
      output_next_buffer_select <= 1'b1;
      output_buffer_switched <= 1'b0;
      matrices_loaded <= 1'b0;
      activation_loaded <= 1'b0;
      weight_loaded <= 1'b0;
      accelerator_done <= 1'b0;  // FIXED: Initialize done flag

      // Initialize double buffering control
      buffer_select <= 1'b0;
      next_buffer_select <= 1'b1;
      buffer_switched <= 1'b0;

      // Initialize output buffers to zero
      for (buf_i = 0; buf_i < 64; buf_i = buf_i + 1) begin
        output_buf_ping[buf_i] <= 128'b0;
        output_buf_pong[buf_i] <= 128'b0;
      end

      // Initialize debug registers
      debug_last_rdata <= 128'd0;
      debug_beat_count <= 8'd0;
      debug_last_addr <= 32'd0;
      chain_complete <= 1'b0;
      chain_active <= 1'b0;
    end else begin
      current_state <= next_state;

      // Handle tile stepping for matrix chaining - 3-level nested loop
      if (current_state == S_CHAIN_NEXT_TILE) begin
        if (current_inner_k < tiles_per_inner - 1) begin
          // Move to next inner dimension for same output tile
          current_inner_k <= current_inner_k + 1;
        end else if (current_tile_col < tiles_per_col - 1) begin
          // Move to next column in same row, reset inner k
          current_inner_k <= 16'd0;
          current_tile_col <= current_tile_col + 1;
        end else begin
          // Move to first column of next row, reset inner k
          current_inner_k <= 16'd0;
          current_tile_col <= 16'd0;
          current_tile_row <= current_tile_row + 1;
        end
      end



      // Beat counter management
      if ((current_state == S_FETCH_ACT_ADDR && m_axi_gmem_arready) ||
          (current_state == S_FETCH_WGT_ADDR && m_axi_gmem_arready) ||
          (current_state == S_WRITE_OUT_ADDR && m_axi_gmem_awready))
        beat_counter <= 8'd0;
      else if ((current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
               (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) ||
               (current_state == S_WRITE_OUT_DATA && m_axi_gmem_wvalid && m_axi_gmem_wready))
        beat_counter <= beat_counter + 1'b1;

      // FIXED: Matrix loading status tracking
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast) begin
        activation_loaded <= 1'b1;
        // Record successful fetch to prevent duplicates
        last_fetched_tile_row <= current_tile_row;
        last_fetched_tile_col <= current_tile_col;
        last_fetched_inner_k <= current_inner_k;
      end else if (current_state == S_IDLE) begin
        activation_loaded <= 1'b0;
      end

      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
        weight_loaded <= 1'b1;
      else if (current_state == S_IDLE) begin
        weight_loaded <= 1'b0;
        // Reset fetch tracking when starting new operation
        last_fetched_tile_row <= 16'hFFFF;
        last_fetched_tile_col <= 16'hFFFF;
        last_fetched_inner_k <= 16'hFFFF;
      end

      // Both matrices loaded - give one extra cycle for stabilization
      matrices_loaded <= activation_loaded && weight_loaded;

      // Swap buffers when transitioning to computation state - this allows next tile to be loaded
      // into the other buffer while current computation is running
      if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd0 && !buffer_switched) begin
        buffer_select <= next_buffer_select;
        next_buffer_select <= ~next_buffer_select;
        buffer_switched <= 1'b1;
      end

      // Reset buffer switch flag when leaving compute state
      if (current_state != S_SYSTOLIC_COMPUTE) begin
        buffer_switched <= 1'b0;
      end

      // FIXED: Done flag management
      if (current_state == S_DONE)
        accelerator_done <= 1'b1;
      else if (start_pulse)  // Clear done when starting new computation
        accelerator_done <= 1'b0;

      // FIXED: Chain completion tracking
      if (current_state == S_WAIT_WRITE_END && m_axi_gmem_bvalid && m_axi_gmem_bready && chain_mode_en) begin
        if (current_inner_k >= tiles_per_inner - 1 &&
            current_tile_col >= tiles_per_col - 1 &&
            current_tile_row >= tiles_per_row - 1) begin
          chain_complete <= 1'b1;
          chain_active <= 1'b0;
        end
      end

if (current_state == S_SYSTOLIC_COMPUTE) begin
  systolic_cycle_count <= systolic_cycle_count + 1'b1;

  if (matrices_loaded) begin
    systolic_computing <= 1'b1;
    input_cycle_count  <= input_cycle_count + 1'b1;
  end else begin
    systolic_computing <= 1'b0;
    input_cycle_count  <= 8'd0;
  end
end else begin
  systolic_computing     <= 1'b0;
  systolic_cycle_count   <= 8'd0;
  input_cycle_count      <= 8'd0;
  capture_results        <= 1'b0;
end

      // Output buffer management
      if (current_state == S_WRITE_OUT_DATA && m_axi_gmem_wvalid && m_axi_gmem_wready) begin
        if (output_buffer_idx < 6'd63)
          output_buffer_idx <= output_buffer_idx + 1'b1;
      end else if (current_state == S_IDLE) begin
        output_buffer_idx <= 6'd0;
      end
    end
  end

  // Matrix unpacking from buffers
  integer unpack_i, unpack_j;
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      for (unpack_i = 0; unpack_i < SYSTOLIC_SIZE; unpack_i = unpack_i + 1) begin
        for (unpack_j = 0; unpack_j < SYSTOLIC_SIZE; unpack_j = unpack_j + 1) begin
          activation_matrix[unpack_i][unpack_j] <= 8'd0;
          weight_matrix[unpack_i][unpack_j] <= 8'd0;
        end
      end
    end else begin
      // Unpack activation matrix when loading completes
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        // Debug input data unpacking
        // Process first beat of activation data
        if (beat_counter == 8'd0) begin
          // Store activation data for computation
        end
        // Capture AXI transaction details for debug
        debug_last_rdata <= m_axi_gmem_rdata;
        debug_beat_count <= beat_counter;
        debug_last_addr <= current_act_addr[31:0];

        activation_matrix[beat_counter][0]  <= $signed(m_axi_gmem_rdata[7:0]);
        activation_matrix[beat_counter][1]  <= $signed(m_axi_gmem_rdata[15:8]);
        activation_matrix[beat_counter][2]  <= $signed(m_axi_gmem_rdata[23:16]);
        activation_matrix[beat_counter][3]  <= $signed(m_axi_gmem_rdata[31:24]);
        activation_matrix[beat_counter][4]  <= $signed(m_axi_gmem_rdata[39:32]);
        activation_matrix[beat_counter][5]  <= $signed(m_axi_gmem_rdata[47:40]);
        activation_matrix[beat_counter][6]  <= $signed(m_axi_gmem_rdata[55:48]);
        activation_matrix[beat_counter][7]  <= $signed(m_axi_gmem_rdata[63:56]);
        activation_matrix[beat_counter][8]  <= $signed(m_axi_gmem_rdata[71:64]);
        activation_matrix[beat_counter][9]  <= $signed(m_axi_gmem_rdata[79:72]);
        activation_matrix[beat_counter][10] <= $signed(m_axi_gmem_rdata[87:80]);
        activation_matrix[beat_counter][11] <= $signed(m_axi_gmem_rdata[95:88]);
        activation_matrix[beat_counter][12] <= $signed(m_axi_gmem_rdata[103:96]);
        activation_matrix[beat_counter][13] <= $signed(m_axi_gmem_rdata[111:104]);
        activation_matrix[beat_counter][14] <= $signed(m_axi_gmem_rdata[119:112]);
        activation_matrix[beat_counter][15] <= $signed(m_axi_gmem_rdata[127:120]);

        // Minimal debug for activation matrix loading
        if (beat_counter == 0 && current_tile_row == 0 && current_tile_col == 0) begin
          // First beat loaded
        end
      end

      // Unpack weight matrix when loading completes
      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        // Debug weight data unpacking
        // Process first beat of weight data
        if (beat_counter == 8'd0) begin
          // Store weight data for computation
        end
        // FIXED: Weight matrix is stored column-wise in memory, so unpack accordingly
        // Memory data contains B[0:15][beat_counter] (column data)
        weight_matrix[0][beat_counter]  <= $signed(m_axi_gmem_rdata[7:0]);    // B[0][beat_counter]
        weight_matrix[1][beat_counter]  <= $signed(m_axi_gmem_rdata[15:8]);   // B[1][beat_counter]
        weight_matrix[2][beat_counter]  <= $signed(m_axi_gmem_rdata[23:16]);  // B[2][beat_counter]
        weight_matrix[3][beat_counter]  <= $signed(m_axi_gmem_rdata[31:24]);  // B[3][beat_counter]
        weight_matrix[4][beat_counter]  <= $signed(m_axi_gmem_rdata[39:32]);  // B[4][beat_counter]
        weight_matrix[5][beat_counter]  <= $signed(m_axi_gmem_rdata[47:40]);  // B[5][beat_counter]
        weight_matrix[6][beat_counter]  <= $signed(m_axi_gmem_rdata[55:48]);  // B[6][beat_counter]
        weight_matrix[7][beat_counter]  <= $signed(m_axi_gmem_rdata[63:56]);  // B[7][beat_counter]
        weight_matrix[8][beat_counter]  <= $signed(m_axi_gmem_rdata[71:64]);  // B[8][beat_counter]
        weight_matrix[9][beat_counter]  <= $signed(m_axi_gmem_rdata[79:72]);  // B[9][beat_counter]
        weight_matrix[10][beat_counter] <= $signed(m_axi_gmem_rdata[87:80]);  // B[10][beat_counter]
        weight_matrix[11][beat_counter] <= $signed(m_axi_gmem_rdata[95:88]);  // B[11][beat_counter]
        weight_matrix[12][beat_counter] <= $signed(m_axi_gmem_rdata[103:96]); // B[12][beat_counter]
        weight_matrix[13][beat_counter] <= $signed(m_axi_gmem_rdata[111:104]);// B[13][beat_counter]
        weight_matrix[14][beat_counter] <= $signed(m_axi_gmem_rdata[119:112]);// B[14][beat_counter]
        weight_matrix[15][beat_counter] <= $signed(m_axi_gmem_rdata[127:120]);// B[15][beat_counter]
      end
    end
  end

  // Double buffer control logic with ping-pong operation
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      // Initialize ping buffer controls
      act_buf_ping_wr_en    <= 1'b0;
      act_buf_ping_wr_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      act_buf_ping_wr_data  <= 128'd0;
      act_buf_ping_rd_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_ping_wr_en    <= 1'b0;
      wgt_buf_ping_wr_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_ping_wr_data  <= 128'd0;
      wgt_buf_ping_rd_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};

      // Initialize pong buffer controls
      act_buf_pong_wr_en    <= 1'b0;
      act_buf_pong_wr_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      act_buf_pong_wr_data  <= 128'd0;
      act_buf_pong_rd_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_pong_wr_en    <= 1'b0;
      wgt_buf_pong_wr_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_pong_wr_data  <= 128'd0;
      wgt_buf_pong_rd_addr  <= {BUFFER_ADDR_WIDTH{1'b0}};
    end else begin
      // Default values - disable all write enables
      act_buf_ping_wr_en <= 1'b0;
      act_buf_pong_wr_en <= 1'b0;
      wgt_buf_ping_wr_en <= 1'b0;
      wgt_buf_pong_wr_en <= 1'b0;

      // Load activation data into the buffer selected by next_buffer_select
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        if (next_buffer_select) begin
          // Load into pong buffer
          act_buf_pong_wr_en   <= 1'b1;
          act_buf_pong_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
          act_buf_pong_wr_data <= m_axi_gmem_rdata;
        end else begin
          // Load into ping buffer
          act_buf_ping_wr_en   <= 1'b1;
          act_buf_ping_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
          act_buf_ping_wr_data <= m_axi_gmem_rdata;
        end
      end

      // Load weight data into the buffer selected by next_buffer_select
      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        if (next_buffer_select) begin
          // Load into pong buffer
          wgt_buf_pong_wr_en   <= 1'b1;
          wgt_buf_pong_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
          wgt_buf_pong_wr_data <= m_axi_gmem_rdata;
        end else begin
          // Load into ping buffer
          wgt_buf_ping_wr_en   <= 1'b1;
          wgt_buf_ping_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
          wgt_buf_ping_wr_data <= m_axi_gmem_rdata;
        end
      end

      // Update read addresses for currently active buffer (based on buffer_select)
      if (buffer_select) begin
        // Using pong buffers for read
        act_buf_pong_rd_addr <= debug_buffer_index[BUFFER_ADDR_WIDTH-1:0];
        wgt_buf_pong_rd_addr <= debug_buffer_index[BUFFER_ADDR_WIDTH-1:0];
      end else begin
        // Using ping buffers for read
        act_buf_ping_rd_addr <= debug_buffer_index[BUFFER_ADDR_WIDTH-1:0];
        wgt_buf_ping_rd_addr <= debug_buffer_index[BUFFER_ADDR_WIDTH-1:0];
      end
    end
  end

  // Output buffer ping-pong control logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      output_buffer_select <= 1'b0;
      output_next_buffer_select <= 1'b1;
      output_buffer_switched <= 1'b0;
      read_buffer_select <= 1'b0;
    end else begin
      // Capture which buffer to read when computation completes
      // Read from the buffer that was just written to (opposite of next buffer)
      if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count >= SYSTOLIC_LATENCY) begin
        read_buffer_select <= ~output_next_buffer_select;
        // Reduced buffer debug
      end

      // FIXED: Switch output buffers only after completing all inner_k iterations for an output tile
      if (current_state == S_WRITE_OUT_ADDR && !output_buffer_switched &&
          current_inner_k == tiles_per_inner - 1) begin
        output_buffer_select <= output_next_buffer_select;
        output_next_buffer_select <= ~output_next_buffer_select;
        output_buffer_switched <= 1'b1;
        // Buffer switch complete
      end

      // Reset buffer switch flag when leaving write states
      if (current_state != S_WRITE_OUT_ADDR && current_state != S_WRITE_OUT_DATA) begin
        output_buffer_switched <= 1'b0;
      end
    end
  end

  // Output buffer multiplexer - select which buffer to use for AXI writes
  always @(*) begin
    for (mux_i = 0; mux_i < 64; mux_i = mux_i + 1) begin
      if (read_buffer_select) begin
        output_data_buffer[mux_i] = output_buf_pong[mux_i];
      end else begin
        output_data_buffer[mux_i] = output_buf_ping[mux_i];
      end
    end

    if (current_state == S_WRITE_OUT_ADDR) begin
      // Debug output buffer selection
    end
  end

  // Synchronous clear of all PE accumulators at the start of SYSTOLIC
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      systolic_accum_reset <= 1'b1;
    end else begin
      // FIXED: Reset accumulator only at start of systolic computation for new output tile
      if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd0 &&
          current_inner_k == 16'd0) begin
        systolic_accum_reset <= 1'b1;
        // Debug: Reset accumulator for new output tile
      end else begin
        systolic_accum_reset <= 1'b0;
        // Debug: Show when accumulators are NOT being reset during computation
        if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd0 && current_inner_k > 16'd0) begin
          // Debug: Accumulator not reset for inner_k continuation
        end
      end

      // Debug systolic array processing cycles
      if (current_state == S_SYSTOLIC_COMPUTE) begin
        if (systolic_cycle_count % 20 == 0 || systolic_cycle_count < 5 || systolic_cycle_count > 120) begin
          // Debug: Systolic computation progress
        end
      end

      // Reduced systolic debug output
    end
  end

  // FIXED: Systolic array input generation with VALID SIGNAL CONTROL
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      for (skew_i = 0; skew_i < SYSTOLIC_SIZE; skew_i = skew_i + 1) begin
        systolic_north_inputs[skew_i] <= 8'd0;
        systolic_west_inputs[skew_i] <= 8'd0;
      end
      systolic_north_valid <= {SYSTOLIC_SIZE{1'b0}};
      systolic_west_valid <= {SYSTOLIC_SIZE{1'b0}};
    end else if (current_state == S_SYSTOLIC_COMPUTE && matrices_loaded && systolic_computing) begin
      // Matrix data ready for systolic computation

      for (skew_i = 0; skew_i < SYSTOLIC_SIZE; skew_i = skew_i + 1) begin
        if (input_cycle_count >= (skew_i + 1) && (input_cycle_count - skew_i - 1) < SYSTOLIC_SIZE) begin
          // Restored proper systolic skewing with correct data flow
          // North: Each column gets B[k][col] with skewing for pipeline alignment
          systolic_north_inputs[skew_i] <= weight_matrix[input_cycle_count - skew_i - 1][skew_i];
          // West: Each row gets A[row][k] with skewing for pipeline alignment
          systolic_west_inputs[skew_i] <= activation_matrix[skew_i][input_cycle_count - skew_i - 1];
          systolic_north_valid[skew_i] <= 1'b1;
          systolic_west_valid[skew_i] <= 1'b1;

          // DEBUG: Show input data for first few cycles of first tile
          if (current_tile_row == 0 && current_tile_col == 0 && input_cycle_count < 4) begin
            if (skew_i == 0 || skew_i == 1) begin
              $display("SYSTOLIC_DEBUG[%0d]: PE[0][%0d] cycle=%0d north=%0d west=%0d k_idx=%0d", 
                       $time, skew_i, input_cycle_count, 
                       weight_matrix[input_cycle_count - skew_i - 1][skew_i],
                       activation_matrix[skew_i][input_cycle_count - skew_i - 1],
                       input_cycle_count - skew_i - 1);
              // Additional debug: Show matrix values being accessed
              if (skew_i == 1 && input_cycle_count == 2) begin
                $display("MATRIX_DEBUG[%0d]: weight_matrix[0][1]=%0d activation_matrix[1][0]=%0d", 
                         $time, weight_matrix[0][1], activation_matrix[1][0]);
                $display("MATRIX_DEBUG[%0d]: Expected: B[0][1]=%0d A[1][0]=%0d", 
                         $time, 2, 2);
              end
            end
          end

        end else begin
          systolic_north_inputs[skew_i] <= 8'd0;
          systolic_west_inputs[skew_i] <= 8'd0;
          systolic_north_valid[skew_i] <= 1'b0;
          systolic_west_valid[skew_i] <= 1'b0;
        end
      end
    end else begin
      for (skew_i = 0; skew_i < SYSTOLIC_SIZE; skew_i = skew_i + 1) begin
        systolic_north_inputs[skew_i] <= 8'd0;
        systolic_west_inputs[skew_i] <= 8'd0;
      end
      systolic_north_valid <= {SYSTOLIC_SIZE{1'b0}};
      systolic_west_valid <= {SYSTOLIC_SIZE{1'b0}};
    end
  end

  // // Result capture and output buffer preparation
  // integer i, j;
  // always @(posedge ap_clk) begin
  //   if (!ap_rst_n) begin
  //     for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
  //       for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
  //         result_matrix[i][j] <= {ACCUM_WIDTH{1'b0}};
  //       end
  //     end
  //     for (i = 0; i < 64; i = i + 1) begin
  //       output_data_buffer[i] <= 128'd0;
  //     end
  //   end else begin
  //     // Capture results when computation is complete
  //     if (capture_results && systolic_cycle_count == 8'd49) begin
  //       for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
  //         for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
  //           result_matrix[i][j] <= systolic_results[(i*SYSTOLIC_SIZE + j + 1)*ACCUM_WIDTH - 1 -: ACCUM_WIDTH];
  //         end
  //       end
  //     end

  //     // Prepare output data buffer - pack 4×32-bit values per 128-bit word
  //     if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd50) begin
  //       for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
  //         for (j = 0; j < SYSTOLIC_SIZE; j = j + 4) begin
  //           buf_idx = i * 4 + j/4;
  //           output_data_buffer[buf_idx] <= {
  //             result_matrix[i][j+3],
  //             result_matrix[i][j+2],
  //             result_matrix[i][j+1],
  //             result_matrix[i][j+0]
  //           };
  //         end
  //       end
  //     end
  //   end
  // end

  // Result capture and output buffer preparation
integer i, j, buf_idx;
always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
      for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
        result_matrix[i][j] <= {ACCUM_WIDTH{1'b0}};
      end
    end
  end else begin
    // 1) CAPTURE: wait for systolic array computation to complete (2*SYSTOLIC_SIZE + settling)
    // FIXED: Only capture results after final inner_k iteration for this output tile
    if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd120) begin
      if (chain_mode_en) begin
        // Chaining mode: only capture on final inner_k iteration
        if (current_inner_k == tiles_per_inner - 1) begin
          capture_results <= 1'b1;
        end else begin
          capture_results <= 1'b0;
        end
      end else begin
        // Single-tile mode: always capture
        capture_results <= 1'b1;
      end
    end

    if (capture_results && current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd121) begin
      for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
        for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
          // Fix: Use correct bit slicing without +1 offset
          result_matrix[i][j] <= systolic_results[(i*SYSTOLIC_SIZE + j)*ACCUM_WIDTH +: ACCUM_WIDTH];

          // FIXED: Debug final accumulated results
          if (i == 0 && j == 0) begin
            // Debug: Final result for position (0,0)
            
            // Debug: Compare with expected value (simplified calculation)
            if (current_tile_row == 0 && current_tile_col == 0) begin
              if (current_inner_k == 0) begin
              end else begin
              end
            end
          end
          if (i == 0 && j == 1) begin
            // Debug: Final result for position (0,1)
          end
          if (i == 1 && j == 0) begin
            // Debug: Final result for position (1,0)
          end
          if (i == 1 && j == 1) begin
            // Debug: Final result for position (1,1)
          end
        end
      end
    end

    // 2) PACK: copy result_matrix -> output buffers (ping-pong)
    // FIXED: Pack for both single-tile and chaining modes
    if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == PACK_CYCLE) begin
      if ((chain_mode_en && current_inner_k == tiles_per_inner - 1) || !chain_mode_en) begin
        for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
          for (j = 0; j < SYSTOLIC_SIZE; j = j + 4) begin
            buf_idx = i * 4 + j/4;
            if (output_buffer_select) begin
              output_buf_pong[buf_idx] <= {
                result_matrix[i][j+3],
                result_matrix[i][j+2],
                result_matrix[i][j+1],
                result_matrix[i][j]
              };
              if (i == 0 && j == 0) begin
                // Debug: Output buffer packing for first element
                // Debug expected vs actual for tile (0,0)
                if (current_tile_row == 0 && current_tile_col == 0) begin
                  // Debug: First element packed
                end
              end
              if (i == 1 && j == 0) begin
                // Debug: Output buffer packing for second row first element
              end
            end else begin
              output_buf_ping[buf_idx] <= {
                result_matrix[i][j+3],
                result_matrix[i][j+2],
                result_matrix[i][j+1],
                result_matrix[i][j]
              };
              if (i == 0 && j == 0) begin
                // Debug: Output buffer packing for first element (ping)
                // Debug expected vs actual for tile (0,0)
                if (current_tile_row == 0 && current_tile_col == 0) begin
                  // Debug: First element packed (ping)
                end
              end
              if (i == 1 && j == 0) begin
                // Debug: Output buffer packing for second row first element (ping)
              end
            end
          end
        end
      end
    end
  end
end

  // AXI-Lite interface
  assign s_axi_control_awready = (current_state == S_IDLE);
  assign s_axi_control_wready  = (current_state == S_IDLE);
  // assign s_axi_control_arready = (current_state == S_IDLE) || (s_axi_control_araddr == ADDR_STATUS);
  assign s_axi_control_arready = 1'b1;

  assign s_axi_control_bresp   = 2'b00;
  assign s_axi_control_rresp   = 2'b00;
  assign s_axi_control_bid     = s_axi_control_awid;
  assign s_axi_control_rid     = s_axi_control_arid;

  // FIXED: AXI-Lite write logic with proper register mapping
  reg [3:0] wstrb_latched;



  always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    s_axi_control_bvalid <= 1'b0;
    start_pulse          <= 1'b0;
    awvalid_seen         <= 1'b0;
    wvalid_seen          <= 1'b0;
    addr_a_reg           <= 64'd0;
    addr_b_reg           <= 64'd0;
    addr_c_reg           <= 64'd0;
    debug_buffer_index   <= 32'd0;

    // Initialize matrix chaining registers
    act_base_addr        <= 64'd0;
    wgt_base_addr        <= 64'd0;
    out_base_addr        <= 64'd0;
    total_rows           <= 16'd0;
    total_cols           <= 16'd0;
    current_tile_row     <= 16'd0;
    current_tile_col     <= 16'd0;
    current_inner_k      <= 16'd0;
    chain_mode_en        <= 1'b0;
    wstrb_latched        <= 4'b0000;
    last_fetched_tile_row <= 16'hFFFF;
    last_fetched_tile_col <= 16'hFFFF;
    last_fetched_inner_k  <= 16'hFFFF;
    fetch_in_progress     <= 1'b0;
  end else begin
    // one-shot start pulse and chaining initialization
    if (start_pulse) begin
      start_pulse <= 1'b0;
      if (chain_mode_en) begin
        // Reset tile position for new matrix operation
        current_tile_row <= 16'd0;
        current_tile_col <= 16'd0;
        current_inner_k <= 16'd0;
        chain_complete <= 1'b0;
        chain_active <= 1'b1;
        // Starting matrix chaining mode
      end
    end

    // complete write response
    if (s_axi_control_bvalid && s_axi_control_bready)
      s_axi_control_bvalid <= 1'b0;

    // capture AW
    if (s_axi_control_awvalid && s_axi_control_awready) begin
      awaddr_latched <= s_axi_control_awaddr;
      awvalid_seen   <= 1'b1;
    end

    // capture W
    if (s_axi_control_wvalid && s_axi_control_wready) begin
      wdata_latched  <= s_axi_control_wdata;
      wstrb_latched  <= s_axi_control_wstrb;   // latch strobes with data
      wvalid_seen    <= 1'b1;
    end

    // commit when both seen
    if (awvalid_seen && wvalid_seen) begin
      awvalid_seen         <= 1'b0;
      wvalid_seen          <= 1'b0;
      s_axi_control_bvalid <= 1'b1;

      // robust START: trigger if any written byte's LSB is 1
      if (awaddr_word == ADDR_CTRL) begin
        if ( (wstrb_latched[0] && wdata_latched[0])  ||
             (wstrb_latched[1] && wdata_latched[8])  ||
             (wstrb_latched[2] && wdata_latched[16]) ||
             (wstrb_latched[3] && wdata_latched[24]) )
          start_pulse <= 1'b1;
      end

      // register writes with byte-merge
      case (awaddr_word)
        A_LSB:          addr_a_reg[31:0]   <= merge_by_wstrb(addr_a_reg[31:0],   wdata_latched, wstrb_latched);
        A_MSB:          addr_a_reg[63:32]  <= merge_by_wstrb(addr_a_reg[63:32],  wdata_latched, wstrb_latched);
        B_LSB:          addr_b_reg[31:0]   <= merge_by_wstrb(addr_b_reg[31:0],   wdata_latched, wstrb_latched);
        B_MSB:          addr_b_reg[63:32]  <= merge_by_wstrb(addr_b_reg[63:32],  wdata_latched, wstrb_latched);
        C_LSB:          addr_c_reg[31:0]   <= merge_by_wstrb(addr_c_reg[31:0],   wdata_latched, wstrb_latched);
        C_MSB:          addr_c_reg[63:32]  <= merge_by_wstrb(addr_c_reg[63:32],  wdata_latched, wstrb_latched);

        // Matrix chaining control registers
        ACT_BASE_LSB:   act_base_addr[31:0]  <= merge_by_wstrb(act_base_addr[31:0],  wdata_latched, wstrb_latched);
        ACT_BASE_MSB:   act_base_addr[63:32] <= merge_by_wstrb(act_base_addr[63:32], wdata_latched, wstrb_latched);
        WGT_BASE_LSB:   wgt_base_addr[31:0]  <= merge_by_wstrb(wgt_base_addr[31:0],  wdata_latched, wstrb_latched);
        WGT_BASE_MSB:   wgt_base_addr[63:32] <= merge_by_wstrb(wgt_base_addr[63:32], wdata_latched, wstrb_latched);
        OUT_BASE_LSB:   out_base_addr[31:0]  <= merge_by_wstrb(out_base_addr[31:0],  wdata_latched, wstrb_latched);
        OUT_BASE_MSB:   out_base_addr[63:32] <= merge_by_wstrb(out_base_addr[63:32], wdata_latched, wstrb_latched);
        MATRIX_DIMS: begin
          total_cols <= merge_by_wstrb(total_cols, wdata_latched[31:16], wstrb_latched[3:2]);
          total_rows <= merge_by_wstrb(total_rows, wdata_latched[15:0],  wstrb_latched[1:0]);
        end
        TILE_POS: begin
          current_tile_col <= merge_by_wstrb(current_tile_col, wdata_latched[31:16], wstrb_latched[3:2]);
          current_tile_row <= merge_by_wstrb(current_tile_row, wdata_latched[15:0],  wstrb_latched[1:0]);
          current_inner_k <= 16'd0; // Reset inner k when manually setting tile position
        end
        CHAIN_CTRL: begin
          chain_mode_en <= wdata_latched[0];
          if (wdata_latched[0]) begin
            // Clear completion flags when starting new operation
            chain_complete <= 1'b0;
            chain_active <= 1'b0;
          end
        end
        DBG_BUF_INDEX:  debug_buffer_index <= merge_by_wstrb(debug_buffer_index, wdata_latched, wstrb_latched);
        default: ;
      endcase
    end
  end
end



reg packed_ready;

always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    packed_ready <= 1'b0;
  end else begin
    if (current_state == S_SYSTOLIC_COMPUTE) begin
      // FIXED: raise packed_ready for both single-tile and chaining modes
      if (chain_mode_en) begin
        // Chaining mode: packed_ready for final inner_k or when skipping capture
        if ((capture_results && systolic_cycle_count == PACK_CYCLE) ||
            (systolic_cycle_count >= SYSTOLIC_LATENCY && current_inner_k < tiles_per_inner - 1))
          packed_ready <= 1'b1;
      end else begin
        // Single-tile mode: packed_ready when capture is complete
        if (capture_results && systolic_cycle_count == 8'd122)
          packed_ready <= 1'b1;
      end
    end else if (current_state == S_IDLE && start_pulse) begin
      // clear for next op
      packed_ready <= 1'b0;
    end
  end
end


  // Buffer read address control is now handled in the main buffer control logic above
  // This ensures proper ping-pong buffer selection for debug access

// Output buffer staging logic now handled by the ping-pong multiplexer above
// write_staging_buffer is automatically updated via the mux based on output_buffer_select



  // FIXED: AXI-Lite read logic with proper status reporting
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_rvalid <= 1'b0;
      s_axi_control_rdata  <= 32'h0;
      s_axi_control_araddr_latched <= 8'h0;
    end else begin
      // Handle read data response completion
      if (s_axi_control_rvalid && s_axi_control_rready) begin
        s_axi_control_rvalid <= 1'b0;
      end

      // Handle address handshake and latch address
      if (s_axi_control_arvalid && s_axi_control_arready) begin
        s_axi_control_rvalid <= 1'b1;
        s_axi_control_araddr_latched <= s_axi_control_araddr;

        // Generate read data based on address
        case ({s_axi_control_araddr[7:2], 2'b00})
          // status: bit0=done, bit1=busy
          ADDR_STATUS: begin
            s_axi_control_rdata <= {30'd0, (current_state != S_IDLE), accelerator_done};
          end

          // existing pointers (great for readback debugging)
          A_LSB:            s_axi_control_rdata <= addr_a_reg[31:0];
          A_MSB:            s_axi_control_rdata <= addr_a_reg[63:32];
          B_LSB:            s_axi_control_rdata <= addr_b_reg[31:0];
          B_MSB:            s_axi_control_rdata <= addr_b_reg[63:32];
          C_LSB:            s_axi_control_rdata <= addr_c_reg[31:0];
          C_MSB:            s_axi_control_rdata <= addr_c_reg[63:32];

          // Matrix chaining control registers readback
          ACT_BASE_LSB: s_axi_control_rdata <= act_base_addr[31:0];
          ACT_BASE_MSB: s_axi_control_rdata <= act_base_addr[63:32];
          WGT_BASE_LSB: s_axi_control_rdata <= wgt_base_addr[31:0];
          WGT_BASE_MSB: s_axi_control_rdata <= wgt_base_addr[63:32];
          OUT_BASE_LSB: s_axi_control_rdata <= out_base_addr[31:0];
          OUT_BASE_MSB: s_axi_control_rdata <= out_base_addr[63:32];
          MATRIX_DIMS:    s_axi_control_rdata <= {total_cols, total_rows};
          TILE_POS:       s_axi_control_rdata <= {current_tile_col, current_tile_row};
          CHAIN_CTRL:     s_axi_control_rdata <= {31'b0, chain_mode_en};
          CHAIN_STATUS:   s_axi_control_rdata <= {30'b0, chain_complete, chain_active};

          // tiny buffer peek window
          DBG_BUF_INDEX:    s_axi_control_rdata <= debug_buffer_index;
          DBG_BUF_DATA_LS:  s_axi_control_rdata <= (debug_buffer_index < BUFFER_DEPTH) ? act_buf_rd_data[31:0]  : 32'hDEADBEEF;
          DBG_BUF_DATA_MS:  s_axi_control_rdata <= (debug_buffer_index < BUFFER_DEPTH) ? act_buf_rd_data[63:32] : 32'hDEADBEEF;

          // AXI transaction debug registers
          DBG_AXI_RDATA0:   s_axi_control_rdata <= debug_last_rdata[31:0];
          DBG_AXI_RDATA1:   s_axi_control_rdata <= debug_last_rdata[63:32];
          DBG_AXI_RDATA2:   s_axi_control_rdata <= debug_last_rdata[95:64];
          DBG_AXI_RDATA3:   s_axi_control_rdata <= debug_last_rdata[127:96];
          DBG_AXI_ADDR:     s_axi_control_rdata <= debug_last_addr;
          DBG_AXI_BEAT:     s_axi_control_rdata <= {24'd0, debug_beat_count};

          default: s_axi_control_rdata <= 32'hDEADBEEF;
        endcase
      end
    end
  end


// Replace the entire write engine always block with this:
// always @(posedge ap_clk) begin
//   if (!ap_rst_n) begin
//     write_active      <= 1'b0;
//     write_beat_count  <= 8'd0;
//     write_data_reg    <= 128'd0;
//     write_last_reg    <= 1'b0;
//     wbeats_sent       <= 8'd0;
//     debug_wbeats_sent <= 8'd0;
//   end else begin
//     case (current_state)
//       // Initialize write engine after AW handshake
//       S_WRITE_OUT_ADDR: begin
//         if (m_axi_gmem_awready) begin
//           write_active     <= 1'b1;
//           write_beat_count <= 8'd0;
//           write_data_reg   <= output_data_buffer[8'd0];
//           write_last_reg   <= 1'b0;
//           wbeats_sent      <= 8'd0;
//         end
//       end

//       // Drive W channel - only advance on WREADY handshakes
//       S_WRITE_OUT_DATA: begin
//         if (write_active && m_axi_gmem_wready) begin
//           wbeats_sent <= wbeats_sent + 1'b1;

//           if (write_beat_count == 8'd63) begin
//             // This cycle completes the last beat
//             write_active     <= 1'b0;
//             write_last_reg   <= 1'b0;
//             debug_wbeats_sent <= wbeats_sent + 1'b1; // Capture final count
//           end else begin
//             // Advance to next beat
//             write_beat_count <= write_beat_count + 1'b1;
//             write_data_reg   <= output_data_buffer[write_beat_count + 1'b1];
//             write_last_reg   <= (write_beat_count + 1'b1 == 8'd63);
//           end
//         end
//       end

//       // Clear debug counter when starting new operation
//       S_IDLE: begin
//         if (start_pulse) begin
//           wbeats_sent       <= 8'd0;
//           debug_wbeats_sent <= 8'd0;
//         end
//       end

//       default: ; // no change
//     endcase
//   end
// end
// ---- sequential write engine (only mutate your regs here)
always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    write_active      <= 1'b0;
    write_beat_count  <= 8'd0;
    write_data_reg    <= 128'd0;
    write_last_reg    <= 1'b0;
    wbeats_sent       <= 8'd0;
    debug_wbeats_sent <= 8'd0;
  end else begin
    // arm when AW handshakes
    if (current_state == S_WRITE_OUT_ADDR && m_axi_gmem_awready) begin
      write_active     <= 1'b1;
      write_beat_count <= 8'd0;
      write_data_reg   <= output_data_buffer[8'd0]; // NOTE: from the staging copy
      write_last_reg   <= (8'd0 == 8'd63);
      wbeats_sent      <= 8'd0;
      // Debug write start (removed for clean synthesis)
    end

    // advance strictly on WREADY handshake
    if (current_state == S_WRITE_OUT_DATA && write_active && m_axi_gmem_wready) begin
      wbeats_sent <= wbeats_sent + 1'b1;
      if (write_beat_count == 8'd63) begin
        write_active      <= 1'b0;    // this beat completes the burst
        write_last_reg    <= 1'b0;    // drop on next cycle
        debug_wbeats_sent <= wbeats_sent + 1'b1;
      end else begin
        write_beat_count <= write_beat_count + 1'b1;
        write_data_reg   <= output_data_buffer[write_beat_count + 1'b1];
        write_last_reg   <= (write_beat_count + 1'b1 == 8'd63);
      end
    end

    // clean up once we leave DATA
    if (current_state != S_WRITE_OUT_DATA) begin
      write_last_reg <= 1'b0;
    end
  end
end


  // FIXED: FSM and AXI Master interface
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
    m_axi_gmem_awsize   = 3'b100;  // 128-bit transfers
    m_axi_gmem_awburst  = 2'b01;   // INCR burst
    m_axi_gmem_arsize   = 3'b100;  // 128-bit transfers
    m_axi_gmem_arburst  = 2'b01;   // INCR burst
    m_axi_gmem_wstrb    = 16'hFFFF;

    case (current_state)
      S_IDLE: begin
        if (start_pulse) begin
          next_state = S_FETCH_ACT_ADDR;
        end
      end

      S_FETCH_ACT_ADDR: begin
        // Check for duplicate fetch prevention
        if (last_fetched_tile_row == current_tile_row &&
            last_fetched_tile_col == current_tile_col &&
            last_fetched_inner_k == current_inner_k) begin
          // Skip duplicate fetch
          next_state = S_SYSTOLIC_COMPUTE;
        end else begin
          m_axi_gmem_arvalid = 1'b1;
          m_axi_gmem_araddr  = current_act_addr;
          m_axi_gmem_arlen   = 8'd15; // 16 beats for 16x16 INT8 activation matrix
          m_axi_gmem_arsize  = 3'b100; // 16 bytes per beat (128-bit)

          // DEBUG: Detailed address calculation trace
          // Calculate activation address
          m_axi_gmem_arburst = 2'b01; // INCR burst type

          // Reduced fetch debug output
          if (m_axi_gmem_arready) next_state = S_FETCH_ACT_DATA;
        end
      end

      S_FETCH_ACT_DATA: begin
        m_axi_gmem_rready = 1'b1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast) begin
          next_state = S_FETCH_WGT_ADDR;
        end
      end

      S_FETCH_WGT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = current_wgt_addr;
        m_axi_gmem_arlen   = 8'd15; // 16 beats for 16x16 INT8 weight matrix
        m_axi_gmem_arsize  = 3'b100; // 16 bytes per beat (128-bit)
        m_axi_gmem_arburst = 2'b01; // INCR burst type

        // DEBUG: Detailed address calculation trace
        // Calculate weight address

        if (m_axi_gmem_arready) next_state = S_FETCH_WGT_DATA;
      end

      S_FETCH_WGT_DATA: begin
        m_axi_gmem_rready = 1'b1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
          next_state = S_SYSTOLIC_COMPUTE;
      end

      // ---- combinational FSM (only control the bus signals here)
S_SYSTOLIC_COMPUTE: begin
  if (systolic_cycle_count >= SYSTOLIC_LATENCY && packed_ready) begin
    // Computation complete, determine next state
    if (chain_mode_en) begin
      if (current_inner_k == tiles_per_inner - 1) begin
        // Final inner_k iteration: write results
        next_state = S_WRITE_OUT_ADDR;
      end else begin
        // Continue to next inner_k iteration
        next_state = S_CHAIN_NEXT_TILE;
      end
    end else begin
      // Single-tile mode: always write results
      next_state = S_WRITE_OUT_ADDR;
    end
  end
end

S_WRITE_OUT_ADDR: begin
  // DRIVE AW
  m_axi_gmem_awvalid = 1'b1;
  m_axi_gmem_awaddr  = current_out_addr;
  m_axi_gmem_awlen   = 8'd63;     // 64 beats
  // Write output to calculated address
  if (m_axi_gmem_awready)
    next_state = S_WRITE_OUT_DATA;
end

S_WRITE_OUT_DATA: begin
  // DRIVE W from the regs (do not compute next here)
  m_axi_gmem_wvalid = write_active;
  m_axi_gmem_wdata  = write_data_reg;
  m_axi_gmem_wstrb  = 16'hFFFF;
  m_axi_gmem_wlast  = write_last_reg;
m_axi_gmem_wvalid = 1'b1;

// Debug write data
// Write output data beat

if (m_axi_gmem_wvalid && m_axi_gmem_wready && m_axi_gmem_wlast)
  next_state = S_WAIT_WRITE_END;
end

      S_WAIT_WRITE_END: begin
        m_axi_gmem_bready = 1'b1;
        if (m_axi_gmem_bvalid && m_axi_gmem_bready) begin
          if (chain_mode_en) begin
            // FIXED: Check completion after write is done
            if (current_inner_k >= tiles_per_inner - 1 &&
                current_tile_col >= tiles_per_col - 1 &&
                current_tile_row >= tiles_per_row - 1) begin
              // All tiles completed
              next_state = S_DONE;
            end else begin
              next_state = S_CHAIN_NEXT_TILE;
            end
          end else begin
            next_state = S_DONE;
          end
        end
      end      S_CHAIN_NEXT_TILE: begin
        // Tile stepping is handled in sequential block above
        // Always go to address update state to ensure proper timing
        // Reduced state transition debug
        next_state = S_CHAIN_UPDATE_ADDR;
      end

      S_CHAIN_UPDATE_ADDR: begin
        // FIXED: Handle inner_k advancement or tile fetch based on context
        // Reduced update address debug
        next_state = S_FETCH_ACT_ADDR;
      end

      S_DONE: begin
        // Done flag is set in sequential logic
        next_state = S_IDLE;
      end

      default:
        next_state = S_IDLE;
    endcase
  end

endmodule
