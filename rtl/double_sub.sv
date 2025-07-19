//=====================================================
// Designer: 
// email: 
//=====================================================

module double_sub #(
  parameter OUTPUT_LATENCY = 1
) (
  input  wire clk,

  input  wire a_tvalid,
  input  wire [63:0] a_tdata,

  input  wire b_tvalid,
  input  wire [63:0] b_tdata,

  output wire result_tvalid,
  output wire [63:0] result_tdata
);

  generate
    if (OUTPUT_LATENCY == 1) begin : gen_double_sub_latency_01_nb
      double_sub_latency_01_nb double_sub_latency_01_nb_inst1 (
        .aclk (clk),

        .s_axis_a_tvalid (a_tvalid),
        .s_axis_a_tdata (a_tdata),

        .s_axis_b_tvalid (b_tvalid),
        .s_axis_b_tdata (b_tdata),

        .m_axis_result_tvalid (result_tvalid),
        .m_axis_result_tdata (result_tdata)
      );
    end else if (OUTPUT_LATENCY == 2) begin : gen_double_sub_latency_02_nb
      double_sub_latency_02_nb double_sub_latency_02_nb_inst1 (
        .aclk (clk),

        .s_axis_a_tvalid (a_tvalid),
        .s_axis_a_tdata (a_tdata),

        .s_axis_b_tvalid (b_tvalid),
        .s_axis_b_tdata (b_tdata),

        .m_axis_result_tvalid (result_tvalid),
        .m_axis_result_tdata (result_tdata)
      );
    end else begin : gen_double_sub_default
      double_sub_latency_01_nb double_sub_latency_01_nb_inst1 (
        .aclk (clk),

        .s_axis_a_tvalid (a_tvalid),
        .s_axis_a_tdata (a_tdata),

        .s_axis_b_tvalid (b_tvalid),
        .s_axis_b_tdata (b_tdata),

        .m_axis_result_tvalid (result_tvalid),
        .m_axis_result_tdata (result_tdata)
      );
    end
  endgenerate


endmodule