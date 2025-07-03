`timescale 1ns / 1ps

module tb_systolic_array_axi_stream;

    // Parameters
    parameter SIZE = 8;
    parameter DATA_WIDTH = 4;
    parameter BUFFER_DEPTH = 256; 
    parameter CLK_PERIOD = 10; // 100MHz
    
    // AXI4-Lite signals
    reg aclk;
    reg aresetn;
    
    // AXI4-Lite Control Interface
    reg [31:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg [31:0]  s_axi_wdata;
    reg [3:0]   s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg [31:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    
    // AXI4-Stream Data Interface
    reg [31:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    
    // Debug outputs
    wire        done;
    wire        result_valid;
    
    // Test matrices
    reg [DATA_WIDTH-1:0] weight_matrix [0:SIZE-1][0:SIZE-1];
    reg [DATA_WIDTH-1:0] activation_matrix [0:SIZE-1][0:SIZE-1];
    reg [3*DATA_WIDTH-1:0] expected_result [0:SIZE-1][0:SIZE-1];
    
    reg [31:0] status_data;
    
    // Test control
    integer i, j, k;
    integer error_count;
    
    // DUT instantiation
    systolic_array_axi_stream #(
        .SIZE(SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .done(done),
        .result_valid(result_valid)
    );
    
    // Clock generation
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end
    
    // ================================================
    // Task: AXI4-Lite Write (Fixed timing)
    // ================================================
    task axi_lite_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Setup write address and data
            @(posedge aclk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hF;
            s_axi_wvalid = 1;
            s_axi_bready = 1;
            
            // Wait for both address and data to be ready
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge aclk);
            end
            
            // Deassert after one cycle
            @(posedge aclk);
            s_axi_awvalid = 0;
            s_axi_wvalid = 0;
            
            // Wait for write response
            while (!s_axi_bvalid) begin
                @(posedge aclk);
            end
            
            @(posedge aclk);
            s_axi_bready = 0;
            
            $display("AXI Write: addr=0x%08x, data=0x%08x, resp=%b", addr, data, s_axi_bresp);
        end
    endtask
    
    // ================================================
    // Task: AXI4-Lite Read (Fixed timing)
    // ================================================
    task axi_lite_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            s_axi_rready = 1;
            
            // Wait for address ready
            while (!s_axi_arready) begin
                @(posedge aclk);
            end
            
            @(posedge aclk);
            s_axi_arvalid = 0;
            
            // Wait for read data
            while (!s_axi_rvalid) begin
                @(posedge aclk);
            end
            
            data = s_axi_rdata;
            @(posedge aclk);
            s_axi_rready = 0;
            
            $display("AXI Read: addr=0x%08x, data=0x%08x, resp=%b", addr, data, s_axi_rresp);
        end
    endtask
    
    // ================================================
    // Task: Send Stream Data (With timeout)
    // ================================================
    task send_stream_data;
        input [DATA_WIDTH-1:0] data;
        input last;
        integer timeout_count;
        begin
            timeout_count = 0;
            @(posedge aclk);
            s_axis_tdata = {24'h0, data};
            s_axis_tvalid = 1;
            s_axis_tlast = last;
            
            // Wait for ready with timeout
            while (!s_axis_tready && timeout_count < 1000) begin
                @(posedge aclk);
                timeout_count = timeout_count + 1;
            end
            
            if (timeout_count >= 1000) begin
                $display("ERROR: Stream data timeout for data=0x%02x", data);
            end else begin
                $display("Stream data sent: 0x%02x, last=%b", data, last);
            end
            
            @(posedge aclk);
            s_axis_tvalid = 0;
            s_axis_tlast = 0;
        end
    endtask
    
    // ================================================
    // Task: Initialize Test Matrices
    // ================================================
    task init_test_matrices;
        begin
            // Initialize weight matrix (simple incrementing pattern)
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    weight_matrix[i][j] = i * SIZE + j ;
                end
            end
            
            // Initialize activation matrix (simple incrementing pattern)
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    activation_matrix[i][j] = i * SIZE + j ;
                end
            end
            
            // Calculate expected result (software matrix multiplication)
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    expected_result[i][j] = 0;
                    for (k = 0; k < SIZE; k = k + 1) begin
                        expected_result[i][j] = expected_result[i][j] + 
                                              (weight_matrix[i][k] * activation_matrix[k][j]);
                    end
                end
            end
        end
    endtask
    
    // ================================================
    // Task: Send Weight Matrix via Stream
    // ================================================
    task send_weight_matrix;
        begin
            $display("Sending weight matrix...");
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    if (i == SIZE-1 && j == SIZE-1) begin
                        send_stream_data(weight_matrix[i][j], 1); // Last weight
                    end else begin
                        send_stream_data(weight_matrix[i][j], 0);
                    end
                end
            end
            $display("Weight matrix sent successfully");
        end
    endtask
    
    // ================================================
    // Task: Send Activation Matrix via Stream
    // ================================================
    task send_activation_matrix;
        begin
            $display("Sending activation matrix...");
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    if (i == SIZE-1 && j == SIZE-1) begin
                        send_stream_data(activation_matrix[i][j], 1); // Last activation
                    end else begin
                        send_stream_data(activation_matrix[i][j], 0);
                    end
                end
            end
            $display("Activation matrix sent successfully");
        end
    endtask
    
    // ================================================
    // Task: Print Matrix
    // ================================================
    task print_matrix;
        input [8*20:1] name;
        input integer matrix_type; // 0=weight, 1=activation, 2=result
        begin
            $display("\n%s:", name);
            for (i = 0; i < SIZE; i = i + 1) begin
                $write("  ");
                for (j = 0; j < SIZE; j = j + 1) begin
                    if (matrix_type == 0) begin
                        $write("%3d ", weight_matrix[i][j]);
                    end else if (matrix_type == 1) begin
                        $write("%3d ", activation_matrix[i][j]);
                    end else begin
                        $write("%5d ", expected_result[i][j]);
                    end
                end
                $display("");
            end
        end
    endtask
    
    // // ================================================
    // // Task: Check Results (With timeout)
    // // ================================================
    // task check_results_old;
    //     reg [31:0] read_data;
    //     integer timeout_count;
    //     begin
    //         $display("\nWaiting for computation to complete...");
    //         error_count = 0;
    //         timeout_count = 0;
            
    //         // Wait for computation with timeout
    //         while (!done && timeout_count < 5000) begin
    //             @(posedge aclk);
    //             timeout_count = timeout_count + 1;
    //         end
            
    //         if (timeout_count >= 5000) begin
    //             $display("ERROR: Computation timeout!");
    //             error_count = error_count + 1;
    //         end else begin
    //             $display("Computation completed in %d cycles", timeout_count);
    //         end
            
    //         if (result_valid) begin
    //             $display("Result valid signal asserted correctly");
    //         end else begin
    //             $display("ERROR: Result valid signal not asserted");
    //             error_count = error_count + 1;
    //         end
            
    //         // Print expected results
    //         print_matrix("Expected Result", 2);
            
    //         if (error_count == 0) begin
    //             $display("\n*** TEST PASSED ***");
    //         end else begin
    //             $display("\n*** TEST FAILED with %d errors ***", error_count);
    //         end
    //     end
    // endtask

    task check_results;
    reg [31:0] read_data;
    integer err, idx;
    begin
        $display("\nChecking results by reading back via AXI-Lite...");
        err = 0;

        // Wait for computation to finish
        wait(done);
        wait(result_valid);
        $display("Computation done. Reading results...");

        for (i = 0; i < SIZE; i = i + 1) begin
            for (j = 0; j < SIZE; j = j + 1) begin
                idx = 3 + i*SIZE + j; // slv_reg index
                axi_lite_read(idx*4, read_data); // 32-bit word address
                if (read_data !== expected_result[i][j]) begin
                    $display("Mismatch at (%0d,%0d): Expected=%0d, Got=%0d",
                        i, j, expected_result[i][j], read_data);
                    err = err + 1;
                end else begin
                    $display("Match at (%0d,%0d): %0d", i, j, read_data);
                end
            end
        end

        if (err == 0)
            $display("\n*** RESULT MATCH: TEST PASSED ***");
        else
            $display("\n*** RESULT MISMATCH: %0d errors ***", err);
    end
endtask

    
    // ================================================
    // Task: Reset System
    // ================================================
    task reset_system;
        begin
            $display("Resetting system...");
            aresetn = 0;
            s_axi_awaddr = 0;
            s_axi_awvalid = 0;
            s_axi_wdata = 0;
            s_axi_wstrb = 0;
            s_axi_wvalid = 0;
            s_axi_bready = 0;
            s_axi_araddr = 0;
            s_axi_arvalid = 0;
            s_axi_rready = 0;
            s_axis_tdata = 0;
            s_axis_tvalid = 0;
            s_axis_tlast = 0;
            
            repeat(10) @(posedge aclk);
            aresetn = 1;
            repeat(10) @(posedge aclk);
            $display("Reset complete");
        end
    endtask
    
    // ================================================
    // Main Test Sequence
    // ================================================
    initial begin
        $display("Starting Systolic Array AXI Stream Testbench");
        $display("SIZE = %d, DATA_WIDTH = %d", SIZE, DATA_WIDTH);
        
        // Initialize
        init_test_matrices();
        
        // Print input matrices
        print_matrix("Weight Matrix", 0);
        print_matrix("Activation Matrix", 1);
        
        // Reset the system
        reset_system();
        
        // Test 1: Basic Matrix Multiplication
        $display("\n=== Test 1: Basic Matrix Multiplication ===");
        
        // Set matrix size via AXI-Lite
        axi_lite_write(32'h4, SIZE); // Write to register 1 (matrix size)
        
        // Read back to verify
        axi_lite_read(32'h4, status_data);
        
        // Send weight matrix
        send_weight_matrix();
        
        // Small delay between matrices
        repeat(20) @(posedge aclk);
        
        // Send activation matrix
        send_activation_matrix();
        
        // Small delay before starting
        repeat(20) @(posedge aclk);
        
        // Start computation via AXI-Lite
        $display("Starting computation...");
        axi_lite_write(32'h0, 32'h1); // Write start bit to register 0
        
        // Check results
        check_results();
        
        // Test 2: Status Register Read
        $display("\n=== Test 2: Status Register Test ===");
        axi_lite_read(32'h8, status_data); // Read status register
        $display("Status register: 0x%08x", status_data);
        
        // Finish simulation
        repeat(100) @(posedge aclk);
        $display("\n=== Testbench Complete ===");
        $finish;
    end
    
    // ================================================
    // Timeout Watchdog (Increased timeout)
    // ================================================
    initial begin
        #(CLK_PERIOD * 50000); // 50000 clock cycles timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end
    
    // ================================================
    // Signal Monitoring
    // ================================================
    always @(posedge aclk) begin
        if (done && !$past(done)) begin
            $display("Time %t: Computation done signal asserted", $time);
        end
        if (result_valid && !$past(result_valid)) begin
            $display("Time %t: Result valid signal asserted", $time);
        end
    end
    
    // ================================================
    // Debug: Stream State Monitoring
    // ================================================
    // always @(posedge aclk) begin
    //     if (s_axis_tvalid && s_axis_tready) begin
    //         $display("Time %t: Stream data accepted: 0x%08x, last=%b", 
    //                 $time, s_axis_tdata, s_axis_tlast);
    //     end
    // end
    
    // ================================================
    // Debug: Internal State Monitoring
    // ================================================
    // always @(posedge aclk) begin
    //     // Monitor internal stream state if accessible
    //     $display("Time %t: Stream ready=%b, valid=%b, internal_state=%b", 
    //             $time, s_axis_tready, s_axis_tvalid, dut.stream_state);
    // end

endmodule