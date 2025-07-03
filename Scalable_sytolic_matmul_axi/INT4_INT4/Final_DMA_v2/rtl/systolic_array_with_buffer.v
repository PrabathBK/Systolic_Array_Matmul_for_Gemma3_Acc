module systolic_array_with_buffers #(
    parameter SIZE = 4,
    parameter DATA_WIDTH = 4,              // INT4 data
    parameter BUFFER_DEPTH = 64
)(
    input clk,
    input rst,
    input start,

    // Weight buffer interface
    input weight_load_en,
    input [$clog2(BUFFER_DEPTH)-1:0] weight_addr,
    input [DATA_WIDTH*64-1:0] weight_data, // 256 bits = 64 x INT4

    // Activation buffer interface
    input activation_load_en,
    input [$clog2(BUFFER_DEPTH)-1:0] activation_addr,
    input [DATA_WIDTH*64-1:0] activation_data,

    // Matrix dimensions
    input [$clog2(SIZE+1)-1:0] matrix_size,

    // Output interface
    output reg done,
    output reg [SIZE*SIZE*2*DATA_WIDTH-1:0] result_matrix,
    output reg result_valid
);

    // Systolic array interconnections
    wire [DATA_WIDTH-1:0] north_data [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] west_data  [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] south_data [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] east_data  [0:SIZE-1][0:SIZE-1];
    wire [2*DATA_WIDTH-1:0] pe_results [0:SIZE-1][0:SIZE-1];

    // Input staging registers
    reg [DATA_WIDTH-1:0] north_inputs [0:SIZE-1];
    reg [DATA_WIDTH-1:0] west_inputs [0:SIZE-1];

    reg computing;
    reg [$clog2(3*SIZE+1)-1:0] cycle_count;
    reg [$clog2(SIZE+1)-1:0] current_size;
    reg capture_results;  // Added flag to delay result capture

    integer i, j;

    // ----------------- PE Array -----------------
    genvar row, col;
    generate
        for (row = 0; row < SIZE; row = row + 1) begin : row_gen
            for (col = 0; col < SIZE; col = col + 1) begin : col_gen
                // Connect inputs
                assign north_data[row][col] = (row == 0) ? north_inputs[col] : south_data[row-1][col];
                assign west_data[row][col]  = (col == 0) ? west_inputs[row]  : east_data[row][col-1];

                // PE instance
                pe #(.DATA_WIDTH(DATA_WIDTH)) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .inp_north(north_data[row][col]),
                    .inp_west(west_data[row][col]),
                    .outp_south(south_data[row][col]),
                    .outp_east(east_data[row][col]),
                    .result(pe_results[row][col])
                );
            end
        end
    endgenerate

    // ----------------- Control FSM -----------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            computing     <= 0;
            cycle_count   <= 0;
            result_matrix <= 0;
            done          <= 0;
            result_valid  <= 0;
            capture_results <= 0;
        end else begin
            if (start && !computing && !done) begin
                computing   <= 1;
                cycle_count <= 0;
                done        <= 0;
                result_valid <= 0;
                capture_results <= 0;

                // Clear input registers
                for (i = 0; i < SIZE; i = i + 1) begin
                    north_inputs[i] <= 0;
                    west_inputs[i]  <= 0;
                end

                current_size <= matrix_size;

            end else if (computing) begin
                cycle_count <= cycle_count + 1;

                // Assign inputs to top row and left column
                for (i = 0; i < SIZE; i = i + 1) begin
                    if (cycle_count >= i && (cycle_count - i) < current_size) begin
                        // Extract weight and activation from packed data
                        north_inputs[i] <= weight_data[DATA_WIDTH * ((cycle_count - i) * SIZE + i) +: DATA_WIDTH];
                        west_inputs[i]  <= activation_data[DATA_WIDTH * (i * SIZE + (cycle_count - i)) +: DATA_WIDTH];
                    end else begin
                        north_inputs[i] <= 0;
                        west_inputs[i]  <= 0;
                    end
                end

                // Check if all data passed through
                if (cycle_count >= (2 * current_size + SIZE - 2)) begin
                    computing <= 0;
                    capture_results <= 1;  // Set flag to capture results next cycle
                end
                
            end else if (capture_results) begin
                // Capture results one cycle after computing ends
                capture_results <= 0;
                done <= 1;
                result_valid <= 1;

                // Store all PE results - now captured at the right time
                for (i = 0; i < SIZE; i = i + 1) begin
                    for (j = 0; j < SIZE; j = j + 1) begin
                        result_matrix[(i*SIZE + j)*2*DATA_WIDTH +: 2*DATA_WIDTH] <= pe_results[i][j];
                    end
                end
                
            end else if (done && start) begin
                done <= 0;
            end
        end
    end

endmodule