//=====================================================
// Designer: 
// email: 
//=====================================================

// Estrin's Scheme

`define VERSION_5p30 // an extra register right after the fp_mult_floor output (after the mux).

module approxexp_v5 #(
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter FLOOR_OUTPUT_LATENCY = 1, // only supports 1. Round/Floor latency
  parameter MULT_OUTPUT_LATENCY = 2 // Latency of the double_mult in fpu_mult_floor in the critical path. Supports 1, 2, 3
) (
  input  wire clk,
  input  wire rst,

  input  wire din_val,
  output wire din_rdy,
  input  wire [63:0] ccs_i,
  input  wire [63:0] x_i,

  output wire dout_val,
  input  wire dout_rdy,
  output wire [63:0] exp_o
);

  
  localparam [63:0] POW_2_63 = 64'h43E0000000000000; // 2^63 in double float

  (* max_fanout = 2 *) reg [63:0] C_reg [12:0] = {  64'h00000004741183A3, // C[12]
                                                    64'h00000036548CFC06,
                                                    64'h0000024FDCBF140A,
                                                    64'h0000171D939DE045,
                                                    64'h0000D00CF58F6F84,
                                                    64'h000680681CF796E3,
                                                    64'h002D82D8305B0FEA,
                                                    64'h011111110E066FD0,
                                                    64'h0555555555070F00,
                                                    64'h155555555581FF00,
                                                    64'h400000000002B400,
                                                    64'h7FFFFFFFFFFF4800,
                                                    64'h8000000000000000}; // C[0]

  localparam OP1_DELAY = MULT_OUTPUT_LATENCY; // output of first multiplier
  localparam OP2_DELAY = OP1_DELAY + FLOOR_OUTPUT_LATENCY; // output of floor, which is right after the multiplier.
  localparam OP3_DELAY = OP2_DELAY + MULT_OUTPUT_LATENCY; // output of first multiplier being used for ccs
  localparam OP4_DELAY = OP3_DELAY + FLOOR_OUTPUT_LATENCY; // output of floor being used for ccs.

  `ifdef VERSION_5p30
    localparam STAGE1_DELAY = OP2_DELAY + 1;        // data input to stage-1 of MAC
  `else
    localparam STAGE1_DELAY = OP2_DELAY;
  `endif
  localparam STAGE2_DELAY = STAGE1_DELAY + 1; // data input to stage-2 of MAC
  localparam STAGE3_DELAY = STAGE2_DELAY + 1; // data input to stage-3 of MAC
  localparam STAGE4_DELAY = STAGE3_DELAY + 1; // data input to stage-4 of MAC
  localparam STAGE5_DELAY = STAGE4_DELAY + 1; // data input to stage-5 of MAC
  localparam STAGE6_DELAY = STAGE5_DELAY + 1; // data output from stage-5 MAC, final output.


  wire din_rdy_internal;

  reg [63:0] ccs_l = 0;
  reg [63:0] x_l = 0;
  reg [STAGE6_DELAY+1:1] din_val_d = 0; // an extra bit, the impl will remove it.

  reg is_ccs_eq_1 = 0;
  reg is_x_eq_0 = 0;

  wire [63:0] x_neg;
  wire [63:0] x_pos;
  wire [63:0] mux_x_ccs;

  wire [63:0] mux_x_ccs_mult_2_pow_63_floor;
  reg  [63:0] ccs_mult_2_pow_63_floor_l = 0;
  wire mux_x_ccs_mult_2_pow_63_floor_val;
  
  wire [63:0] fpu_mf1_tdata;
  wire fpu_mf1_tvalid;

  wire [63:0] x_powers_net; // select one of x, x2, x4, x8
  wire [127:0] x_powers; // square x_powers_net
  reg  [63:0] x_powers_reg = 0; // >>63
  
  wire [63:0]  mult_0_a;
  wire [63:0]  mult_0_b;
  wire [128:0] mult_0_p;
  wire [63:0]  mult_0_p_trimmed;
  wire [63:0]  mac_0_a;
  wire [63:0]  mac_0_b;
  reg  [63:0]  mac_0 = 0; // no bit growth expected

  wire [63:0]  mult_1_a;
  wire [63:0]  mult_1_b;
  wire [128:0] mult_1_p;
  wire [63:0]  mult_1_p_trimmed;
  wire [63:0]  mac_1_a;
  wire [63:0]  mac_1_b;
  reg  [63:0]  mac_1 = 0; // no bit growth expected

  wire [63:0]  mult_2_a;
  wire [63:0]  mult_2_b;
  wire [128:0] mult_2_p;
  wire [63:0]  mult_2_p_trimmed;
  wire [63:0]  mac_2_a;
  wire [63:0]  mac_2_b;
  reg  [63:0]  mac_2 = 0; // no bit growth expected

  wire [63:0]  mult_3_a;
  wire [63:0]  mult_3_b;
  wire [128:0] mult_3_p;
  wire [63:0]  mult_3_p_trimmed;
  wire [63:0]  mac_3_a;
  wire [63:0]  mac_3_b;
  reg  [63:0]  mac_3 = 0; // no bit growth expected

  wire [63:0]  mult_4_a;
  wire [63:0]  mult_4_b;
  wire [128:0] mult_4_p;
  wire [63:0]  mult_4_p_trimmed;
  wire [63:0]  mac_4_a;
  wire [63:0]  mac_4_b;
  reg  [63:0]  mac_4 = 0; // no bit growth expected

  wire [63:0]  mult_5_a;
  wire [63:0]  mult_5_b;
  wire [128:0] mult_5_p;
  wire [63:0]  mult_5_p_trimmed;
  wire [63:0]  mac_5_a;
  wire [63:0]  mac_5_b;
  reg  [63:0]  mac_5 = 0; // no bit growth expected

  reg  [63:0]  mac_6 = 0; // no bit growth expected. Not a MAC.

  wire [127:0] final_mult;
  reg  [63:0] final_mult_reg = 0; // no bit growth expected.

  `ifdef VERSION_5p30
    reg  [63:0] x_powers_d = 0;
    wire [63:0] x_powers_current;
  `else
    wire [63:0] x_powers_current;
  `endif




  assign din_rdy = 1'b1;

  always@ (posedge clk) begin
    if (rst)
      din_val_d <= 0;
    else
      din_val_d <= {din_val_d[STAGE6_DELAY:1], din_val};
  end

  always@ (posedge clk) begin
    if (din_val) begin
      ccs_l <= {1'b0, ccs_i[62:0]};
      x_l   <= {1'b0, x_i[62:0]}; // converting sign bit to 0 (positive)
    end

    if (ccs_l == 64'h3FF0000000000000)
      is_ccs_eq_1 <= 1'b1;
    else
      is_ccs_eq_1 <= 1'b0;
    
    if (x_l[63:0] == 64'h0)
      is_x_eq_0 <= 1'b1;
    else
      is_x_eq_0 <= 1'b0;
  end

  assign x_neg = {1'b1, x_i[62:0]};
  assign x_pos = {1'b0, x_i[62:0]};


  assign mux_x_ccs = din_val_d[OP2_DELAY] ? ccs_l : x_pos;
  
  fpu_mult_floor #(
    .MULT_OPT (MULT_OPT),
    .ROUND_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY),
    .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) fpu_mult_floor_inst1 (
    .clk (clk),

    // m_axis
    .a_tvalid ((din_val | din_val_d[OP2_DELAY])),
    .a_tready (),
    .a_tdata (mux_x_ccs),

    // m_axis
    .b_tvalid ((din_val | din_val_d[OP2_DELAY])),
    .b_tready (),
    .b_tdata (POW_2_63),

    // s_axis
    .result_tvalid (mux_x_ccs_mult_2_pow_63_floor_val),
    .result_tready (1'b1),
    .result_tdata (mux_x_ccs_mult_2_pow_63_floor)
  );

  always@ (posedge clk) begin
    if (din_val_d[OP4_DELAY]) begin
      ccs_mult_2_pow_63_floor_l <= mux_x_ccs_mult_2_pow_63_floor;
    end
  end


  // MUX after the Mult+Floor
  assign x_powers_net = din_val_d[OP2_DELAY] ? mux_x_ccs_mult_2_pow_63_floor : x_powers_reg;

  assign x_powers = (x_powers_net * x_powers_net);

  always@ (posedge clk) begin
    x_powers_reg <= x_powers[63+:64]; // no bit growth expected
  end

  `ifdef VERSION_5p30
    always@ (posedge clk) begin
      x_powers_d <= x_powers_net;
    end
    assign x_powers_current = x_powers_d;
  `else
    assign x_powers_current = x_powers_net;
  `endif

  // MAC-0
  assign mult_0_a = x_powers_current;
  assign mult_0_b = din_val_d[STAGE1_DELAY] ? C_reg[1] : mac_1;
  
  assign mult_0_p = (mult_0_a * mult_0_b);
  assign mult_0_p_trimmed = mult_0_p[63+:64];

  assign mac_0_a = din_val_d[STAGE1_DELAY] ? C_reg[0] : mac_0;
  assign mac_0_b = mult_0_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_0 <= mac_0_a - mac_0_b;
    else
      mac_0 <= mac_0_a + mac_0_b;
  end


  // MAC-1
  assign mult_1_a = x_powers_current;
  assign mult_1_b = din_val_d[STAGE1_DELAY] ? C_reg[3] : mac_3;
  
  assign mult_1_p = (mult_1_a * mult_1_b);
  assign mult_1_p_trimmed = mult_1_p[63+:64];

  assign mac_1_a = din_val_d[STAGE1_DELAY] ? C_reg[2] : mac_2;
  assign mac_1_b = mult_1_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_1 <= mac_1_a - mac_1_b;
    else
      mac_1 <= mac_1_a + mac_1_b;
  end


  // MAC-2
  assign mult_2_a = x_powers_current;
  assign mult_2_b = din_val_d[STAGE1_DELAY] ? C_reg[5] : mac_5;
  
  assign mult_2_p = (mult_2_a * mult_2_b);
  assign mult_2_p_trimmed = mult_2_p[63+:64];

  assign mac_2_a = din_val_d[STAGE1_DELAY] ? C_reg[4] : mac_4;
  assign mac_2_b = mult_2_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_2 <= mac_2_a - mac_2_b;
    else
      mac_2 <= mac_2_a + mac_2_b;
  end


  // MAC-3
  assign mult_3_a = x_powers_current;
  assign mult_3_b = din_val_d[STAGE1_DELAY] ? C_reg[7] : 0;
  
  assign mult_3_p = (mult_3_a * mult_3_b);
  assign mult_3_p_trimmed = mult_3_p[63+:64];

  assign mac_3_a = din_val_d[STAGE1_DELAY] ? C_reg[6] : mac_6;
  assign mac_3_b = mult_3_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_3 <= mac_3_a - mac_3_b;
    else
      mac_3 <= mac_3_a + mac_3_b;
  end


  // MAC-4
  assign mult_4_a = x_powers_current;
  assign mult_4_b = din_val_d[STAGE1_DELAY] ? C_reg[9] : 0;
  
  assign mult_4_p = (mult_4_a * mult_4_b);
  assign mult_4_p_trimmed = mult_4_p[63+:64];

  assign mac_4_a = din_val_d[STAGE1_DELAY] ? C_reg[8] : 0;
  assign mac_4_b = mult_4_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_4 <= mac_4_a - mac_4_b;
    else
      mac_4 <= mac_4_a + mac_4_b;
  end


  // MAC-5
  assign mult_5_a = x_powers_current;
  assign mult_5_b = din_val_d[STAGE1_DELAY] ? C_reg[11] : 0;
  
  assign mult_5_p = (mult_5_a * mult_5_b);
  assign mult_5_p_trimmed = mult_5_p[63+:64];

  assign mac_5_a = din_val_d[STAGE1_DELAY] ? C_reg[10] : 0;
  assign mac_5_b = mult_5_p_trimmed;

  always@ (posedge clk) begin
    if (din_val_d[STAGE1_DELAY])
      mac_5 <= mac_5_a - mac_5_b;
    else
      mac_5 <= mac_5_a + mac_5_b;
  end

  // Not a MAC as there is only 1 term left here. But for ease of naming, consider this to be MAC-6.
  always@ (posedge clk) begin
    mac_6 <= C_reg[12];
  end

  assign final_mult = ((mac_0 + 1'b1) * ccs_mult_2_pow_63_floor_l);
  always@(posedge clk) begin
    final_mult_reg <= final_mult[63+:64];
  end

  assign exp_o = final_mult_reg;
  assign dout_val = din_val_d[STAGE6_DELAY];

endmodule