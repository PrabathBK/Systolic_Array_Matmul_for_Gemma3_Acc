`timescale 1ns / 1ps

module systolic_array_axi_stream #(
    parameter SIZE = 8,
    parameter DATA_WIDTH = 4,
    parameter BUFFER_DEPTH = 256,
    parameter ADDR_WIDTH = $clog2(BUFFER_DEPTH)
)(
    input  wire aclk,
    input  wire aresetn,

    // AXI4-Lite Slave (Control)
    input  wire [31:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,

    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,

    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,

    input  wire [31:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,

    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    // AXI4-Stream Slave (Data In)
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,

    // Debug
    output wire         done,
    output wire         result_valid
);

    // ================================================
    // AXI4-Lite Register Declarations
    // ================================================
    localparam integer ADDR_LSB             = 2; 
    localparam integer OPT_MEM_ADDR_BITS    = 4;

    // reg [31:0]  slv_reg     [0:15];
    reg [31:0]  slv_reg [0:(3 + SIZE*SIZE - 1)];
    reg [31:0]  axi_awaddr, axi_araddr;
    reg         axi_awready, axi_wready, axi_bvalid, axi_arready, axi_rvalid;
    reg [31:0]  axi_rdata;
    reg [1:0]   axi_bresp, axi_rresp;

    assign      s_axi_awready = axi_awready;
    assign      s_axi_wready  = axi_wready;
    assign      s_axi_bvalid  = axi_bvalid;
    assign      s_axi_bresp   = axi_bresp;
    assign      s_axi_arready = axi_arready;
    assign      s_axi_rvalid  = axi_rvalid;
    assign      s_axi_rdata   = axi_rdata;
    assign      s_axi_rresp   = axi_rresp;

    // ================================================
    // AXI4-Lite FSM: Write Address
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) axi_awready <= 1'b0;
        else if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
            axi_awready <= 1'b1;
            axi_awaddr  <= s_axi_awaddr;
        end else axi_awready <= 1'b0;
    end

    // ================================================
    // AXI4-Lite FSM: Write Data
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) axi_wready <= 1'b0;
        else if (~axi_wready && s_axi_wvalid && s_axi_awvalid) axi_wready <= 1'b1;
        else axi_wready <= 1'b0;
    end

    // ================================================
    // AXI4-Lite FSM: Register Write
    // ================================================
    integer byte_index;
    always @(posedge aclk) begin
        if (~aresetn) begin
            slv_reg[0] <= 0; // Control
            slv_reg[1] <= SIZE; // Matrix size
            slv_reg[2] <= 0; // Status
        end else if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid) begin
            case (axi_awaddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB])
                4'h0: for (byte_index = 0; byte_index <= 3; byte_index = byte_index + 1)
                    if (s_axi_wstrb[byte_index])
                        slv_reg[0][(byte_index*8) +: 8] <= s_axi_wdata[(byte_index*8) +: 8];
                4'h1: for (byte_index = 0; byte_index <= 3; byte_index = byte_index + 1)
                    if (s_axi_wstrb[byte_index])
                        slv_reg[1][(byte_index*8) +: 8] <= s_axi_wdata[(byte_index*8) +: 8];
            endcase
        end
    end

    // ================================================
    // AXI4-Lite FSM: Write Response
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) begin
            axi_bvalid <= 1'b0; axi_bresp <= 2'b0;
        end else if (axi_awready && s_axi_awvalid && ~axi_bvalid && axi_wready && s_axi_wvalid) begin
            axi_bvalid <= 1'b1; axi_bresp <= 2'b00;
        end else if (axi_bvalid && s_axi_bready) axi_bvalid <= 1'b0;
    end

    // ================================================
    // AXI4-Lite FSM: Read Address
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) begin
            axi_arready <= 1'b0; axi_araddr <= 0;
        end else if (~axi_arready && s_axi_arvalid) begin
            axi_arready <= 1'b1; axi_araddr <= s_axi_araddr;
        end else axi_arready <= 1'b0;
    end

    // ================================================
    // AXI4-Lite FSM: Read Data
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) begin
            axi_rvalid <= 1'b0; axi_rresp <= 2'b0;
        end else if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
            axi_rvalid <= 1'b1; axi_rresp <= 2'b00;
        end else if (axi_rvalid && s_axi_rready) axi_rvalid <= 1'b0;
    end

    // always @(posedge aclk) begin
    //     if (~aresetn) axi_rdata <= 0;
    //     else if (axi_arready && s_axi_arvalid) begin
    //         case (axi_araddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB])
    //             4'h0: axi_rdata <= slv_reg[0];
    //             4'h1: axi_rdata <= slv_reg[1];
    //             4'h2: axi_rdata <= slv_reg[2];
    //             default: axi_rdata <= 0;
    //         endcase
    //     end
    // end
    // always @(posedge aclk) begin
    // if (~aresetn) axi_rdata <= 0;
    // else if (axi_arready && s_axi_arvalid) begin
    //     case (axi_araddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB])
    //         4'h0: axi_rdata <= slv_reg[0];
    //         4'h1: axi_rdata <= slv_reg[1];
    //         4'h2: axi_rdata <= slv_reg[2];
    //         default: axi_rdata <= slv_reg[axi_araddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB]];
    //     endcase
    // end

// end

        wire [ADDR_WIDTH-1:0] reg_index = axi_araddr >> 2;

        always @(posedge aclk) begin
        if (~aresetn)
            axi_rdata <= 0;
        else if (axi_arready && s_axi_arvalid)
            axi_rdata <= slv_reg[reg_index];
        end


    // ================================================
    // AXI4-Stream + Loader FSM 
    // ================================================
    localparam IDLE = 3'b000, 
               WRITE_WEIGHTS = 3'b001, 
               WRITE_ACTIVATIONS = 3'b010, 
               LOAD_WEIGHTS = 3'b011, 
               LOAD_ACTIVATIONS = 3'b100, 
               WAIT_START = 3'b101,
               COMPUTING = 3'b110;

    reg [2:0]               stream_state;
    reg [ADDR_WIDTH-1:0]    weight_wr_addr, activation_wr_addr, loader_addr;
    reg                     s_axis_tready_reg;
    reg                     weight_load_en, activation_load_en;
    reg [DATA_WIDTH-1:0]    weight_data_to_core, activation_data_to_core;
    reg                     start_computation;

    assign s_axis_tready = s_axis_tready_reg;

    reg [DATA_WIDTH-1:0] weight_buffer      [0:BUFFER_DEPTH-1];
    reg [DATA_WIDTH-1:0] activation_buffer  [0:BUFFER_DEPTH-1];

    always @(posedge aclk) begin
        if (~aresetn) begin
            stream_state <= IDLE;
            s_axis_tready_reg <= 0;
            weight_wr_addr <= 0;
            activation_wr_addr <= 0;
            loader_addr <= 0;
            weight_load_en <= 0;
            activation_load_en <= 0;
            start_computation <= 0;
        end else begin
            weight_load_en <= 0;
            activation_load_en <= 0;
            start_computation <= 0;

            case (stream_state)
                IDLE: begin
                    s_axis_tready_reg <= 1;
                    weight_wr_addr <= 0;
                    activation_wr_addr <= 0;
                    if (s_axis_tvalid) begin
                        weight_buffer[weight_wr_addr] <= s_axis_tdata[DATA_WIDTH-1:0];
                        weight_wr_addr <= weight_wr_addr + 1;
                        stream_state <= WRITE_WEIGHTS;
                    end
                end

                WRITE_WEIGHTS: begin
                    if (s_axis_tvalid) begin
                        weight_buffer[weight_wr_addr] <= s_axis_tdata[DATA_WIDTH-1:0];
                        if (s_axis_tlast) begin
                            stream_state <= WRITE_ACTIVATIONS;
                        end else begin
                            weight_wr_addr <= weight_wr_addr + 1;
                        end
                    end
                end

                WRITE_ACTIVATIONS: begin
                    if (s_axis_tvalid) begin
                        activation_buffer[activation_wr_addr] <= s_axis_tdata[DATA_WIDTH-1:0];
                        if (s_axis_tlast) begin
                            // weight_load_en <= 1;
                            stream_state <= LOAD_WEIGHTS;
                            s_axis_tready_reg <= 0;
                        end else begin
                            activation_wr_addr <= activation_wr_addr + 1;
                        end
                    end
                end

                // Add this to the stream FSM to actually load the buffers into the core
                LOAD_WEIGHTS: begin
                    if (loader_addr < SIZE * SIZE) begin
                        weight_load_en <= 1;
                        weight_data_to_core <= weight_buffer[loader_addr];
                        loader_addr <= loader_addr + 1;
                    end else begin
                        loader_addr <= 0;
                        stream_state <= LOAD_ACTIVATIONS;
                    end
                end

                LOAD_ACTIVATIONS: begin
                    if (loader_addr < SIZE * SIZE) begin
                        activation_data_to_core <= activation_buffer[loader_addr];
                        activation_load_en <= 1;
                        loader_addr <= loader_addr + 1;
                    end else begin
                        stream_state <= WAIT_START;
                    end
                end

                WAIT_START: begin
                    if (slv_reg[0][0]) begin // Start bit set
                        stream_state <= COMPUTING;
                        start_computation <= 1;
                    end
                end
                
                COMPUTING: begin
                    if (core_done) begin
                        stream_state <= IDLE;
                        s_axis_tready_reg <= 1;
                    end
                end
            endcase
        end
    end

    // ================================================
    // Connect to systolic array core
    // ================================================
    wire core_done, core_result_valid;
    wire [SIZE*SIZE*DATA_WIDTH*3-1:0] result_matrix;

    systolic_array_with_buffers #(
        .SIZE(SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
    ) core (
        .clk(aclk),
        .rst(~aresetn),
        .start(start_computation),
        .weight_load_en(weight_load_en),
        .weight_addr(loader_addr),
        .weight_data(weight_data_to_core),
        .activation_load_en(activation_load_en),
        .activation_addr(loader_addr),
        .activation_data(activation_data_to_core),
        .matrix_size(slv_reg[1][7:0]),
        .done(core_done),
        .result_matrix(result_matrix),
        .result_valid(core_result_valid)
    );

    // ================================================
    // Update status register
    // ================================================
    always @(posedge aclk) begin
        if (~aresetn) begin
            slv_reg[2] <= 0;
        end else begin
            slv_reg[2][0] <= core_done;
            slv_reg[2][1] <= core_result_valid;
            slv_reg[2][2] <= (stream_state == COMPUTING);
            slv_reg[2][7:4] <= stream_state;
        end
    end
// ================================================
// Store result_matrix in readable AXI registers
// ================================================
integer ii, jj;
always @(posedge aclk) begin
    if (~aresetn) begin
        for (ii = 3; ii < 3 + SIZE*SIZE; ii = ii + 1) begin
            slv_reg[ii] <= 0;
        end
    end else if (core_done) begin
        for (ii = 0; ii < SIZE; ii = ii + 1) begin
            for (jj = 0; jj < SIZE; jj = jj + 1) begin
                slv_reg[3 + ii*SIZE + jj] <= result_matrix[(ii*SIZE + jj)*3*DATA_WIDTH +: 3*DATA_WIDTH];
            end
        end
    end
end

    assign done = core_done;
    assign result_valid = core_result_valid;

endmodule