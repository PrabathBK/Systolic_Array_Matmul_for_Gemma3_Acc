
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
    S_DONE             = 4'd9;

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
  DBG_AXI_BEAT    = 8'h50;  // read:  {24'd0, debug_beat_count}


  reg [3:0]   current_state, next_state;
  reg [7:0]   beat_counter;
  reg [63:0]  addr_a_reg, addr_b_reg, addr_c_reg;
  reg         start_pulse;
  reg         accelerator_done;  // FIXED: Add done signal

  // AXI-Lite write buffer
  reg         awvalid_seen, wvalid_seen;
  reg [7:0]   awaddr_latched;
  reg [31:0]  wdata_latched;

  // Buffer control signals for activation buffer (INT8, 128-bit width = 16 values)
  reg                           act_buf_wr_en;
  reg [BUFFER_ADDR_WIDTH-1:0]   act_buf_wr_addr;
  reg [127:0]                   act_buf_wr_data;
  reg [BUFFER_ADDR_WIDTH-1:0]   act_buf_rd_addr;
  wire [127:0]                  act_buf_rd_data;

  // Buffer control signals for weight buffer (INT8, 128-bit width = 16 values)
  reg                           wgt_buf_wr_en;
  reg [BUFFER_ADDR_WIDTH-1:0]   wgt_buf_wr_addr;
  reg [127:0]                   wgt_buf_wr_data;
  reg [BUFFER_ADDR_WIDTH-1:0]   wgt_buf_rd_addr;
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
  reg [ACCUM_WIDTH-1:0]         result_matrix [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1];
  reg [127:0]                   output_data_buffer [0:63];
  reg [4:0]                     output_buffer_idx;
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
wire [7:0] araddr_word = {s_axi_control_araddr[7:2], 2'b00};

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

  // Instantiate activation buffer (INT8, 128-bit width)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) activation_buffer (
    .clk(ap_clk),
    .wr_en(act_buf_wr_en),
    .wr_addr(act_buf_wr_addr),
    .wr_data(act_buf_wr_data),
    .rd_addr(act_buf_rd_addr),
    .rd_data(act_buf_rd_data)
  );

  // Weight buffer for INT8 weights (128-bit width for 16 values)
  accelerator_buffer #(
    .DATA_WIDTH(128),
    .DEPTH(BUFFER_DEPTH),
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
  ) weight_buffer (
    .clk(ap_clk),
    .wr_en(wgt_buf_wr_en),
    .wr_addr(wgt_buf_wr_addr),
    .wr_data(wgt_buf_wr_data),
    .rd_addr(wgt_buf_rd_addr),
    .rd_data(wgt_buf_rd_data)
  );

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
      output_buffer_idx <= 5'd0;
      systolic_computing <= 1'b0;
      capture_results <= 1'b0;
      matrices_loaded <= 1'b0;
      activation_loaded <= 1'b0;
      weight_loaded <= 1'b0;
      accelerator_done <= 1'b0;  // FIXED: Initialize done flag
      
      // Initialize debug registers
      debug_last_rdata <= 128'd0;
      debug_beat_count <= 8'd0;
      debug_last_addr <= 32'd0;
    end else begin
      current_state <= next_state;
      
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
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
        activation_loaded <= 1'b1;
      else if (current_state == S_IDLE)
        activation_loaded <= 1'b0;

      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
        weight_loaded <= 1'b1;
      else if (current_state == S_IDLE)
        weight_loaded <= 1'b0;

      // Both matrices loaded - give one extra cycle for stabilization
      matrices_loaded <= activation_loaded && weight_loaded;

      // FIXED: Done flag management
      if (current_state == S_DONE)
        accelerator_done <= 1'b1;
      else if (start_pulse)  // Clear done when starting new computation
        accelerator_done <= 1'b0;

if (current_state == S_SYSTOLIC_COMPUTE) begin
  systolic_cycle_count <= systolic_cycle_count + 1'b1;

  if (matrices_loaded) begin
    systolic_computing <= 1'b1;
    input_cycle_count  <= input_cycle_count + 1'b1;

    // give the systolic pipeline a bit more time before capture
    if (systolic_cycle_count >= 8'd35) begin
      capture_results <= 1'b1;
    end
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
        if (output_buffer_idx < 5'd63)
          output_buffer_idx <= output_buffer_idx + 1'b1;
      end else if (current_state == S_IDLE) begin
        output_buffer_idx <= 5'd0;
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
        // Debug: Capture last AXI transaction details
        debug_last_rdata <= m_axi_gmem_rdata;
        debug_beat_count <= beat_counter;
        debug_last_addr <= addr_a_reg + (beat_counter << 4); // beat_counter * 16 bytes
        
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
      end
      
      // Unpack weight matrix when loading completes
      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        weight_matrix[beat_counter][0]  <= $signed(m_axi_gmem_rdata[7:0]);
        weight_matrix[beat_counter][1]  <= $signed(m_axi_gmem_rdata[15:8]);
        weight_matrix[beat_counter][2]  <= $signed(m_axi_gmem_rdata[23:16]);
        weight_matrix[beat_counter][3]  <= $signed(m_axi_gmem_rdata[31:24]);
        weight_matrix[beat_counter][4]  <= $signed(m_axi_gmem_rdata[39:32]);
        weight_matrix[beat_counter][5]  <= $signed(m_axi_gmem_rdata[47:40]);
        weight_matrix[beat_counter][6]  <= $signed(m_axi_gmem_rdata[55:48]);
        weight_matrix[beat_counter][7]  <= $signed(m_axi_gmem_rdata[63:56]);
        weight_matrix[beat_counter][8]  <= $signed(m_axi_gmem_rdata[71:64]);
        weight_matrix[beat_counter][9]  <= $signed(m_axi_gmem_rdata[79:72]);
        weight_matrix[beat_counter][10] <= $signed(m_axi_gmem_rdata[87:80]);
        weight_matrix[beat_counter][11] <= $signed(m_axi_gmem_rdata[95:88]);
        weight_matrix[beat_counter][12] <= $signed(m_axi_gmem_rdata[103:96]);
        weight_matrix[beat_counter][13] <= $signed(m_axi_gmem_rdata[111:104]);
        weight_matrix[beat_counter][14] <= $signed(m_axi_gmem_rdata[119:112]);
        weight_matrix[beat_counter][15] <= $signed(m_axi_gmem_rdata[127:120]);
      end
    end
  end

  // Buffer control logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      act_buf_wr_en         <= 1'b0;
      act_buf_wr_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      act_buf_wr_data       <= 128'd0;
      wgt_buf_wr_en         <= 1'b0;
      wgt_buf_wr_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_wr_data       <= 128'd0;
      wgt_buf_rd_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
    end else begin
      // Default values
      act_buf_wr_en         <= 1'b0;
      wgt_buf_wr_en         <= 1'b0;

      // Load activation data
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        act_buf_wr_en   <= 1'b1;
        act_buf_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
        act_buf_wr_data <= m_axi_gmem_rdata;
      end

      // Load weight data
      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        wgt_buf_wr_en   <= 1'b1;
        wgt_buf_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
        wgt_buf_wr_data <= m_axi_gmem_rdata;
      end
    end
  end

  // Synchronous clear of all PE accumulators at the start of SYSTOLIC
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      systolic_accum_reset <= 1'b1;
    end else begin
      if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd0)
        systolic_accum_reset <= 1'b1;
      else
        systolic_accum_reset <= 1'b0;
    end
  end

  // FIXED: Systolic array input generation with VALID SIGNAL CONTROL
  integer skew_i;
  integer buf_idx;
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      for (skew_i = 0; skew_i < SYSTOLIC_SIZE; skew_i = skew_i + 1) begin
        systolic_north_inputs[skew_i] <= 8'd0;
        systolic_west_inputs[skew_i] <= 8'd0;
      end
      systolic_north_valid <= {SYSTOLIC_SIZE{1'b0}};
      systolic_west_valid <= {SYSTOLIC_SIZE{1'b0}};
    end else if (current_state == S_SYSTOLIC_COMPUTE && matrices_loaded && systolic_computing) begin
      for (skew_i = 0; skew_i < SYSTOLIC_SIZE; skew_i = skew_i + 1) begin
        if (input_cycle_count >= (skew_i + 1) && (input_cycle_count - skew_i - 1) < SYSTOLIC_SIZE) begin
          systolic_north_inputs[skew_i] <= weight_matrix[input_cycle_count - skew_i - 1][skew_i];
          systolic_west_inputs[skew_i] <= activation_matrix[skew_i][input_cycle_count - skew_i - 1];
          systolic_north_valid[skew_i] <= 1'b1;
          systolic_west_valid[skew_i] <= 1'b1;
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
    for (i = 0; i < 64; i = i + 1) begin
      output_data_buffer[i] <= 128'd0;
    end
  end else begin
    // 1) CAPTURE: wait an extra couple of cycles for pipeline to settle
    if (capture_results && systolic_cycle_count == 8'd60) begin
      for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
        for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
          // keep your original +1 slice convention
          result_matrix[i][j] <= systolic_results[(i*SYSTOLIC_SIZE + j + 1)*ACCUM_WIDTH - 1 -: ACCUM_WIDTH];
        end
      end
    end

    // 2) PACK: do packing one cycle *after* capture
    if (capture_results && systolic_cycle_count == 8'd65) begin
      // pack 4×32-bit per 128-bit, row by row, big-endian within the word
      for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
        for (j = 0; j < SYSTOLIC_SIZE; j = j + 4) begin
          buf_idx = i * 4 + j/4;
          output_data_buffer[buf_idx] <= {
            result_matrix[i][j+3],
            result_matrix[i][j+2],
            result_matrix[i][j+1],
            result_matrix[i][j+0]
          };
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
    wstrb_latched        <= 4'b0000;
  end else begin
    // one-shot start pulse
    if (start_pulse) start_pulse <= 1'b0;

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
      // raise when packing is done
      if (capture_results && systolic_cycle_count == 8'd65)
        packed_ready <= 1'b1;
    end else if (current_state == S_IDLE && start_pulse) begin
      // clear for next op
      packed_ready <= 1'b0;
    end
  end
end


  // Add buffer read address control for debug access
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      act_buf_rd_addr <= {BUFFER_ADDR_WIDTH{1'b0}};
    end else begin
      act_buf_rd_addr <= debug_buffer_index[BUFFER_ADDR_WIDTH-1:0];
    end
  end

reg [127:0] write_staging_buffer [0:63];

integer k;
always @(posedge ap_clk) begin
  if (!ap_rst_n) begin
    for (k=0;k<64;k=k+1) write_staging_buffer[k] <= 128'd0;
  end else if (current_state == S_SYSTOLIC_COMPUTE && packed_ready && systolic_cycle_count == 8'd66) begin
    for (k=0;k<64;k=k+1) write_staging_buffer[k] <= output_data_buffer[k];
  end
end



  // FIXED: AXI-Lite read logic with proper status reporting
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_rvalid <= 1'b0;
      s_axi_control_rdata  <= 32'h0;
    end else begin
      if (s_axi_control_rvalid && s_axi_control_rready) begin
        s_axi_control_rvalid <= 1'b0;
      end else if (s_axi_control_arvalid && s_axi_control_arready) begin
        s_axi_control_rvalid <= 1'b1;
      

        // assume araddr_word = {s_axi_control_araddr[5:2],2'b00}
        case (araddr_word)
          // status: bit0=done, bit1=busy
          ADDR_STATUS:      s_axi_control_rdata <= {30'd0, (current_state != S_IDLE), accelerator_done};

          // existing pointers (great for readback debugging)
          A_LSB:            s_axi_control_rdata <= addr_a_reg[31:0];
          A_MSB:            s_axi_control_rdata <= addr_a_reg[63:32];
          B_LSB:            s_axi_control_rdata <= addr_b_reg[31:0];
          B_MSB:            s_axi_control_rdata <= addr_b_reg[63:32];
          C_LSB:            s_axi_control_rdata <= addr_c_reg[31:0];
          C_MSB:            s_axi_control_rdata <= addr_c_reg[63:32];

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

          default:          s_axi_control_rdata <= 32'hDEADBEEF;
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
      write_data_reg   <= write_staging_buffer[8'd0]; // NOTE: from the staging copy
      write_last_reg   <= (8'd0 == 8'd63);
      wbeats_sent      <= 8'd0;
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
        write_data_reg   <= write_staging_buffer[write_beat_count + 1'b1];
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
      S_IDLE: 
        if (start_pulse) next_state = S_FETCH_ACT_ADDR;

      S_FETCH_ACT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = addr_a_reg;
        m_axi_gmem_arlen   = 8'd15; // 16 beats for 16x16 INT8 activation matrix
        m_axi_gmem_arsize  = 3'b100; // 16 bytes per beat (128-bit)
        m_axi_gmem_arburst = 2'b01; // INCR burst type
        if (m_axi_gmem_arready) next_state = S_FETCH_ACT_DATA;
      end

      S_FETCH_ACT_DATA: begin
        m_axi_gmem_rready = 1'b1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast) 
          next_state = S_FETCH_WGT_ADDR;
      end

      S_FETCH_WGT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = addr_b_reg;
        m_axi_gmem_arlen   = 8'd15; // 16 beats for 16x16 INT8 weight matrix
        m_axi_gmem_arsize  = 3'b100; // 16 bytes per beat (128-bit)
        m_axi_gmem_arburst = 2'b01; // INCR burst type
        if (m_axi_gmem_arready) next_state = S_FETCH_WGT_DATA;
      end

      S_FETCH_WGT_DATA: begin
        m_axi_gmem_rready = 1'b1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
          next_state = S_SYSTOLIC_COMPUTE;
      end

      // ---- combinational FSM (only control the bus signals here)
S_SYSTOLIC_COMPUTE: begin
  if (systolic_cycle_count >= 8'd70 && packed_ready)
    next_state = S_WRITE_OUT_ADDR;
end

S_WRITE_OUT_ADDR: begin
  // DRIVE AW
  m_axi_gmem_awvalid = 1'b1;
  m_axi_gmem_awaddr  = addr_c_reg;
  m_axi_gmem_awlen   = 8'd63;     // 64 beats
  if (m_axi_gmem_awready)
    next_state = S_WRITE_OUT_DATA;
end

S_WRITE_OUT_DATA: begin
  // DRIVE W from the regs (do not compute next here)
  m_axi_gmem_wvalid = write_active;
  m_axi_gmem_wdata  = write_data_reg;
  m_axi_gmem_wstrb  = 16'hFFFF;
  m_axi_gmem_wlast  = write_last_reg;

  if (m_axi_gmem_wvalid && m_axi_gmem_wready && m_axi_gmem_wlast)
    next_state = S_WAIT_WRITE_END;
end

S_WAIT_WRITE_END: begin
  m_axi_gmem_bready = 1'b1;
  if (m_axi_gmem_bvalid && m_axi_gmem_bready)
    next_state = S_DONE;
end

      S_DONE: 
        next_state = S_IDLE;

      default:
        next_state = S_IDLE;
    endcase
  end

endmodule