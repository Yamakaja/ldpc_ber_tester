module ldpc_ber_tester #(
    parameter SEED_ID = 0
) (
    // AXI4 Lite slave interface
    input                   s_axi_aclk,
    input                   s_axi_aresetn,
    input                   s_axi_awvalid,
    input       [ 11:0]     s_axi_awaddr,
    input       [  2:0]     s_axi_awprot,
    output                  s_axi_awready,
    input                   s_axi_wvalid,
    input       [ 31:0]     s_axi_wdata,
    input       [  3:0]     s_axi_wstrb,
    output                  s_axi_wready,
    output                  s_axi_bvalid,
    output      [  1:0]     s_axi_bresp,
    input                   s_axi_bready,
    input                   s_axi_arvalid,
    input       [ 11:0]     s_axi_araddr,
    input       [  2:0]     s_axi_arprot,
    output                  s_axi_arready,
    output                  s_axi_rvalid,
    input                   s_axi_rready,
    output      [  1:0]     s_axi_rresp,
    output      [ 31:0]     s_axi_rdata,

    output                  interrupt,

    // Datapath clock and reset
    input                   data_clk,
    input                   data_resetn,

    // AXI4 Stream DIN master
    output      [127:0]     m_axis_din_tdata,
    output                  m_axis_din_tvalid,
    input                   m_axis_din_tready,
    output                  m_axis_din_tlast,

    // AXI4 Stream CTRL master
    output      [ 31:0]     m_axis_ctrl_tdata,
    output                  m_axis_ctrl_tvalid,
    input                   m_axis_ctrl_tready,

    // AXI4 Stream DOUT slave
    input       [127:0]     s_axis_dout_tdata,
    input                   s_axis_dout_tvalid,
    output                  s_axis_dout_tready,
    input                   s_axis_dout_tlast,

    // AXI4 Stream STATUS slave
    input       [ 31:0]     s_axis_status_tdata,
    input                   s_axis_status_tvalid,
    output                  s_axis_status_tready
);

    // Address width
    localparam AW = 12;

    wire                    up_rreq;
    wire                    up_rack;
    wire    [AW-3:0]        up_raddr;
    wire    [  31:0]        up_rdata;

    wire                    up_wreq;
    wire                    up_wack;
    wire    [AW-3:0]        up_waddr;
    wire    [  31:0]        up_wdata;

    wire                    data_en;
    wire                    data_sw_resetn;
    wire    [  15:0]        data_factor;
    wire    [   7:0]        data_offset;
    wire    [  15:0]        data_din_beats;
    wire    [  31:0]        data_ctrl_word;
    wire    [ 127:0]        data_last_mask;

    wire    [  63:0]        data_finished_blocks;
    wire    [  63:0]        data_bit_errors;
    wire    [  31:0]        data_in_flight;
    wire    [  31:0]        data_last_status;
    wire    [  63:0]        data_iter_count;
    wire    [  63:0]        data_failed_blocks;
    wire    [  63:0]        data_last_failed;

    wire                    data_axis_din_buf_tvalid;
    wire                    data_axis_din_buf_tready;
    wire    [ 127:0]        data_axis_din_buf_tdata;
    wire                    data_axis_din_buf_tlast;

    ldpc_ber_tester_ber_counter i_ber_counter (
        .clk                    (data_clk),
        .resetn                 (data_resetn & data_sw_resetn),
        .last_mask              (data_last_mask),
        .s_axis_dout_tdata      (s_axis_dout_tdata),
        .s_axis_dout_tvalid     (s_axis_dout_tvalid),
        .s_axis_dout_tready     (s_axis_dout_tready),
        .s_axis_dout_tlast      (s_axis_dout_tlast),
        .bit_errors             (data_bit_errors)
    );

    ldpc_ber_tester_axis_gen #( .SEED_ID (SEED_ID) ) i_ctrl (
        .clk                    (data_clk),
        .resetn                 (data_resetn),
        .en                     (data_en),
        .sw_resetn              (data_sw_resetn),

        .factor                 (data_factor),
        .offset                 (data_offset),
        .din_beats              (data_din_beats),

        .ctrl_tvalid            (m_axis_ctrl_tvalid),
        .ctrl_tready            (m_axis_ctrl_tready),

        .din_tvalid             (data_axis_din_buf_tvalid),
        .din_tready             (data_axis_din_buf_tready),
        .din_tlast              (data_axis_din_buf_tlast),
        .din_tdata              (data_axis_din_buf_tdata),

        .status_tvalid          (s_axis_status_tvalid),
        .status_tready          (s_axis_status_tready),
        .status_tdata           (s_axis_status_tdata),

        .dout_finish            (s_axis_dout_tlast && s_axis_dout_tvalid && s_axis_dout_tready),

        .finished_blocks        (data_finished_blocks),
        .in_flight              (data_in_flight),
        .last_status            (data_last_status),
        .iter_count             (data_iter_count),
        .failed_blocks          (data_failed_blocks),
        .last_failed            (data_last_failed)

    );

    util_axis_buf #( .DATA_WIDTH(128) ) i_din_buf (
        .clk                    (data_clk),
        .resetn                 (data_resetn),

        .s_axis_valid           (data_axis_din_buf_tvalid),
        .s_axis_ready           (data_axis_din_buf_tready),
        .s_axis_data            (data_axis_din_buf_tdata),
        .s_axis_last            (data_axis_din_buf_tlast),

        .m_axis_valid           (m_axis_din_tvalid),
        .m_axis_ready           (m_axis_din_tready),
        .m_axis_data            (m_axis_din_tdata),
        .m_axis_last            (m_axis_din_tlast)
    );

    assign m_axis_ctrl_tdata = data_ctrl_word;

    ldpc_ber_tester_regmap #(
        .SEED_ID (SEED_ID),
        .ADDRESS_WIDTH (AW-2)
    ) i_regmap (
        .up_clk                 (s_axi_aclk),
        .up_resetn              (s_axi_aresetn),

        .up_rreq                (up_rreq),
        .up_rack                (up_rack),
        .up_raddr               (up_raddr),
        .up_rdata               (up_rdata),

        .up_wreq                (up_wreq),
        .up_wack                (up_wack),
        .up_waddr               (up_waddr),
        .up_wdata               (up_wdata),

        .up_interrupt           (interrupt),

        .data_clk               (data_clk),
        
        .data_en                (data_en),
        .data_sw_resetn         (data_sw_resetn),
        .data_factor            (data_factor),
        .data_offset            (data_offset),
        .data_din_beats         (data_din_beats),
        .data_ctrl_word         (data_ctrl_word),
        .data_last_mask         (data_last_mask),

        .data_finished_blocks   (data_finished_blocks),
        .data_bit_errors        (data_bit_errors),
        .data_in_flight         (data_in_flight),
        .data_last_status       (data_last_status),
        .data_iter_count        (data_iter_count),
        .data_failed_blocks     (data_failed_blocks),
        .data_last_failed       (data_last_failed)
    );

    up_axi #(
        .AXI_ADDRESS_WIDTH(AW)
    ) i_up_axi (
        .up_rstn                (s_axi_aresetn),
        .up_clk                 (s_axi_aclk),

        .up_axi_awvalid         (s_axi_awvalid),
        .up_axi_awaddr          (s_axi_awaddr),
        .up_axi_awready         (s_axi_awready),
        .up_axi_wvalid          (s_axi_wvalid),
        .up_axi_wdata           (s_axi_wdata),
        .up_axi_wstrb           (s_axi_wstrb),
        .up_axi_wready          (s_axi_wready),
        .up_axi_bvalid          (s_axi_bvalid),
        .up_axi_bresp           (s_axi_bresp),
        .up_axi_bready          (s_axi_bready),
        .up_axi_arvalid         (s_axi_arvalid),
        .up_axi_araddr          (s_axi_araddr),
        .up_axi_arready         (s_axi_arready),
        .up_axi_rvalid          (s_axi_rvalid),
        .up_axi_rresp           (s_axi_rresp),
        .up_axi_rdata           (s_axi_rdata),
        .up_axi_rready          (s_axi_rready),

        .up_wreq                (up_wreq),
        .up_waddr               (up_waddr),
        .up_wdata               (up_wdata),
        .up_wack                (up_wack),
        .up_rreq                (up_rreq),
        .up_raddr               (up_raddr),
        .up_rdata               (up_rdata),
        .up_rack                (up_rack)
    );
endmodule
