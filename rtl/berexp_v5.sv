//=====================================================
// Designer: 
// email: 
//=====================================================

// Estrin's Scheme

module berexp_v5 #(
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter MULT_OUTPUT_LATENCY = 2, // LATENCY for multiplier(). Supports 1, 2.
  parameter FLOOR_OUTPUT_LATENCY = 1, // only supports 1. Floor/Round latency
  parameter INT_TO_DOUBLE_LATENCY = 1, // currently supports 1.
  parameter DOUBLE_SUB_LATENCY = 1 // currently supports 1.
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

  /*
  itd = int_to_double

  -1: ccs, x input. x to mult_floor.
  0 : x_d=x
  1 : x_d_l=x
  2 : s=floor(x*(1/ln2)) output from floor() ready, sent to itd
  3 : s_d=s, itd(s) output ready, sent to mult
  4 : s_min = min(s_d, 63)
  5 : itd(s)*ln2 output from mult ready, sent to subtractor. s=min(s,63) output ready.
  6 : r=x_d_l-(s*ln2) output ready from subtractor, sent to ApproxExp(r,ccs)
  .
  .
  .
  N  : ApproxExp output ready.
  N+1: (2*ApproxExp - 1) >> s ready (Operation-6)
  N+2: Final output ready (Operation-7)




  */

  localparam OPERATION_1 = MULT_OUTPUT_LATENCY + FLOOR_OUTPUT_LATENCY;
  localparam OPERATION_2 = INT_TO_DOUBLE_LATENCY;
  localparam OPERATION_3 = MULT_OUTPUT_LATENCY;
  localparam OPERATION_4 = DOUBLE_SUB_LATENCY;

  //localparam NUM_DELAY_REGS_CCS = OPERATION_1 + OPERATION_2 + OPERATION_3 + OPERATION_4; // 6
  localparam NUM_DELAY_REGS_DIN_VAL = OPERATION_1 + OPERATION_2 + OPERATION_3 + OPERATION_4;

  localparam [63:0] POW_2_63 = 64'h43E0000000000000; // 2^63 in double float
  localparam [63:0] INV_LN_2 = 64'h3FF71547652B82FE; // 1/ln(2) in double float
  localparam [63:0] LN_2 = 64'h3FE62E42FEFA3BDC; // ln(2) in double float

  reg  [63:0] ccs_i_d = 'd0;
  reg  [63:0] ccs_i_l = 'd0;
  reg  [63:0] x_d = 'd0;
  reg  [63:0] x_d_l = 'd0;
  reg  [7:0] rand_8_i_d = 'd0;
  reg  [7:0] rand_8_i_l = 'd0;
  reg  [7:0] rand_8_i_l_rep [0:7];
  reg  [NUM_DELAY_REGS_DIN_VAL:1] din_val_i_d = 'd0;

  reg [63:0] s_d = 'd0;
  reg [63:0] s_min = 'd0;

  wire fpu_mf1_result_tvalid;
  wire [63:0] fpu_mf1_result_tdata;

  wire i2d_result_tvalid;
  wire [63:0] i2d_result_tdata;

  wire mult_result_tvalid;
  wire [63:0] mult_result_tdata;

  wire sub_result_tvalid;
  wire [63:0] sub_result_tdata;

  wire approxexp_tvalid;
  wire [63:0] approxexp_tdata;

  reg  approxexp_tvalid_d0 = 'b0;
  reg  approxexp_tvalid_d1 = 'b0;

  (* max_fanout = 10 *) reg [64:0] z_reg [0:7];
  (* max_fanout = 10 *) wire [64:0] z_net [0:7];

  reg w_reg = 'b0;

  genvar ii;

  /*
  generate
    for (ii = 0; ii < NUM_DELAY_REGS_CCS; ii = ii + 1) begin : gen_ccs_i_d
      initial begin
        ccs_i_d[ii] <= 'd0;
      end
      always@ (posedge clk) begin
        if (ii == 0) begin
          ccs_i_d[ii] <= ccs_i;
        end else begin
          ccs_i_d[ii] <= ccs_i_d[ii-1];
        end
      end
    end
  endgenerate
  */

  // Input reg/latch for later use
  // Valid shift reg to keep track of data flow
  // These happen in parallel to Operation-1, Operation-2, ... so on.
  // For timing, look at Operation-1 onwards.
  always@ (posedge clk) begin
    ccs_i_d <= ccs_i;
    x_d <= x_i;
    rand_8_i_d <= rand_8_i;

    din_val_i_d <= {din_val_i_d[(NUM_DELAY_REGS_DIN_VAL-1):1], din_val_i};

    if (din_val_i_d[1]) begin
      ccs_i_l <= ccs_i_d;
      x_d_l <= x_d;
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



  // OPERATION_1
  fpu_mult_floor #(
    .MULT_OPT (MULT_OPT),
    .ROUND_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY),
    .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) fpu_mult_floor_inst1 (
    .clk (clk),

    // m_axis
    .a_tvalid (din_val_i),
    .a_tready (),
    .a_tdata (x_i),

    // m_axis
    .b_tvalid (din_val_i),
    .b_tready (),
    .b_tdata (INV_LN_2),

    // s_axis
    .result_tvalid (fpu_mf1_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (fpu_mf1_result_tdata)
  );

  always@ (posedge clk) begin
    //if (fpu_mf1_result_tvalid) begin
    if (din_val_i_d[OPERATION_1]) begin
      s_d <= fpu_mf1_result_tdata;
    end

    if (s_d < 63) begin
      s_min <= s_d;
    end else begin
      s_min <= 'd63;
    end
  end

  // OPERATION_2
  int_to_double #(
    .OUTPUT_LATENCY (INT_TO_DOUBLE_LATENCY)
  ) int_to_double_inst1 (
    .clk (clk),

    //.a_tvalid (fpu_mf1_result_tvalid),
    .a_tvalid (din_val_i_d[OPERATION_1]),
    .a_tready (),
    .a_tdata (fpu_mf1_result_tdata),

    .result_tvalid (i2d_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (i2d_result_tdata)
  );

  // OPERATION_3
  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) double_mult_v3_inst1 (
    .clk (clk),

    //.a_tvalid (i2d_result_tvalid),
    .a_tvalid (din_val_i_d[(OPERATION_1+OPERATION_2)]),
    .a_tready (),
    .a_tdata (i2d_result_tdata),

    //.b_tvalid (i2d_result_tvalid),
    .b_tvalid (din_val_i_d[(OPERATION_1+OPERATION_2)]),
    .b_tready (),
    .b_tdata (LN_2),

    .result_tvalid (mult_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (mult_result_tdata)
  );

  // OPERATION_4
  double_sub #(
    .OUTPUT_LATENCY (DOUBLE_SUB_LATENCY)
  ) double_sub_inst1 (
    .clk (clk),

    //.a_tvalid (mult_result_tvalid),
    .a_tvalid (din_val_i_d[(OPERATION_1+OPERATION_2+OPERATION_3)]),
    //.a_tdata (x_d),
    .a_tdata (x_d_l),

    //.b_tvalid (mult_result_tvalid),
    .b_tvalid (din_val_i_d[(OPERATION_1+OPERATION_2+OPERATION_3)]),
    .b_tdata (mult_result_tdata),

    .result_tvalid (sub_result_tvalid), // equivalent to din_val_i_d[(OPERATION_1+OPERATION_2+OPERATION_3+OPERATION_4)]
    .result_tdata (sub_result_tdata)
  );

  // OPERATION_5
  approxexp_v5 #(
    .MULT_OPT (MULT_OPT),
    .FLOOR_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY),
    .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) approxexp_v5_inst1 (
    .clk (clk),
    .rst (rst),

    .din_val (din_val_i_d[(OPERATION_1+OPERATION_2+OPERATION_3+OPERATION_4)]),
    .din_rdy (),
    .ccs_i (ccs_i_l),
    .x_i (sub_result_tdata),

    .dout_val (approxexp_tvalid),
    .dout_rdy (1'b1),
    .exp_o (approxexp_tdata)
  );

  // OPERATION_6
  generate
    for (ii = 0; ii < 8; ii = ii + 1) begin: gen_z_reg
      initial begin
        z_reg[ii] <= 'b0;
      end
      always@ (posedge clk) begin
        if (approxexp_tvalid) begin
          z_reg[ii] <= ({approxexp_tdata, 1'b0} - 1) >> s_min;
        end
      end

      assign z_net[ii] = z_reg[ii][63:0];
    end
  endgenerate

  always@ (posedge clk) begin
    approxexp_tvalid_d0 <= approxexp_tvalid;
  end


  // OPERATION_7
  wire [7:0] u_equal;
  wire [7:0] u_less;
  generate
    for (ii = 0; ii < 8; ii = ii + 1) begin: gen_u_equal_u_less
      assign u_equal[ii] = (rand_8_i_l_rep[ii] == z_net[ii][(63-(ii*8)) : (56-(ii*8))]) ? 1'b1 : 1'b0;
      assign u_less[ii]  = (rand_8_i_l_rep[ii] <  z_net[ii][(63-(ii*8)) : (56-(ii*8))]) ? 1'b1 : 1'b0;
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
    approxexp_tvalid_d1 <= approxexp_tvalid_d0;
  end

  assign w_o = w_reg;
  assign dout_val_o = approxexp_tvalid_d1;

endmodule