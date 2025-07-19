//=====================================================
// Designer: 
// email: 
//=====================================================
module double_mult_v3 #(
  parameter OPT = 0, // 0 = SPEED, 1 = LATENCY
  parameter OUTPUT_LATENCY = 1 // 1, 2
) (
  input  wire clk,

  input  wire a_tvalid,
  input  wire [63:0] a_tdata,
  output wire a_tready,

  input  wire b_tvalid,
  input  wire [63:0] b_tdata,
  output wire b_tready,

  output wire result_tvalid,
  output wire [63:0] result_tdata,
  input  wire result_tready
);
  
  generate
    if ((OUTPUT_LATENCY == 1) && (OPT == 0)) begin : gen_double_mult_optspeed_lat_01

        double_mult_optspeed_latency_01 double_mult_latency_01_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else if ((OUTPUT_LATENCY == 1) && (OPT == 1)) begin : gen_double_mult_optlatency_lat_01

        double_mult_optlatency_latency_01 double_mult_latency_01_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          .m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else if (OUTPUT_LATENCY == 2) begin : gen_double_mult_optspeed_lat_02

        double_mult_optspeed_latency_02 double_mult_latency_02_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else if (OUTPUT_LATENCY == 3) begin : gen_double_mult_optspeed_lat_03

        double_mult_optspeed_latency_03 double_mult_latency_03_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else if (OUTPUT_LATENCY == 4) begin : gen_double_mult_optspeed_lat_04

        double_mult_optspeed_latency_04 double_mult_latency_04_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else if (OUTPUT_LATENCY == 5) begin : gen_double_mult_optspeed_lat_05

        double_mult_optspeed_latency_05 double_mult_latency_05_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end else begin : gen_double_mult_optspeed_default

        double_mult_optspeed_latency_02 double_mult_latency_02_inst (
          .aclk(clk),                                  // input wire aclk

          .s_axis_a_tvalid(a_tvalid),            // input wire s_axis_a_tvalid
          .s_axis_a_tready(a_tready),            // output wire s_axis_a_tready
          .s_axis_a_tdata(a_tdata),              // input wire [63 : 0] s_axis_a_tdata

          .s_axis_b_tvalid(b_tvalid),            // input wire s_axis_b_tvalid
          .s_axis_b_tready(b_tready),            // output wire s_axis_b_tready
          .s_axis_b_tdata(b_tdata),              // input wire [63 : 0] s_axis_b_tdata

          .m_axis_result_tvalid(result_tvalid),  // output wire m_axis_result_tvalid
          //.m_axis_result_tready(result_tready),  // input wire m_axis_result_tready
          .m_axis_result_tdata(result_tdata)    // output wire [63 : 0] m_axis_result_tdata
        );

    end
  endgenerate

endmodule