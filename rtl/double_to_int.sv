//=====================================================
// Designer: 
// email: 
//=====================================================

module double_to_int #(
  parameter OUTPUT_LATENCY = 1
) (
  input  wire clk,

  input  wire a_tvalid,
  input  wire [63:0] a_tdata,
  output wire a_tready,

  output wire result_tvalid,
  output wire [63:0] result_tdata,
  input  wire result_tready
);

  generate
    if (OUTPUT_LATENCY == 1) begin : gen_double_to_int_lat_01
      double_to_int_lat_01 double_to_int_lat_01_inst (
        .aclk (clk),                           // input wire aclk

        .s_axis_a_tvalid (a_tvalid),           // input wire s_axis_a_tvalid
        .s_axis_a_tready (a_tready),           // output wire s_axis_a_tready
        .s_axis_a_tdata (a_tdata),             // input wire [63 : 0] s_axis_a_tdata
        
        .m_axis_result_tvalid (result_tvalid), // output wire m_axis_result_tvalid
        //.m_axis_result_tready (result_tready), // input wire m_axis_result_tready
        .m_axis_result_tdata (result_tdata)    // output wire [63 : 0] m_axis_result_tdata
      );
    end else begin : gen_double_to_int_default
      double_to_int_lat_01 double_to_int_lat_01_inst (
        .aclk (clk),                           // input wire aclk

        .s_axis_a_tvalid (a_tvalid),           // input wire s_axis_a_tvalid
        .s_axis_a_tready (a_tready),           // output wire s_axis_a_tready
        .s_axis_a_tdata (a_tdata),             // input wire [63 : 0] s_axis_a_tdata
        
        .m_axis_result_tvalid (result_tvalid), // output wire m_axis_result_tvalid
        //.m_axis_result_tready (result_tready), // input wire m_axis_result_tready
        .m_axis_result_tdata (result_tdata)    // output wire [63 : 0] m_axis_result_tdata
      );
    end
  endgenerate


endmodule