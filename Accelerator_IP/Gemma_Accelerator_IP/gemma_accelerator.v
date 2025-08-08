module gemma_accelerator #(
  parameter integer ID_WIDTH = 12,
  parameter integer BUFFER_DEPTH = 256,
  parameter integer BUFFER_ADDR_WIDTH = $clog2(BUFFER_DEPTH),
  parameter integer SYSTOLIC_SIZE = 16,
  parameter integer DATA_WIDTH = 8,
  parameter integer ACCUM_WIDTH = 20  // 20-bit to handle INT8×INT8 accumulation safely
)(
  input  wire                  ap_clk,
  input  wire                  ap_rst_n,
  // AXI-Lite Control Interface
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
  input  wire [0:0]            s_axi_control_awid,
  output wire [0:0]            s_axi_control_bid,
  input  wire                  s_axi_control_arvalid,
  output wire                  s_axi_control_arready,
  input  wire [5:0]            s_axi_control_araddr,
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

  // FSM states (removed dequantization state)
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

  // AXI-Lite register offsets (removed dequantization parameters)
  localparam [5:0]
    ADDR_CTRL     = 6'h00,
    ADDR_STATUS   = 6'h04,
    A_LSB         = 6'h10,
    A_MSB         = 6'h14,
    B_LSB         = 6'h18,
    B_MSB         = 6'h1C,
    C_LSB         = 6'h20,
    C_MSB         = 6'h24;

  reg [3:0]   current_state, next_state;
  reg [7:0]   beat_counter;
  reg [63:0]  addr_a_reg, addr_b_reg, addr_c_reg;
  reg         start_pulse;

  // AXI-Lite write buffer
  reg         awvalid_seen, wvalid_seen;
  reg [5:0]   awaddr_latched;
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

  // Systolic Array signals
  reg                           systolic_accum_reset;
  reg signed [SYSTOLIC_SIZE*DATA_WIDTH-1:0]  systolic_north_inputs; // 128 bits
  reg signed [SYSTOLIC_SIZE*DATA_WIDTH-1:0]  systolic_west_inputs;  // 128 bits
  wire signed [SYSTOLIC_SIZE*SYSTOLIC_SIZE*ACCUM_WIDTH-1:0] systolic_results; // 5120 bits (16×16×20)

  // Systolic control
  reg [7:0]                     systolic_cycle_count;
  reg [3:0]                     current_k;
  reg                           systolic_computing;

  // Result management (truncate 20-bit accumulator results to 16-bit for storage)
  reg [ACCUM_WIDTH-1:0]         result_matrix [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1];
  reg [15:0]                    result_matrix_16bit [0:SYSTOLIC_SIZE-1][0:SYSTOLIC_SIZE-1]; // INT16 storage
  reg [127:0]                   output_data_buffer [0:31]; // 32 x 128-bit output words (8 INT16 values per word)
  reg [4:0]                     output_buffer_idx;
  reg                           capture_results;

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

  // Systolic Array instantiation
  systolic_array_16x16 #(
    .SIZE(SYSTOLIC_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACCUM_WIDTH(ACCUM_WIDTH)
  ) systolic_array_inst (
    .clk(ap_clk),
    .rst(~ap_rst_n),
    .accum_reset(systolic_accum_reset),
    .north_inputs(systolic_north_inputs),
    .west_inputs(systolic_west_inputs),
    .result_matrix(systolic_results)
  );

  // State machine and counters
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      current_state <= S_IDLE;
      beat_counter <= 8'd0;
      systolic_cycle_count <= 8'd0;
      current_k <= 4'd0;
      output_buffer_idx <= 5'd0;
      systolic_computing <= 1'b0;
      capture_results <= 1'b0;
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

      // Systolic computation control
      if (current_state == S_SYSTOLIC_COMPUTE) begin
        systolic_computing <= 1'b1;
        systolic_cycle_count <= systolic_cycle_count + 1'b1;
        
        // Advance K dimension
        if (current_k < 4'd15) begin
          current_k <= current_k + 1'b1;
        end else begin
          current_k <= 4'd0;
        end
        
        // Start capturing results after pipeline fills
        if (systolic_cycle_count >= 8'd31) begin
          capture_results <= 1'b1;
        end
      end else begin
        systolic_computing <= 1'b0;
        systolic_cycle_count <= 8'd0;
        current_k <= 4'd0;
        capture_results <= 1'b0;
      end

      // Output buffer management (32 beats for INT16 results)
      if (current_state == S_WRITE_OUT_DATA && m_axi_gmem_wvalid && m_axi_gmem_wready) begin
        if (output_buffer_idx < 5'd31)
          output_buffer_idx <= output_buffer_idx + 1'b1;
      end else if (current_state == S_IDLE) begin
        output_buffer_idx <= 5'd0;
      end
    end
  end

  // Buffer control logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      act_buf_wr_en         <= 1'b0;
      act_buf_wr_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      act_buf_wr_data       <= 128'd0;
      act_buf_rd_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_wr_en         <= 1'b0;
      wgt_buf_wr_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      wgt_buf_wr_data       <= 128'd0;
      wgt_buf_rd_addr       <= {BUFFER_ADDR_WIDTH{1'b0}};
      systolic_accum_reset  <= 1'b0;
      systolic_north_inputs <= {SYSTOLIC_SIZE*DATA_WIDTH{1'b0}};
      systolic_west_inputs  <= {SYSTOLIC_SIZE*DATA_WIDTH{1'b0}};
    end else begin
      // Default values
      act_buf_wr_en         <= 1'b0;
      wgt_buf_wr_en         <= 1'b0;
      systolic_accum_reset  <= 1'b0;

      // Load activation data (INT8, 16 values per beat)
      if (current_state == S_FETCH_ACT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        act_buf_wr_en   <= 1'b1;
        act_buf_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
        act_buf_wr_data <= m_axi_gmem_rdata;
      end

      // Load weight data (INT8, 16 values per beat)
      if (current_state == S_FETCH_WGT_DATA && m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        wgt_buf_wr_en   <= 1'b1;
        wgt_buf_wr_addr <= beat_counter[BUFFER_ADDR_WIDTH-1:0];
        wgt_buf_wr_data <= m_axi_gmem_rdata; // Full 128-bit data (16 INT8 weights)
      end

      // Systolic computation
      if (current_state == S_SYSTOLIC_COMPUTE) begin
        // Reset accumulator at start
        if (systolic_cycle_count == 8'd0) begin
          systolic_accum_reset <= 1'b1;
        end else if (systolic_computing) begin
          // Set buffer addresses based on current K
          act_buf_rd_addr <= current_k;
          wgt_buf_rd_addr <= current_k;
          
          // Feed data to systolic array
          systolic_west_inputs  <= $signed(act_buf_rd_data);
          systolic_north_inputs <= $signed(wgt_buf_rd_data);
        end
      end
    end
  end

  // Result capture and output buffer preparation
  integer i, j;
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      // Initialize result matrix
      for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
        for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
          result_matrix[i][j] <= {ACCUM_WIDTH{1'b0}};
          result_matrix_16bit[i][j] <= 16'd0;
        end
      end
      // Initialize output buffer
      for (i = 0; i < 32; i = i + 1) begin
        output_data_buffer[i] <= 128'd0;
      end
    end else begin
      // Capture results when computation is nearly complete (cycle 45)
      if (capture_results && systolic_cycle_count == 8'd45) begin
        for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
          for (j = 0; j < SYSTOLIC_SIZE; j = j + 1) begin
            // Extract the 20-bit result for position [i][j]
            result_matrix[i][j] <= systolic_results[(i*SYSTOLIC_SIZE + j + 1)*ACCUM_WIDTH - 1 -: ACCUM_WIDTH];
            
            // Truncate/saturate 20-bit result to 16-bit
            if ($signed(result_matrix[i][j]) > $signed(20'd32767))
              result_matrix_16bit[i][j] <= 16'd32767;  // Positive saturation
            else if ($signed(result_matrix[i][j]) < $signed(-20'd32768))
              result_matrix_16bit[i][j] <= -16'd32768; // Negative saturation  
            else
              result_matrix_16bit[i][j] <= result_matrix[i][j][15:0];
          end
        end
      end
      
      // Prepare output data buffer (pack 8×16-bit results into 128-bit words)
      // This happens at cycle 46, before transitioning to S_WRITE_OUT_ADDR
      if (current_state == S_SYSTOLIC_COMPUTE && systolic_cycle_count == 8'd46) begin
        for (i = 0; i < SYSTOLIC_SIZE; i = i + 1) begin
          // Pack first 8 results of row i (columns 0-7)
          output_data_buffer[i*2] <= {
            result_matrix_16bit[i][7], result_matrix_16bit[i][6], 
            result_matrix_16bit[i][5], result_matrix_16bit[i][4],
            result_matrix_16bit[i][3], result_matrix_16bit[i][2], 
            result_matrix_16bit[i][1], result_matrix_16bit[i][0]
          };
          // Pack remaining 8 results of row i (columns 8-15)
          output_data_buffer[i*2 + 1] <= {
            result_matrix_16bit[i][15], result_matrix_16bit[i][14], 
            result_matrix_16bit[i][13], result_matrix_16bit[i][12],
            result_matrix_16bit[i][11], result_matrix_16bit[i][10], 
            result_matrix_16bit[i][9],  result_matrix_16bit[i][8]
          };
        end
      end
    end
  end

  // AXI-Lite interface
  assign s_axi_control_awready = (current_state == S_IDLE);
  assign s_axi_control_wready  = (current_state == S_IDLE);
  assign s_axi_control_arready = (current_state == S_IDLE) || (s_axi_control_araddr == ADDR_STATUS);
  assign s_axi_control_bresp   = 2'b00;
  assign s_axi_control_rresp   = 2'b00;
  assign s_axi_control_bid     = s_axi_control_awid;
  assign s_axi_control_rid     = s_axi_control_arid;

  // AXI-Lite write logic (removed dequantization parameters)
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_bvalid <= 1'b0;
      start_pulse          <= 1'b0;
      awvalid_seen         <= 1'b0;
      wvalid_seen          <= 1'b0;
      addr_a_reg           <= 64'd0;
      addr_b_reg           <= 64'd0;
      addr_c_reg           <= 64'd0;
    end else begin
      if (start_pulse)
        start_pulse <= 1'b0;

      if (s_axi_control_bvalid && s_axi_control_bready)
        s_axi_control_bvalid <= 1'b0;

      if (s_axi_control_awvalid && s_axi_control_awready) begin
        awaddr_latched <= s_axi_control_awaddr;
        awvalid_seen   <= 1'b1;
      end

      if (s_axi_control_wvalid && s_axi_control_wready) begin
        wdata_latched <= s_axi_control_wdata;
        wvalid_seen   <= 1'b1;
      end

      if (awvalid_seen && wvalid_seen) begin
        awvalid_seen <= 1'b0;
        wvalid_seen  <= 1'b0;
        s_axi_control_bvalid <= 1'b1;
        case (awaddr_latched)
          ADDR_CTRL:  start_pulse          <= wdata_latched[0];
          A_LSB:      addr_a_reg[31:0]     <= wdata_latched;
          A_MSB:      addr_a_reg[63:32]    <= wdata_latched;
          B_LSB:      addr_b_reg[31:0]     <= wdata_latched;
          B_MSB:      addr_b_reg[63:32]    <= wdata_latched;
          C_LSB:      addr_c_reg[31:0]     <= wdata_latched;
          C_MSB:      addr_c_reg[63:32]    <= wdata_latched;
        endcase
      end
    end
  end

  // AXI-Lite read logic
  always @(posedge ap_clk) begin
    if (!ap_rst_n) begin
      s_axi_control_rvalid <= 1'b0;
      s_axi_control_rdata  <= 32'h0;
    end else begin
      if (s_axi_control_rvalid && s_axi_control_rready) begin
        s_axi_control_rvalid <= 1'b0;
      end else if (s_axi_control_arvalid && s_axi_control_arready) begin
        s_axi_control_rvalid <= 1'b1;
        case (s_axi_control_araddr)
//          ADDR_STATUS:   s_axi_control_rdata <= {30'd0, (current_state == S_DONE), (current_state != S_IDLE)};
          ADDR_STATUS:   s_axi_control_rdata <= {30'd0, (current_state != S_IDLE), (current_state == S_DONE)};
          default:       s_axi_control_rdata <= 32'hDEADBEEF;
        endcase
      end
    end
  end

  // FSM and AXI Master interface
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
      S_IDLE: 
        if (start_pulse) next_state = S_FETCH_ACT_ADDR;

      S_FETCH_ACT_ADDR: begin
        m_axi_gmem_arvalid = 1'b1;
        m_axi_gmem_araddr  = addr_a_reg;
        m_axi_gmem_arlen   = 8'd15; // 16 beats for 16x16 INT8 activation matrix
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
        if (m_axi_gmem_arready) next_state = S_FETCH_WGT_DATA;
      end

      S_FETCH_WGT_DATA: begin
        m_axi_gmem_rready = 1'b1;
        if (m_axi_gmem_rvalid && m_axi_gmem_rready && m_axi_gmem_rlast)
          next_state = S_SYSTOLIC_COMPUTE;
      end

      S_SYSTOLIC_COMPUTE: begin
        if (systolic_cycle_count >= 8'd47) // Complete matrix multiplication (back to original timing)
          next_state = S_WRITE_OUT_ADDR;
      end

      S_WRITE_OUT_ADDR: begin
        m_axi_gmem_awvalid = 1'b1;
        m_axi_gmem_awaddr  = addr_c_reg;
        m_axi_gmem_awlen   = 8'd31; // 32 beats for 16x16 INT16 result matrix
        if (m_axi_gmem_awready) next_state = S_WRITE_OUT_DATA;
      end

      S_WRITE_OUT_DATA: begin
        m_axi_gmem_wvalid = 1'b1;
        m_axi_gmem_wdata  = output_data_buffer[output_buffer_idx];
        m_axi_gmem_wlast  = (beat_counter == 8'd31); // Last beat of 32-beat burst
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