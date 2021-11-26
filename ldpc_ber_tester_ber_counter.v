module ldpc_ber_tester_ber_counter (
    input                   clk,
    input                   resetn,

    input       [127:0]     last_mask,

    input       [127:0]     s_axis_dout_tdata,
    input                   s_axis_dout_tvalid,
    output reg              s_axis_dout_tready,
    input                   s_axis_dout_tlast,

    output reg  [ 31:0]     bit_errors,
    output                  active
);

    function automatic [6:0] popcount_8(input [7:0] bits);
        popcount_8 = bits[0] + bits[1] + bits[2] + bits[3] + bits[4] + bits[5] + bits[6] + bits[7];    
    endfunction

    function automatic [6:0] popcount_32(input [31:0] bits);
        popcount_32 = popcount_8(bits[7:0]) + popcount_8(bits[15:8]) + popcount_8(bits[23:16]) + popcount_8(bits[31:24]);
    endfunction

    reg [7:0] popcount_d [0:3];
    reg [7:0] popcount;
    reg [1:0] valid;
    reg       busy;

    assign active = busy | |valid;

    always @(posedge clk) begin
        if (!resetn) begin
            busy <= 'h0;
            bit_errors <= 'h0;
            s_axis_dout_tready <= 'h0;

            for (integer i = 0; i < 4; i = i + 1)
                popcount_d[i] <= 'h0;

            popcount <= 'h0;

            valid <= 'h0;
        end else begin
            s_axis_dout_tready <= 'h1;

            if (s_axis_dout_tready && s_axis_dout_tvalid) begin
                busy <= !s_axis_dout_tlast;

                if (s_axis_dout_tlast)
                    s_axis_dout_tready <= 'h0;

                valid[0] <= 1'b1;

                for (integer i = 0; i < 4; i = i + 1) begin
                    if (s_axis_dout_tlast)
                        popcount_d[i] <= popcount_32(s_axis_dout_tdata[i*32 +: 32] & last_mask[i*32 +: 32]);
                    else
                        popcount_d[i] <= popcount_32(s_axis_dout_tdata[i*32 +: 32]);
                end

            end else begin
                valid[0] <= 1'b0;
            end

            valid[1] <= valid[0];

            if (valid[0])
                popcount <= popcount_d[0] + popcount_d[1] + popcount_d[2] + popcount_d[3];

            if (valid[1])
                bit_errors <= bit_errors + {24'h0, popcount};
        end
    end

endmodule
