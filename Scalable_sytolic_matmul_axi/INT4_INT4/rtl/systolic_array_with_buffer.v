module systolic_array_with_buffers #(
    parameter SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter BUFFER_DEPTH = 64
)(
    input clk,
    input rst,
    input start,
    
    // Weight buffer interface
    input weight_load_en,
    input [$clog2(BUFFER_DEPTH)-1:0] weight_addr,
    input [DATA_WIDTH-1:0] weight_data,
    // input [DATA_WIDTH-1:0] weight_buffer [0:BUFFER_DEPTH-1];
    // input [DATA_WIDTH-1:0] activation_buffer [0:BUFFER_DEPTH-1];
    
    // Activation buffer interface
    input activation_load_en,
    input [$clog2(BUFFER_DEPTH)-1:0] activation_addr,
    input [DATA_WIDTH-1:0] activation_data,
    
    // Matrix dimensions
    input [$clog2(SIZE+1)-1:0] matrix_size, // Actual size (1 to SIZE)
    
    // Output interface
    output reg done,
    output reg [SIZE*SIZE*3*DATA_WIDTH-1:0] result_matrix,
    output reg result_valid
);

    // Internal parameters
    localparam ADDR_WIDTH = $clog2(BUFFER_DEPTH);
    
    // Weight buffer
    reg [DATA_WIDTH-1:0] weight_buffer [0:BUFFER_DEPTH-1];
    
    // Activation buffer
    reg [DATA_WIDTH-1:0] activation_buffer [0:BUFFER_DEPTH-1];
    
    // Systolic array connections
    wire [DATA_WIDTH-1:0] north_data [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] west_data [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] south_data [0:SIZE-1][0:SIZE-1];
    wire [DATA_WIDTH-1:0] east_data [0:SIZE-1][0:SIZE-1];
    wire [3*DATA_WIDTH-1:0] pe_results [0:SIZE-1][0:SIZE-1];
    
    // Control signals
    reg computing;
    reg [$clog2(3*SIZE+1)-1:0] cycle_count;
    reg [$clog2(SIZE+1)-1:0] current_size;
    
    // Input staging registers for proper timing
    reg [DATA_WIDTH-1:0] north_inputs [0:SIZE-1];
    reg [DATA_WIDTH-1:0] west_inputs [0:SIZE-1];
    
    // Loop variables
    integer k1, k2, k3, ii, jj;
    
    // Generate PE array
    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : row_gen
            for (j = 0; j < SIZE; j = j + 1) begin : col_gen
                // Connect north inputs
                assign north_data[i][j] = (i == 0) ? north_inputs[j] : south_data[i-1][j];
                
                // Connect west inputs
                assign west_data[i][j] = (j == 0) ? west_inputs[i] : east_data[i][j-1];
                
                // Instantiate PE
                pe #(.DATA_WIDTH(DATA_WIDTH)) processing_element (
                    .clk(clk),
                    // .rst(rst | ~computing),
                    .rst(rst),
                    .inp_north(north_data[i][j]),
                    .inp_west(west_data[i][j]),
                    .outp_south(south_data[i][j]),
                    .outp_east(east_data[i][j]),
                    .result(pe_results[i][j])
                );
            end
        end
    endgenerate
    
    // Buffer write operations
   
    always @(negedge clk) begin
        if (weight_load_en) begin
            weight_buffer[weight_addr-1] <= weight_data;
        end
        
        if (activation_load_en) begin
            activation_buffer[activation_addr-1] <= activation_data;
        end
    end
    
    // Main control FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            computing <= 0;
            done <= 0;
            result_valid <= 0;
            cycle_count <= 0;
            current_size <= 0;
            
            // Clear input registers
            for (k1 = 0; k1 < SIZE; k1 = k1 + 1) begin
                north_inputs[k1] <= 0;
                west_inputs[k1] <= 0;
            end
            
        end else begin
            if (start && !computing && !done) begin
                // Start computation
                computing <= 1;
                done <= 0;
                result_valid <= 0;
                cycle_count <= 0;
                
                current_size <= matrix_size;
                
                // Clear inputs
                for (k1 = 0; k1 < SIZE; k1 = k1 + 1) begin
                    north_inputs[k1] <= 0;
                    west_inputs[k1] <= 0;
                end
                
            end else if (computing) begin
                cycle_count <= cycle_count + 1;
                
                // Feed data into the array with proper timing
                // North inputs (weights) - column-wise, staggered by column index
                for (k2 = 0; k2 < SIZE; k2 = k2 + 1) begin
                    if (cycle_count >= k2 && (cycle_count - k2) < current_size) begin
                        north_inputs[k2] <= weight_buffer[(cycle_count - k2) * SIZE + k2];
                    end else begin
                        north_inputs[k2] <= 0;
                    end
                end
                
                // West inputs (activations) - row-wise, staggered by row index
                for (k3 = 0; k3 < SIZE; k3 = k3 + 1) begin
                    if (cycle_count >= k3 && (cycle_count - k3) < current_size) begin
                        west_inputs[k3] <= activation_buffer[k3 * SIZE + (cycle_count - k3)];
                    end else begin
                        west_inputs[k3] <= 0;
                    end
                end
                
                // Check if computation is complete
                if (cycle_count >= (2 * current_size + SIZE - 1)) begin
                    computing <= 0;
                    done <= 1;
                    result_valid <= 1;
                    
                    // Capture results - Fixed indexing
                    for (ii = 0; ii < SIZE; ii = ii + 1) begin
                        for (jj = 0; jj < SIZE; jj = jj + 1) begin
                            result_matrix[(ii*SIZE + jj)*3*DATA_WIDTH +: 3*DATA_WIDTH] <= pe_results[ii][jj];
                        end
                    end
                end
            end else if (done) begin
                // Keep done high until next start
                if (start) begin
                    done <= 0;
                end
            end
        end
    end

endmodule