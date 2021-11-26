module ldpc_ber_tester_ctrl (
    input               clk,
    input               resetn,

    input               en,
    input               sw_resetn,

    output reg          ctrl_valid,
    input               ctrl_ready,

    input               status_valid,
    output reg          status_ready,
    input      [31:0]   status_data,

    output reg [63:0]   finished_blocks
    );

    always @(posedge clk) begin
        if (!resetn) begin
            ctrl_valid <= 'h0;
            status_ready <= 'h0;
            finished_blocks <= 'h0;
        end else begin
            status_ready <= 1'h1;
            ctrl_valid <= en || ctrl_valid && !ctrl_ready;

            if (status_ready & status_valid)
                finished_blocks <= finished_blocks + 1;
        end
    end

endmodule
