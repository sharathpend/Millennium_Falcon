//=====================================================
// Designer: 
// email: 
//=====================================================

// Horner's Method

module approxexp_v2 #(
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter FLOOR_OUTPUT_LATENCY = 1, // only supports 1. Round/Floor latency
  parameter MULT_OUTPUT_LATENCY = 2 // LATENCY for multiplier(). Supports 1, 2.
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

  //localparam MULT_OPT = 0; // 0 = SPEED, 1 = LATENCY for multiplier()
  //localparam FLOOR_OUTPUT_LATENCY = 1; // only supports 1. Round/Floor latency
  //localparam MULT_OUTPUT_LATENCY = 2; // LATENCY for multiplier(). Supports 1, 2.

  localparam NUM_BITS_DIN_VAL_SREG = ((MULT_OUTPUT_LATENCY+FLOOR_OUTPUT_LATENCY)*2);

  // MULT_OUTPUT_LATENCY=1. din_val_sreg[1] <-> x_i computation complete. din_val_sreg[3] <-> ccs_i computation complete.
  // MULT_OUTPUT_LATENCY=2. din_val_sreg[2] <-> x_i computation complete. din_val_sreg[5] <-> ccs_i computation complete.
  localparam X_CALC_DONE_BIT = (1*(MULT_OUTPUT_LATENCY+FLOOR_OUTPUT_LATENCY))-1; // bit position of din_val_sreg indicatting x_i computation complete
  localparam CCS_CALC_DONE_BIT = (2*(MULT_OUTPUT_LATENCY+FLOOR_OUTPUT_LATENCY))-1; // bit position of din_val_sreg indicatting ccs_i computation complete

  localparam [63:0] POW_2_63 = 64'h43E0000000000000; // 2^63 in double float

  (* max_fanout = 20 *) reg [NUM_BITS_DIN_VAL_SREG-1:0] din_val_sreg = 'b0;
  (* max_fanout = 20 *) reg dout_val_p1 = 'b0;
  (* max_fanout = 20 *) reg dout_val_reg = 'b0;

  reg [63:0] exp_reg = 'b0; // equivalent to fpu_mf1_result_tvalid for ccs_i


  wire [63:0] fpu_mf1_result_tdata;
  (* max_fanout = 20 *) wire fpu_mf1_result_tvalid;

  wire fpu_mf1_a_tvalid;
  wire fpu_mf1_b_tvalid;
  wire [63:0] fpu_mf1_a_tdata;
  reg  [63:0] fpu_mf1_b_tdata;
  reg  [63:0] ccs_reg = 'd0;

  wire [63:0] z_net;
  reg  [63:0] z_reg;

  wire [63:0] y_net;

  reg  [3:0] C_index = 'd0;

  reg  [63:0] z2;

  (* max_fanout = 20 *) reg [10:0] fpu_mf1_result_tvalid_sreg = 'd0;

  always@ (posedge clk) begin
    if (din_val)
      ccs_reg <= ccs_i;
  end

  always@ (posedge clk) begin
    if (rst) begin
      fpu_mf1_result_tvalid_sreg <= 'd0;
      C_index <= 'd1;
    end else begin
      fpu_mf1_result_tvalid_sreg <= {fpu_mf1_result_tvalid_sreg[9:0], din_val_sreg[X_CALC_DONE_BIT]};

      if ((|fpu_mf1_result_tvalid_sreg) | din_val_sreg[X_CALC_DONE_BIT])
        C_index <= C_index + 'b1;
      else
        C_index <= 'd1;
    end

    dout_val_p1 <= fpu_mf1_result_tvalid_sreg[10];
  end

  always@ (posedge clk) begin
    din_val_sreg <= {din_val_sreg[(NUM_BITS_DIN_VAL_SREG-2):0], din_val};
  end

  // first, we send x_i, then we send ccs_i 2 cycles later
  assign fpu_mf1_a_tdata = din_val ? x_i : ccs_reg;
  assign fpu_mf1_a_tvalid = din_val | din_val_sreg[X_CALC_DONE_BIT];
  assign fpu_mf1_b_tvalid = fpu_mf1_a_tvalid;

  always@ (posedge clk) begin
    fpu_mf1_b_tdata <= POW_2_63;
  end

  // Line 3
  fpu_mult_floor #(
    .MULT_OPT (MULT_OPT),
    .ROUND_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY),
    .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) fpu_mult_floor_inst1 (
    .clk (clk),

    // m_axis
    .a_tvalid (fpu_mf1_a_tvalid),
    .a_tready (),
    .a_tdata (fpu_mf1_a_tdata),

    // m_axis
    .b_tvalid (fpu_mf1_b_tvalid),
    .b_tready (),
    .b_tdata (fpu_mf1_b_tdata),

    // s_axis
    .result_tvalid (fpu_mf1_result_tvalid),
    .result_tready (1'b1),
    .result_tdata (fpu_mf1_result_tdata)
  );

  assign z_net = din_val_sreg[X_CALC_DONE_BIT] ? fpu_mf1_result_tdata : z_reg;

  always@ (posedge clk) begin
    if (din_val_sreg[X_CALC_DONE_BIT])
      z_reg <= z_net;
  end

  always@ (posedge clk) begin
    if (din_val_sreg[CCS_CALC_DONE_BIT])
      z2 <= fpu_mf1_result_tdata;
  end

  // Line 2, 4, 5
  // Latency should be 12.
  approxexp_loop approxexp_loop_inst (
    .clk (clk),

    .C_index (C_index),
    .y_init (din_val_sreg[X_CALC_DONE_BIT-1]),
    .y_loop (|{fpu_mf1_result_tvalid_sreg, din_val_sreg[X_CALC_DONE_BIT]}),
    .z_i (z_net),

    .y_o (y_net)
  );

  always@ (posedge clk) begin
    if (dout_val_p1) begin
      exp_reg <= (z2*y_net) >> 63;
    end
    dout_val_reg <= dout_val_p1;
  end

  assign exp_o = exp_reg;
  assign dout_val = dout_val_reg;

endmodule