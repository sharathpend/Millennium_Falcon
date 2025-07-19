//=====================================================
// Designer: 
// email: 
//=====================================================

module fpu_mult_floor #(
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter ROUND_OUTPUT_LATENCY = 1, // only supports 1. Round() latency
  parameter MULT_OUTPUT_LATENCY = 2 // Multiplier latency
) (
  input  wire clk,

  // m_axis
  input  wire a_tvalid,
  output wire a_tready,
  input  wire [63:0] a_tdata,

  // m_axis
  input  wire b_tvalid,
  output wire b_tready,
  input  wire [63:0] b_tdata,

  // s_axis
  output wire result_tvalid,
  input  wire result_tready,
  output wire [63:0] result_tdata
);
  
  // If other combinations of operations need to be supported (int to float, etc), needs rewiring. Currently mult connected to round always.

  assign a_tready = 1'b1;
  assign b_tready = 1'b1;
  
  wire mult_result_tvalid;
  wire mult_result_tready;
  wire [63:0] mult_result_tdata;

  wire floor_result_tvalid;
  wire floor_result_tready;
  wire [63:0] floor_result_tdata;

  reg [1:0] op_sel_latched = 'd0;


  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) double_mult_v3_inst (
    .clk (clk),

    .a_tvalid (a_tvalid),
    .a_tready (),
    .a_tdata (a_tdata),

    .b_tvalid (b_tvalid),
    .b_tready (),
    .b_tdata (b_tdata),

    .result_tvalid (mult_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (mult_result_tdata)
  );

  double_to_int #(
    .OUTPUT_LATENCY (ROUND_OUTPUT_LATENCY)
  ) double_to_int_inst (
    .clk (clk),

    .a_tvalid (mult_result_tvalid),
    .a_tready (),
    .a_tdata (mult_result_tdata),

    .result_tvalid (floor_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (floor_result_tdata)
  );


  assign result_tdata = floor_result_tdata;
  assign result_tvalid = floor_result_tvalid;

endmodule