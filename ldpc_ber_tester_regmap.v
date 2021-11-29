`timescale 1ns/100ps

module ldpc_ber_tester_regmap #(
    parameter SEED_ID = 0,
    parameter ADDRESS_WIDTH = 10
) (
    // up interface
    input                               up_clk,
    input                               up_resetn,

    // up - Read interface
    input                               up_rreq,
    output reg                          up_rack,
    input       [ ADDRESS_WIDTH - 1:0]  up_raddr,
    output reg  [ 31:0]                 up_rdata,

    // up - Write interface
    input                               up_wreq,
    output reg                          up_wack,
    input       [ ADDRESS_WIDTH - 1:0]  up_waddr,
    input       [ 31:0]                 up_wdata,


    // Data interface
    input                               data_clk,

    output                              data_en,
    output                              data_sw_resetn,

    // Controls SNR
    output      [ 15:0]                 data_factor,
    output      [  7:0]                 data_offset,
    output      [ 31:0]                 data_ctrl_word,

    // Which bits should be counted for the last transaction
    output      [ 15:0]                 data_din_beats,
    output      [127:0]                 data_last_mask,

    // Simulation results
    input       [ 63:0]                 data_finished_blocks,
    input       [ 63:0]                 data_bit_errors,
    input       [ 31:0]                 data_in_flight
);

    localparam  [ 31:0]                 CORE_VERSION = 32'h00010061; // 1.00.a
    localparam  [ 31:0]                 CORE_MAGIC   = 32'h4350444c; // LDPC
    localparam                          AW = ADDRESS_WIDTH; // Address width alias

    // up registers
    reg         [ 31:0]                 up_scratch;
    reg                                 up_en;
    reg                                 up_sw_resetn;
    reg         [ 15:0]                 up_factor;
    reg         [  7:0]                 up_offset;
    reg         [ 15:0]                 up_din_beats;
    reg         [ 31:0]                 up_ctrl_word;
    reg         [127:0]                 up_last_mask;

    // up input signals (after CDC)
    wire        [ 63:0]                 up_finished_blocks;
    wire        [ 63:0]                 up_bit_errors;
    wire        [ 31:0]                 up_in_flight;

    wire                                data_sw_reset;

    // up write interface
    always @(posedge up_clk) begin
        up_wack <= up_wreq;

        if (!up_resetn) begin
            up_scratch      <= 'h0;
            up_en           <= 'h0;
            up_sw_resetn    <= 'h0;
            up_factor       <= 'h0;
            up_offset       <= 'h0;
            up_din_beats    <= 'h0;
            up_ctrl_word    <= 'h0;
            up_last_mask    <= 'h0;
        end else if (up_wreq) begin
            if (up_waddr == 'h02)
                up_scratch <= up_wdata;

            if (up_waddr == 'h10)
                {up_sw_resetn, up_en} <= up_wdata[1:0];

            if (up_waddr == 'h11)
                {up_offset, up_factor} <= up_wdata[23:0];

            if (up_waddr == 'h12)
                up_din_beats <= up_wdata[15:0];

            if (up_waddr == 'h13)
                up_ctrl_word <= up_wdata;

            if (up_waddr == 'h14)
                up_last_mask[31: 0] <= up_wdata;

            if (up_waddr == 'h15)
                up_last_mask[63:32] <= up_wdata;

            if (up_waddr == 'h16)
                up_last_mask[95:64] <= up_wdata;

            if (up_waddr == 'h17)
                up_last_mask[127:96] <= up_wdata;

        end else begin
            // Yes, this doesn't guarantee a 1-cycle pulse, but that's good
            // enogh for me :)
            up_sw_resetn <= 'h1;
        end
    end

    // up read interface
    always @(posedge up_clk) begin
        if (!up_resetn) begin
            up_rack <= 'h0;
            up_rdata <= 'b0;
        end else begin
            up_rack <= up_rreq;
            case (up_raddr)
                // Core information
                //
                // Version register
                'h00: up_rdata <= CORE_VERSION;

                // Core identifier. We choose the seed id here, as it should
                // be unique to each instance.
                'h01: up_rdata <= SEED_ID;

                // Scratch register for debugging purposes
                'h02: up_rdata <= up_scratch;

                // Magic identification value. Reads "LDPC".
                'h03: up_rdata <= CORE_MAGIC;

                // Core settings
                //
                // Control register:
                //  0: dataflow enable
                //  1: SW resetn
                'h10: up_rdata <= {up_sw_resetn, up_en};

                // AWGN config
                'h11: up_rdata <= {8'h0, up_offset, up_factor};

                // DIN Beat count. For a code with N code bits, this value
                // should be = ceil(N/16)
                'h12: up_rdata <= {16'h0, up_din_beats};

                // SD-FEC CTRL word
                'h13: up_rdata <= up_ctrl_word;

                // Last mask registers
                'h14: up_rdata <= up_last_mask[ 31: 0];
                'h15: up_rdata <= up_last_mask[ 63:32];
                'h16: up_rdata <= up_last_mask[ 95:64];
                'h17: up_rdata <= up_last_mask[127:96];

                // Result data
                //
                // Processed blocks
                'h20: up_rdata <= up_finished_blocks[31:0];
                'h21: up_rdata <= up_finished_blocks[63:32];

                // Bit error count
                'h22: up_rdata <= up_bit_errors[31:0];
                'h23: up_rdata <= up_bit_errors[63:32];

                // Last status word
                // 'h24: up_rdata <= up_last_status;

                // In-flight transactions
                'h24: up_rdata <= up_in_flight;

                default: up_rdata <= 'h0;

            endcase
        end
    end

    sync_event #(
        .NUM_OF_EVENTS  (1),
        .ASYNC_CLK      (1)
    ) i_sync_sw_reset_event (
        .in_clk     (up_clk),
        .in_event   (~up_sw_resetn),
        .out_clk    (data_clk),
        .out_event  (data_sw_reset)
    );

    assign data_sw_resetn = ~data_sw_reset;

    sync_data #(
        .NUM_OF_BITS    (1+16+8+16+32+128),
        .ASYNC_CLK      (1)
    ) i_sync_control (
        .in_clk     (up_clk),
        .in_data    ({up_en,
                      up_factor,
                      up_offset,
                      up_din_beats,
                      up_ctrl_word,
                      up_last_mask}),
        .out_clk    (data_clk),
        .out_data   ({data_en,
                      data_factor,
                      data_offset,
                      data_din_beats,
                      data_ctrl_word,
                      data_last_mask})
    );

    sync_data #(
        .NUM_OF_BITS    (64+64+32),
        .ASYNC_CLK      (1)
    ) i_sync_feedback (
        .in_clk     (data_clk),
        .in_data    ({data_finished_blocks,
                      data_bit_errors,
                      data_in_flight}),
        .out_clk    (up_clk),
        .out_data   ({up_finished_blocks,
                      up_bit_errors,
                      up_in_flight})
    );

endmodule
