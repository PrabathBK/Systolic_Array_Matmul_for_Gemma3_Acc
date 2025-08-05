// fp16_mult.v
module fp16_mult (
    input wire clk,
    input wire [15:0] a,  // FP16
    input wire [15:0] b,  // FP16
    output wire [31:0] result,  // FP32
    output wire result_valid    // valid flag from IP
);

    // Synthesis: use Xilinx Floating Point IP core
    floating_point_0 u_fp_mult (
        .aclk(clk),
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(a),
        .s_axis_b_tvalid(1'b1),
        .s_axis_b_tdata(b),
        .m_axis_result_tvalid(result_valid),
        .m_axis_result_tdata(result)
    );

endmodule
