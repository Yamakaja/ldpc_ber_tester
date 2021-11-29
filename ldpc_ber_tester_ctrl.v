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

    // Explicitly NOT called "dout_last" to prevent confusion with tlast.
    // This signal is only high if the current beat is actually the
    // last one in the stream, i.e. ready and valid are also high.
    input               dout_finish,

    output reg [63:0]   finished_blocks,
    output reg [31:0]   in_flight
    );

    always @(posedge clk) begin
        if (!resetn) begin
            ctrl_valid <= 'h0;
            status_ready <= 'h0;
            finished_blocks <= 'h0;
            in_flight <= 'h0;
        end else begin
            status_ready <= 1'h1;
            ctrl_valid <= en || (ctrl_valid && !ctrl_ready);

            if (status_ready & status_valid)
                finished_blocks <= finished_blocks + 1;


            // Transactions start with a CTRL word to provide information
            // about the contents of the DIN stream. Once the data has been
            // processed we receive a CTRL beat and data on DOUT. We consider
            // the last beat of DOUT the be the end of a transaction.
            if ((ctrl_valid && ctrl_ready) ^ dout_finish) begin
                in_flight <= in_flight + (dout_finish ? -1 : 1);
            end
        end
    end

endmodule
