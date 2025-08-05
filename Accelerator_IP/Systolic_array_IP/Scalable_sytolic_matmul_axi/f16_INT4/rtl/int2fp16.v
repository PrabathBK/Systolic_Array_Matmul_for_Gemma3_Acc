// int2fp16.v
module int2fp16 (
    input [3:0] in,
    output reg [15:0] out
);

    always @(*) begin
        case (in)
            4'd0: out = 16'h0000;
            4'd1: out = 16'h3C00; // 1.0
            4'd2: out = 16'h4000; // 2.0
            4'd3: out = 16'h4200; // 3.0
            4'd4: out = 16'h4400; // 4.0
            4'd5: out = 16'h4500; // 5.0
            4'd6: out = 16'h4600; // 6.0
            4'd7: out = 16'h4700; // 7.0
            4'd8: out = 16'h4800; // 8.0
            4'd9: out = 16'h4900; // 9.0
            4'd10: out = 16'h4A00; // 10.0
            4'd11: out = 16'h4B00; // 11.0
            4'd12: out = 16'h4C00; // 12.0
            4'd13: out = 16'h4D00; // 13.0
            4'd14: out = 16'h4E00; // 14.0
            4'd15: out = 16'h4F00; // 15.0
            default: out = 16'h0000;
        endcase
    end

endmodule
