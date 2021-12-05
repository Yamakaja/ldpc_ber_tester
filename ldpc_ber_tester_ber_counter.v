module ldpc_ber_tester_ber_counter (
    input                   clk,
    input                   resetn,

    input       [127:0]     last_mask,

    input       [127:0]     s_axis_dout_tdata,
    input                   s_axis_dout_tvalid,
    output reg              s_axis_dout_tready,
    input                   s_axis_dout_tlast,

    output reg  [ 63:0]     bit_errors
);

    function automatic [6:0] popcount_8(input [7:0] bits);
        popcount_8 = bits[0] + bits[1] + bits[2] + bits[3] + bits[4] + bits[5] + bits[6] + bits[7];    
    endfunction

    function automatic [6:0] popcount_32(input [31:0] bits);
        popcount_32 = popcount_8(bits[7:0]) + popcount_8(bits[15:8]) + popcount_8(bits[23:16]) + popcount_8(bits[31:24]);
    endfunction

    reg [127:0] data_d;
    reg         last_d;
    reg [7:0] popcount_d [0:3];
    reg [7:0] popcount;
    reg [2:0] valid;
    reg [9:0] i;

    always @(posedge clk) begin
        if (!resetn) begin
            bit_errors <= 'h0;
            s_axis_dout_tready <= 'h0;
            data_d <= 'h0;
            last_d <= 'h0;

            for (i = 0; i < 4; i = i + 1)
                popcount_d[i] <= 'h0;

            popcount <= 'h0;

            valid <= 'h0;
        end else begin
            s_axis_dout_tready <= 'h1;

            if (s_axis_dout_tready && s_axis_dout_tvalid) begin
                data_d <= s_axis_dout_tdata;
                last_d <= s_axis_dout_tlast;

                if (s_axis_dout_tlast)
                    s_axis_dout_tready <= 'h0;
            end
            valid[0] <= s_axis_dout_tready && s_axis_dout_tvalid;

            if (valid[0]) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (last_d)
                        popcount_d[i] <= popcount_32(data_d[i*32 +: 32] & last_mask[i*32 +: 32]);
                    else
                        popcount_d[i] <= popcount_32(data_d[i*32 +: 32]);
                end
            end

            if (valid[1])
                popcount <= popcount_d[0] + popcount_d[1] + popcount_d[2] + popcount_d[3];

            if (valid[2])
                bit_errors <= bit_errors + {56'h0, popcount};

            valid[2:1] <= valid[1:0];
        end
    end

endmodule
