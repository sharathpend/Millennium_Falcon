//=====================================================
// Designer: 
// email: 
//
//
// Return 1 with probability 2^(-64).z ≈ ccs*(exp(-x))
// Latency = 7 + ApproxExp + 2
//=====================================================

// ccs_i and x_i floats
// ccs_i in [0, ln(2)]
// x >= 0
// rand_8_i uniform random 8 bits

module berexp_v6 #(
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter MULT_OUTPUT_LATENCY = 2, // LATENCY for multiplier(). Supports 1, 2.
  parameter FLOOR_OUTPUT_LATENCY = 1, // only supports 1. Floor/Round latency
  parameter INT_TO_DOUBLE_LATENCY = 1, // currently supports 1.
  parameter DOUBLE_SUB_LATENCY = 1, // currently supports 1.
  parameter EXP_OUTPUT_LATENCY = 8
) (
  input  wire clk,
  input  wire rst,

  input  wire din_val_i,
  output wire din_rdy_o,
  input  wire [63:0] ccs_i,
  input  wire [63:0] x_i,
  input  wire [7:0] rand_8_i,

  output wire dout_val_o,
  input  wire dout_rdy_i,
  output wire w_o
);

  localparam NUM_DELAY_REGS_DIN_VAL = EXP_OUTPUT_LATENCY + MULT_OUTPUT_LATENCY + FLOOR_OUTPUT_LATENCY;


  /*
  2^64     = 18,446,744,073,709,551,614 (dec) (D1) = 0x43F0_0000_0000_0000 (double)
  2^64 - 1 = 18,446,744,073,709,551,614 (dec) (D2)

  0x43EF_FFFF_FFFF_FFFF (double) = 18,446,744,073,709,549,568 (dec) (D3)
  D3 - D2 = 2046
  */
  localparam [63:0] POW_2_64_SUB_1 = 64'h43EF_FFFF_FFFF_FFFF;
  localparam [63:0] POW_2_63_SUB_1 = 64'h43DF_FFFF_FFFF_FFFF;

  reg  [63:0] ccs_i_d = 'd0;
  reg  [7:0] rand_8_i_d = 'd0;
  reg  [7:0] rand_8_i_l = 'd0;
  reg  [7:0] rand_8_i_l_rep [0:7];
  reg  [NUM_DELAY_REGS_DIN_VAL:1] din_val_i_d = 'd0;
  wire din_rdy_internal;

  wire [63:0] x_neg;
  wire [63:0] exp_x_neg;
  wire exp_x_neg_val;

  wire ccs_scaled_val;
  wire [63:0] ccs_scaled;
  reg [63:0] ccs_scaled_l = 0;

  wire [64:0] z_net;
  wire [64:0] z_net_mult_2;

  wire [7:0] u_equal;
  wire [7:0] u_less;
  reg w_reg = 1'b0;
  reg w_val_reg = 1'b0;

  genvar ii;

  
  assign x_neg = {1'b1, x_i[62:0]};

  always@ (posedge clk) begin
    ccs_i_d <= ccs_i;
    rand_8_i_d <= rand_8_i;

    din_val_i_d <= {din_val_i_d[(NUM_DELAY_REGS_DIN_VAL-1):1], din_val_i};

    if (din_val_i_d[1]) begin
      rand_8_i_l <= rand_8_i_d;
    end
  end

  generate
    for (ii = 0; ii < 8; ii = ii + 1) begin : gen_rand_8_i_l_rep
      initial begin
        rand_8_i_l_rep[ii] <= 'd0;
      end
      always@ (posedge clk) begin
        rand_8_i_l_rep[ii] <= rand_8_i_l;
      end
    end
  endgenerate

  // Not in critical data path
  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY+1)
  ) fpu_mult_ccs_pow_2_63_sub_1_inst (
    .clk (clk),

    //.a_tvalid (i2d_result_tvalid),
    .a_tvalid (din_val_i_d[1]),
    .a_tready (),
    .a_tdata (ccs_i_d),

    //.b_tvalid (i2d_result_tvalid),
    .b_tvalid (din_val_i_d[1]),
    .b_tready (),
    .b_tdata (POW_2_63_SUB_1),

    .result_tvalid (ccs_scaled_val),
    .result_tready (1'b1),
    .result_tdata (ccs_scaled)
  );

  // not in critical data path
  always@ (posedge clk) begin
    if (ccs_scaled_val == 1'b1) begin
      ccs_scaled_l <= ccs_scaled;
    end
  end

  // critical data path
  generate
    if (EXP_OUTPUT_LATENCY == 5) begin : gen_fpr_exp_lat_05
      fpr_exp_latency_05 fpr_exp_latency_05_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end else if (EXP_OUTPUT_LATENCY == 6) begin : gen_fpr_exp_lat_06
      fpr_exp_latency_06 fpr_exp_latency_06_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end else if (EXP_OUTPUT_LATENCY == 7) begin : gen_fpr_exp_lat_07
      fpr_exp_latency_07 fpr_exp_latency_07_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end else if (EXP_OUTPUT_LATENCY == 8) begin : gen_fpr_exp_lat_08
      fpr_exp_latency_08 fpr_exp_latency_08_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end else if (EXP_OUTPUT_LATENCY == 9) begin : gen_fpr_exp_lat_09
      fpr_exp_latency_09 fpr_exp_latency_09_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end else begin : gen_fpr_exp_default
      fpr_exp_latency_09 fpr_exp_latency_09_inst (
        .aclk                 (clk),              // input wire aclk
        .s_axis_a_tvalid      (din_val_i),          // input wire s_axis_a_tvalid
        .s_axis_a_tready      (din_rdy_internal), // output wire s_axis_a_tready
        .s_axis_a_tdata       (x_neg),            // input wire [63 : 0] s_axis_a_tdata
        .m_axis_result_tvalid (exp_x_neg_val),    // output wire m_axis_result_tvalid
        .m_axis_result_tdata  (exp_x_neg)         // output wire [63 : 0] m_axis_result_tdata
      );
    end
  endgenerate

  // critical data path
  fpu_mult_floor #(
    .MULT_OPT (MULT_OPT),
    .ROUND_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY),
    .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) fpu_mult_floor_exp_x_neg_ccs_scaled_inst (
    .clk (clk),

    // m_axis
    .a_tvalid (din_val_i_d[EXP_OUTPUT_LATENCY]),
    .a_tready (),
    .a_tdata (exp_x_neg),

    // m_axis
    .b_tvalid (din_val_i_d[EXP_OUTPUT_LATENCY]),
    .b_tready (),
    .b_tdata (ccs_scaled_l),

    // s_axis
    .result_tvalid (z_net_val),
    .result_tready (1'b1),
    .result_tdata (z_net)
  );

  // znet * 2 because we perform the inital scaling by ((2^63)-1) instead of ((2^64)-1) (due to lack of double to unsigned int)
  assign z_net_mult_2 = {z_net[62:0], 1'b0}; // upper bit is sign bit, which is dropped


  generate
    for (ii = 0; ii < 8; ii = ii + 1) begin: gen_u_equal_u_less
      assign u_equal[ii] = (rand_8_i_l_rep[ii] == z_net_mult_2[(63-(ii*8)) : (56-(ii*8))]) ? 1'b1 : 1'b0;
      assign u_less[ii]  = (rand_8_i_l_rep[ii] <  z_net_mult_2[(63-(ii*8)) : (56-(ii*8))]) ? 1'b1 : 1'b0;
    end
  endgenerate
  
  always@ (posedge clk) begin
    if (~u_equal[0])
      w_reg <= u_less[0];
    else if (~u_equal[1])
      w_reg <= u_less[1];
    else if (~u_equal[2])
      w_reg <= u_less[2];
    else if (~u_equal[3])
      w_reg <= u_less[3];
    else if (~u_equal[4])
      w_reg <= u_less[4];
    else if (~u_equal[5])
      w_reg <= u_less[5];
    else if (~u_equal[6])
      w_reg <= u_less[6];
    else
      w_reg <= u_less[7];
  end

  always@ (posedge clk) begin
    w_val_reg <= din_val_i_d[NUM_DELAY_REGS_DIN_VAL];
  end

  assign w_o = w_reg;
  assign dout_val_o = w_val_reg;

endmodule