// Self-checking testbench for systolic array with buffers
module tb_systolic_array_with_buffers;

    // Parameters for 8x8 array with 4-bit data
    parameter SIZE = 8;
    parameter DATA_WIDTH = 4;
    parameter BUFFER_DEPTH = 256;
    parameter ADDR_WIDTH = $clog2(BUFFER_DEPTH);
    parameter RESULT_WIDTH = 2 * DATA_WIDTH;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // Control signals
    reg start;
    wire done;
    wire result_valid;
    
    // Buffer interfaces
    reg weight_load_en;
    reg [ADDR_WIDTH-1:0] weight_addr;
    reg [DATA_WIDTH-1:0] weight_data;
    
    reg activation_load_en;
    reg [ADDR_WIDTH-1:0] activation_addr;
    reg [DATA_WIDTH-1:0] activation_data;
    
    reg [$clog2(SIZE+1)-1:0] matrix_size;
    
    // Output
    wire [SIZE*SIZE*RESULT_WIDTH-1:0] result_matrix;
    
    // Test matrices - using 4-bit values (0-15)
    reg [DATA_WIDTH-1:0] test_matrix_a [0:SIZE-1][0:SIZE-1];
    reg [DATA_WIDTH-1:0] test_matrix_b [0:SIZE-1][0:SIZE-1];
    reg [RESULT_WIDTH-1:0] expected_result [0:SIZE-1][0:SIZE-1];
    reg [RESULT_WIDTH-1:0] actual_result [0:SIZE-1][0:SIZE-1];
    
    // Test control and statistics
    integer test_case;
    integer errors;
    integer total_tests;
    integer passed_tests;
    integer i, j, k;
    integer seed;
    
    // Performance monitoring
    integer start_time, end_time, computation_cycles;
    
    // DUT instantiation
    systolic_array_with_buffers #(
        .SIZE(SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .weight_load_en(weight_load_en),
        .weight_addr(weight_addr),
        .weight_data(weight_data),
        .activation_load_en(activation_load_en),
        .activation_addr(activation_addr),
        .activation_data(activation_data),
        .matrix_size(matrix_size),
        .done(done),
        .result_matrix(result_matrix),
        .result_valid(result_valid)
    );
    
    // Clock generation - 100MHz
    always #5 clk = ~clk;
    
    // Main test procedure
    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        start = 0;
        weight_load_en = 0;
        activation_load_en = 0;
        weight_addr = 0;
        weight_data = 0;
        activation_addr = 0;
        activation_data = 0;
        matrix_size = SIZE;
        test_case = 0;
        errors = 0;
        total_tests = 0;
        passed_tests = 0;
        seed = 12345; // Fixed seed for reproducible results
        
        $display("========================================");
        $display("8x8 Systolic Array INT4 Testbench");
        $display("========================================");
        $display("Array Size: %0dx%0d", SIZE, SIZE);
        $display("Data Width: %0d bits (INT4: 0-15)", DATA_WIDTH);
        $display("Result Width: %0d bits (0-1920 max)", RESULT_WIDTH);
        $display("Buffer Depth: %0d entries", BUFFER_DEPTH);
        $display("========================================");
        
        // Reset sequence
        #50 rst = 0;
        #40;
        
        // Test Suite 1: Basic functionality tests
        $display("\n=== BASIC FUNCTIONALITY TESTS ===");
        
        initialization();
        
        // Test 1: Identity matrix
        run_identity_test();
        
        // Test 2: Zero matrix
        run_zero_test();

        // Test 3: Ones matrix
        run_ones_test();
        
        // Test 4: Diagonal matrix
        run_diagonal_test();
        
        // Test Suite 2: Randomized tests
        $display("\n=== RANDOMIZED TESTS ===");
        
        // Run multiple random tests with different characteristics
        for (test_case = 1; test_case <= 20; test_case = test_case + 1) begin
            $display("\n--- Random Test Case %0d ---", test_case);
            
            // Vary the random characteristics
            case (test_case % 4)
                0: run_small_values_test();    // Values 0-3
                1: run_medium_values_test();   // Values 0-7
                2: run_large_values_test();    // Values 8-15
                3: run_mixed_values_test();    // Values 0-15
            endcase
        end
        
        // Test Suite 3: Edge cases
        $display("\n=== EDGE CASE TESTS ===");
        
        // Test with maximum values
        run_max_values_test();
        
        // Test with sparse matrices
        run_sparse_test();
        
        // Test with pattern matrices
        run_pattern_test();
        
        // Performance test
        $display("\n=== PERFORMANCE TEST ===");
        run_performance_test();
        
        // Final summary
        print_final_summary();
        
        $display("\nTestbench completed at time %0t", $time);
        $finish;
    end
    
    // Task to load matrices into buffers
    task load_matrices;
        begin
            // Load weight matrix (Matrix B) - column by column
            weight_load_en = 1;
            for (j = 0; j < SIZE; j = j + 1) begin
                for (i = 0; i < SIZE; i = i + 1) begin
                    weight_addr = j * SIZE + i;
                    weight_data = test_matrix_b[i][j];
                    @(posedge clk);
                end
            end
            weight_load_en = 0;
            
            // Load activation matrix (Matrix A) - row by row
            activation_load_en = 1;
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    activation_addr = i * SIZE + j;
                    activation_data = test_matrix_a[i][j];
                    @(posedge clk);
                end
            end
            activation_load_en = 0;
            @(posedge clk);
        end
    endtask
    
    // Generic test runner
    task run_matrix_test;
        input [200*8-1:0] test_name;
        begin
            total_tests = total_tests + 1;
            $display("Running %s...", test_name);
            
            load_matrices();
            
            // Record start time
            start_time = $time;
            
            // Start computation
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait for completion
            @(posedge done);
            end_time = $time;
            computation_cycles = (end_time - start_time) / 10;
            
            @(posedge clk);
            
            // Extract and check results
            extract_results();
            calculate_expected_result();
            
            if (check_results(test_name)) begin
                passed_tests = passed_tests + 1;
                $display("✓ %s PASSED (Cycles: %0d)", test_name, computation_cycles);
            end else begin
                $display("✗ %s FAILED", test_name);
            end
        end
    endtask
    
    // Extract results from output vector
    task extract_results;
        begin
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    actual_result[i][j] = result_matrix[((i*SIZE + j + 1)*RESULT_WIDTH)-1 -: RESULT_WIDTH];
                end
            end
        end
    endtask
    
    // Calculate expected result using software multiplication
    task calculate_expected_result;
        integer sum;
        begin
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    sum = 0;
                    for (k = 0; k < SIZE; k = k + 1) begin
                        sum = sum + (test_matrix_a[i][k] * test_matrix_b[k][j]);
                    end
                    expected_result[i][j] = sum;
                end
            end
        end
    endtask
    
    // Check results and return pass/fail
    function check_results;
        input [200*8-1:0] test_name;
        integer local_errors;
        integer max_error_display;
        begin
            local_errors = 0;
            max_error_display = 5; // Limit error display for readability
            
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
//                 $display("  Value at [%0d][%0d]: Expected %0d, Got %0d",i, j, expected_result[i][j], actual_result[i][j]);
                    if (expected_result[i][j] !== actual_result[i][j]) begin
                        if (local_errors < max_error_display) begin
                            $display("  ERROR at [%0d][%0d]: Expected %0d, Got %0d", 
                                    i, j, expected_result[i][j], actual_result[i][j]);
                        end
                        local_errors = local_errors + 1;
                    end
                end
            end
            
            if (local_errors > max_error_display) begin
                $display("  ... and %0d more errors", local_errors - max_error_display);
            end
            
            errors = errors + local_errors;
            check_results = (local_errors == 0);
        end
    endfunction
    // Test Cases
    task initialization;
        begin
            // Matrix A 
            clear_matrices();
            for (i = 0; i < SIZE; i = i + 1) begin
                test_matrix_a[i][i] = 1;
            end
            
            // Matrix B 
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_b[i][j] = (i * SIZE + j) % 16; // Keep in 4-bit range
                end
            end
            
            
            load_matrices();
            
            // Record start time
            start_time = $time;
            
            // Start computation
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait for completion
            @(posedge done);
            end_time = $time;
            computation_cycles = (end_time - start_time) / 10;
            
            @(posedge clk);
            

            $display("Initialization...");

        end
    endtask
    
    // Test Cases
    task run_identity_test;
        begin
            // Matrix A = Identity
            clear_matrices();
            for (i = 0; i < SIZE; i = i + 1) begin
                test_matrix_a[i][i] = 1;
            end
            
            // Matrix B = Sequential values
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_b[i][j] = (i * SIZE + j) % 16; // Keep in 4-bit range
                end
            end
            
            run_matrix_test("Identity Matrix Test");
        end
    endtask
    
    task run_zero_test;
        begin
            clear_matrices();
            // All zeros - result should be all zeros
            run_matrix_test("Zero Matrix Test");
        end
    endtask
    
    task run_ones_test;
        begin
            clear_matrices();
            // Fill with ones
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_a[i][j] = 1;
                    test_matrix_b[i][j] = 1;
                end
            end
            run_matrix_test("Ones Matrix Test");
        end
    endtask
    
    task run_diagonal_test;
        begin
            clear_matrices();
            // Diagonal matrices
            for (i = 0; i < SIZE; i = i + 1) begin
                test_matrix_a[i][i] = (i + 1) % 16;
                test_matrix_b[i][i] = (i + 2) % 16;
            end
            run_matrix_test("Diagonal Matrix Test");
        end
    endtask
    
    task run_small_values_test;
        begin
            generate_random_matrices(0, 3); // Values 0-3
            run_matrix_test("Small Values Random Test");
        end
    endtask
    
    task run_medium_values_test;
        begin
            generate_random_matrices(0, 7); // Values 0-7
            run_matrix_test("Medium Values Random Test");
        end
    endtask
    
    task run_large_values_test;
        begin
            generate_random_matrices(8, 15); // Values 8-15
            run_matrix_test("Large Values Random Test");
        end
    endtask
    
    task run_mixed_values_test;
        begin
            generate_random_matrices(0, 15); // Full range
            run_matrix_test("Mixed Values Random Test");
        end
    endtask
    
    task run_max_values_test;
        begin
            clear_matrices();
            // Fill with maximum 4-bit value (15)
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_a[i][j] = 15;
                    test_matrix_b[i][j] = 15;
                end
            end
            run_matrix_test("Maximum Values Test");
        end
    endtask
    
    task run_sparse_test;
        begin
            clear_matrices();
            // Sparse matrices - only few non-zero elements
            for (i = 0; i < SIZE; i = i + 2) begin
                for (j = 0; j < SIZE; j = j + 2) begin
                    test_matrix_a[i][j] = $random(seed) % 16;
                    test_matrix_b[i][j] = $random(seed) % 16;
                    if (test_matrix_a[i][j] < 0) test_matrix_a[i][j] = -test_matrix_a[i][j];
                    if (test_matrix_b[i][j] < 0) test_matrix_b[i][j] = -test_matrix_b[i][j];
                end
            end
            run_matrix_test("Sparse Matrix Test");
        end
    endtask
    
    task run_pattern_test;
        begin
            clear_matrices();
            // Checkerboard pattern
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_a[i][j] = ((i + j) % 2) ? 7 : 3;
                    test_matrix_b[i][j] = ((i + j) % 2) ? 5 : 9;
                end
            end
            run_matrix_test("Pattern Matrix Test");
        end
    endtask
    
    task run_performance_test;
        integer perf_start, perf_end, total_cycles;
        begin
            $display("Running performance benchmark...");
            
            // Generate large random matrices
            generate_random_matrices(0, 15);
            load_matrices();
            
            perf_start = $time;
            
            // Run 5 consecutive computations
            for (i = 0; i < 5; i = i + 1) begin
                start = 1;
                @(posedge clk);
                start = 0;
                @(posedge done);
                @(posedge clk);
            end
            
            perf_end = $time;
            total_cycles = (perf_end - perf_start) / 10;
            
            $display("Performance Results:");
            $display("  Total time for 5 computations: %0d cycles", total_cycles);
            $display("  Average per computation: %0d cycles", total_cycles / 5);
            $display("  Theoretical minimum: %0d cycles", 2 * SIZE + SIZE - 1);
        end
    endtask
    
    // Helper tasks
    task clear_matrices;
        begin
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_a[i][j] = 0;
                    test_matrix_b[i][j] = 0;
                end
            end
        end
    endtask
    
    task generate_random_matrices;
        input integer min_val;
        input integer max_val;
        integer range;
        begin
            range = max_val - min_val + 1;
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    test_matrix_a[i][j] = min_val + ($random(seed) % range);
                    test_matrix_b[i][j] = min_val + ($random(seed) % range);
                    if (test_matrix_a[i][j] < 0) test_matrix_a[i][j] = -test_matrix_a[i][j];
                    if (test_matrix_b[i][j] < 0) test_matrix_b[i][j] = -test_matrix_b[i][j];
                    // Ensure 4-bit range
                    test_matrix_a[i][j] = test_matrix_a[i][j] % 16;
                    test_matrix_b[i][j] = test_matrix_b[i][j] % 16;
                end
            end
        end
    endtask
    
    task print_final_summary;
        real pass_rate;
        begin
            pass_rate = (passed_tests * 100.0) / total_tests;
            
            $display("\n========================================");
            $display("FINAL TEST SUMMARY");
            $display("========================================");
            $display("Total Tests Run: %0d", total_tests);
            $display("Tests Passed: %0d", passed_tests);
            $display("Tests Failed: %0d", total_tests - passed_tests);
            $display("Pass Rate: %0.1f%%", pass_rate);
            $display("Total Errors: %0d", errors);
            
            if (passed_tests == total_tests) begin
                $display("\n ALL TESTS PASSED!");
                $display("8x8 INT4 Systolic Array is working correctly!");
            end else begin
                $display("\n SOME TESTS FAILED!");
                $display("Please check the implementation.");
            end
            
            $display("========================================");
        end
    endtask
    
    // Monitor signals for debugging
    always @(posedge start) begin
        $display("[%0t] Computation started", $time);
    end
    
    always @(posedge done) begin
        $display("[%0t] Computation completed", $time);
    end
    
    // Timeout protection
    initial begin
        #2000000; // 2ms timeout
        $display("ERROR: Testbench timeout!");
        $display("Current test case: %0d", test_case);
        $finish;
    end

endmodule
