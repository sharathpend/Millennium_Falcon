//=====================================================
// Designer: 
// email: 
//
//
// Return 1 with probability 2^(-64).z ≈ ccs*(exp(-x))
// Latency = 9 + BerExp + 1
//=====================================================

// mu and sigma_prime float and in R, sigma_prime in [sigma_min, sigma_max]
// inv_sigma_prime supplied inputs (since inv_sigma_prime required for both samplerz instances, makes sense to calculate outside samplerz).
// sigma_min and inv_sigma_min inputs.
// sigma_max and inv_sigma_max inputs.

module samplerz_v6 #(
  parameter NUM_SAMPLING_LOOPS = 1, // Number of parallel sampling loops (1-6)
  parameter MULT_OPT = 0, // 0 = SPEED, 1 = LATENCY for multiplier()
  parameter MULT_OUTPUT_LATENCY = 2, // LATENCY for multiplier(). Supports 1, 2.
  parameter FLOOR_OUTPUT_LATENCY = 1, // only supports 1. Floor/Round latency
  parameter INT_TO_DOUBLE_LATENCY = 1, // currently supports 1.
  parameter DOUBLE_SUB_LATENCY = 1, // currently supports 1.
  parameter EXP_OUTPUT_LATENCY = 8 // latency of floating point exp(x). supports 5-9
) (
  input  wire         clk,
  input  wire         rst,

  input  wire         falcon_type, // 0 = FALCON-512, 1 = FALCON-2014

  input  wire         din_val_i,
  input  wire [63:0]  mu,

  input  wire [63:0]  inv_sigma_prime_sqr_div_2,
  input  wire [63:0]  inv_sigma_prime,


  input  wire         rand_72_val_i,
  input  wire [71:0]  rand_72_i [0:(NUM_SAMPLING_LOOPS-1)],

  // rand_1_val_i and rand_8_val_i expected to come in at the same time.
  // rand_72_val_i should not be too far after din_val_i, or too far after request_rand.
  input  wire         rand_8_val_i,
  input  wire [7:0]   rand_8_i [0:(NUM_SAMPLING_LOOPS-1)],

  input  wire         rand_1_val_i,
  input  wire [(NUM_SAMPLING_LOOPS-1):0] rand_1_i ,

  output wire         request_rand, // requests more random 72, 8, and 1 bit random

  output wire         dout_val_o,
  output wire [63:0]  w_o
);

  //input  wire [63:0] inv_sigma_max_sqr,
  //input  wire [63:0] inv_sigma_max_sqr_div_2,
  //input  wire [63:0] sigma_min,
  
  /*
  itd = int_to_double
  dti = double_to_int
  
  mu, sigma_prime input in R
  sigma_prime in [sigma_min, sigma_max] (from Falcon Tree, created during keygen)

  inv_sigma_prime input (stored in lowest level of Falcon Tree during keygen)
  
  Recommended Parameters
  sigma_max = 1.8205 (FALCON-512 and FALCON-1024)
  sigma_min = 1.277833697 (FALCON-512), 1.298280334 (FALCON-1024)


  inv_sigma_max_sqr_div_2 constant

  0 : mu to floor. sigma_min and inv_sigma_prime to mult. BaseSampler starts.
  1 : floor(mu) ready, sent to itd. z0=BaseSampler() ready. inv_sigma_prime_sqr_div_2_reg_l = inv_sigma_prime_sqr_div_2 ready
  2 : i2d(floor(mu) ready, sent to subtractor. ccs=sigma_min*inv_sigma_prime ready. z=b?(b+z0):(b-z0), sent to itd.
  3 : r=mu-i2d(floor(mu) and itd(z) ready, both sent to subtractor.
  4 : z_sub_r=z-r ready. Sent to multiplier.
  5 : 
  6 : z_sub_r_sqr=(z-r)^2 ready, sent to mult with inv_sigma_prime_sqr_div_2_reg_l. z and PAR_INV_SIGMA_MAX_SQR_DIV_2 sent to mult.
  7 : 
  8 : PART_1 of x ready. PART_2 of x ready. Both sent to sub
  9 : x ready. sent to BerExp


  */

  localparam [63:0] POW_2_63 = 64'h43E0000000000000; // 2^63 in double float
  localparam [63:0] INV_2 = 64'h3FE0000000000000; // 1/2 in double float
  localparam [63:0] INV_LN_2 = 64'h3FF71547652B82FE; // 1/ln(2) in double float
  localparam [63:0] LN_2 = 64'h3FE62E42FEFA3BDC; // ln(2) in double float

  localparam BASE_SAMPLER_LATENCY = 1;
  localparam MULT2_OUTPUT_LATENCY = MULT_OUTPUT_LATENCY + 1;

  // sigma_max = 1.8205
  // (1/2)*((1/sigma_max)^2) = 0.15086504887537272153231216302
  // sigma_min for FALCON 512 = 1.277833697
  // sigma_min for FALCON 1024 = 1.298280334
  localparam [63:0] PAR_INV_SIGMA_MAX_SQR_DIV_2 = 64'h3FC34F8BC183BBC2;
  localparam [63:0] PAR_SIGMA_MIN_FALCON_512 = 64'h3FF47201BF2577E7;
  localparam [63:0] PAR_SIGMA_MIN_FALCON_1024 = 64'h3FF4C5C199791E8B;

  localparam NUM_DELAY_REGS_DIN_VAL = (FLOOR_OUTPUT_LATENCY + INT_TO_DOUBLE_LATENCY) > (BASE_SAMPLER_LATENCY + 1) ? (FLOOR_OUTPUT_LATENCY + INT_TO_DOUBLE_LATENCY) : (BASE_SAMPLER_LATENCY + 1);

  localparam OP1_DELAY = FLOOR_OUTPUT_LATENCY; // output of floor(mu) ready
  localparam OP2_DELAY = OP1_DELAY + INT_TO_DOUBLE_LATENCY; // output of i2d(floor(mu)) ready

  localparam BASE_SAMPL_OUTPUT_DELAY = BASE_SAMPLER_LATENCY; // output of Base Sampler ready
  // 1 cycle after Base sampler, to perform b+(2b-1)z0. This extra cycle technically won't effect the critical path, as this is the same as the critical path of (mu - i2d(floor(mu)))
  // Maybe the base sampler and the extra addition outside could be partitioned better if running into timing failures here, but not yet happened.
  localparam Z_NEXT_DELAY = BASE_SAMPL_OUTPUT_DELAY + 1;


  (* max_fanout = 10 *) reg  [(NUM_DELAY_REGS_DIN_VAL):1] din_val_i_d = 'd0;
  reg  [63:0] mu_reg_l = 'd0;
  (* max_fanout = 2 *) reg  [63:0] floor_mu_reg_l = 'd0;
  reg  [7:0] rand_8_i_l [0:(NUM_SAMPLING_LOOPS-1)];

  wire [63:0] sigma_min;

  wire floor_mu_val_net;
  wire [63:0] floor_mu_net;

  wire mult1_result_tvalid;
  wire [63:0] mult1_result_tdata;

  wire i2d_floor_mu_val_net;
  wire [63:0] i2d_floor_mu_net;

  wire sub1_result_tvalid;
  wire [63:0] sub1_result_tdata;

  //wire inv_sigma_prime_sqr_val_net;
  //wire [63:0] inv_sigma_prime_sqr_net;

  //wire inv_sigma_max_sqr_div_2_val_net;
  //wire [63:0] inv_sigma_max_sqr_div_2_net;
  //reg  [63:0] inv_sigma_max_sqr_div_2_reg_l = 'd0;
  //reg  [63:0] inv_sigma_max_sqr_div_2_reg_l_d [0:(NUM_SAMPLING_LOOPS-1)];

  //wire inv_sigma_prime_sqr_div_2_val_net;
  //wire [63:0] inv_sigma_prime_sqr_div_2_net;
  reg  [63:0] inv_sigma_prime_sqr_div_2_reg_l = 'd0;
  reg  [63:0] inv_sigma_prime_sqr_div_2_reg_l_d [0:(NUM_SAMPLING_LOOPS-1)];

  wire [63:0] ccs_net;
  wire ccs_val_net;
  reg [63:0] ccs_reg = 'b0;
  reg [63:0] ccs_reg_d [0:(NUM_SAMPLING_LOOPS-1)];

  wire [63:0] r_net;
  wire r_val_net;

  reg  [(NUM_SAMPLING_LOOPS-1):0] rand_72_val_i_d;
  wire [63:0] z0_net [0:(NUM_SAMPLING_LOOPS-1)];
  reg  [(NUM_SAMPLING_LOOPS-1):0] b_reg_l = 'd0;

  wire [63:0] z0_sqr_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] z0_sqr_val_net;
  reg  [63:0] z0_sqr_reg_l [0:(NUM_SAMPLING_LOOPS-1)];

  reg  [63:0] z_next_reg [0:(NUM_SAMPLING_LOOPS-1)];
  reg  [63:0] z_next_reg_l [0:(NUM_SAMPLING_LOOPS-1)];
  reg  [(NUM_SAMPLING_LOOPS-1):0] z_next_reg_val = 'd0;

  wire [63:0] z_current_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [63:0] z_current [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] z_current_net_val;
  reg  [63:0] z_current_net_d [0:(NUM_SAMPLING_LOOPS-1)];
  reg  [(NUM_SAMPLING_LOOPS-1):0] z_current_net_val_d = 0;
  reg  [63:0] z_current_reg_l [0:(NUM_SAMPLING_LOOPS-1)];

  (* max_fanout = 2 *) reg  process_next_z_reg = 'b0;
  wire [(NUM_SAMPLING_LOOPS-1):0] process_next_z;
  wire [(NUM_SAMPLING_LOOPS-1):0] start_sampling_loop;

  // z_sub_r = z-r
  // z_sub_r_sqr = (z-r)^2

  wire [63:0] z_sub_r_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] z_sub_r_val_net;

  wire [63:0] z_sub_r_sqr_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] z_sub_r_sqr_val_net;

  wire [63:0] x_part_1_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] x_part_1_val_net;

  wire [63:0] x_part_2_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] x_part_2_val_net;

  wire [63:0] x_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] x_val_net;

  wire [63:0] w_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] w_val_net;

  wire [63:0] return_value_net [0:(NUM_SAMPLING_LOOPS-1)];
  wire [(NUM_SAMPLING_LOOPS-1):0] return_value_val_net;
  reg  [63:0] return_value_p [0:(NUM_SAMPLING_LOOPS-1)];
  reg  [63:0] return_value [0:(NUM_SAMPLING_LOOPS-1)];

  reg  [63:0] w_reg = 'b0;
  reg  w_reg_val = 'b0;

  genvar ii;

  // Initial
  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_init_return_val
      initial begin
        return_value_p[ii] <= 'b0;
        return_value[ii] <= 'b0;
        z_current_reg_l[ii] <= 'b0;
        z_next_reg[ii] <= 'b0;
        z_current_net_d[ii] <= 'b0;
        z_next_reg_l[ii] <= 'b0;
        z0_sqr_reg_l[ii] <= 'b0;
        ccs_reg_d[ii] <= 'b0;
        inv_sigma_prime_sqr_div_2_reg_l_d[ii] <= 'b0;
        rand_8_i_l[ii] <= 'b0;
      end
    end
  endgenerate



  // Input Regsiters/Latches/SREG
  always@ (posedge clk) begin
    din_val_i_d <= {din_val_i_d[(NUM_DELAY_REGS_DIN_VAL-1):1], din_val_i};
  end

  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_rand_8_i_l
      always@ (posedge clk) begin
        if (rand_8_val_i) begin
          rand_8_i_l[ii] <= rand_8_i[ii];
        end
      end
    end
  endgenerate

  assign sigma_min = falcon_type ? PAR_SIGMA_MIN_FALCON_1024 : PAR_SIGMA_MIN_FALCON_512;



  // Clock-0
  double_to_int #(
    .OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY)
  ) double_to_int_floor_mu_inst (
    .clk (clk),

    .a_tvalid (din_val_i),
    .a_tready (),
    .a_tdata (mu),

    .result_tvalid (floor_mu_val_net),
    .result_tready (1'b1),
    .result_tdata (floor_mu_net)
  );

  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT2_OUTPUT_LATENCY)
  ) double_mult_v3_ccs_inst (
    .clk (clk),

    .a_tvalid (din_val_i),
    .a_tready (),
    .a_tdata (sigma_min),

    .b_tvalid (din_val_i),
    .b_tready (),
    .b_tdata (inv_sigma_prime),

    .result_tvalid (ccs_val_net),
    .result_tready (1'b1),
    .result_tdata (ccs_net)
  );

  /*
  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) double_mult_v3_inv_sigma_prime_sqr_inst (
    .clk (clk),

    .a_tvalid (din_val_i),
    .a_tready (),
    .a_tdata (inv_sigma_prime),

    .b_tvalid (din_val_i),
    .b_tready (),
    .b_tdata (inv_sigma_prime),

    .result_tvalid (inv_sigma_prime_sqr_val_net),
    .result_tready (1'b1),
    .result_tdata (inv_sigma_prime_sqr_net)
  );
  */

  /*
  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) double_mult_v3_inv_sigma_max_sqr_div_2_inst (
    .clk (clk),

    .a_tvalid (din_val_i),
    .a_tready (),
    .a_tdata (inv_sigma_max_sqr),

    .b_tvalid (din_val_i),
    .b_tready (),
    .b_tdata (INV_2),

    .result_tvalid (inv_sigma_max_sqr_div_2_val_net),
    .result_tready (1'b1),
    .result_tdata (inv_sigma_max_sqr_div_2_net)
  );
  */

  always@ (posedge clk) begin
    if (din_val_i)
      mu_reg_l <= mu;
  end

  always@ (posedge clk) begin
    if (din_val_i) begin
      inv_sigma_prime_sqr_div_2_reg_l <= inv_sigma_prime_sqr_div_2;
    end
  end


  // Clock-1
  int_to_double #(
    .OUTPUT_LATENCY (INT_TO_DOUBLE_LATENCY)
  ) int_to_double_i2d_floor_mu_inst (
    .clk (clk),

    //.a_tvalid (floor_mu_val_net),
    .a_tvalid (din_val_i_d[OP1_DELAY]),
    .a_tready (),
    .a_tdata (floor_mu_net),

    .result_tvalid (i2d_floor_mu_val_net),
    .result_tready (1'b1),
    .result_tdata (i2d_floor_mu_net)
  );

  always@ (posedge clk) begin
    if (ccs_val_net)
      ccs_reg <= ccs_net;
  end

  always@ (posedge clk) begin
    if (din_val_i_d[OP1_DELAY]) begin
      floor_mu_reg_l <= floor_mu_net;
    end
  end

  // Clock-2
  double_sub #(
    .OUTPUT_LATENCY (DOUBLE_SUB_LATENCY)
  ) double_sub_r_inst (
    .clk (clk),

    //.a_tvalid (i2d_floor_mu_val_net),
    .a_tvalid (din_val_i_d[OP2_DELAY]),
    .a_tdata (i2d_floor_mu_net),

    //.b_tvalid (i2d_floor_mu_val_net),
    .b_tvalid (din_val_i_d[OP2_DELAY]),
    .b_tdata (mu_reg_l),

    .result_tvalid (r_val_net),
    .result_tdata (r_net)
  );

  /*
  double_mult_v3 #(
    .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
    .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
  ) double_mult_v3_inv_sigma_prime_sqr_div_2_inst (
    .clk (clk),

    .a_tvalid (inv_sigma_prime_sqr_val_net),
    .a_tready (),
    .a_tdata (inv_sigma_prime_sqr_net),

    .b_tvalid (inv_sigma_prime_sqr_val_net),
    .b_tready (),
    .b_tdata (INV_2),

    .result_tvalid (inv_sigma_prime_sqr_div_2_val_net),
    .result_tready (1'b1),
    .result_tdata (inv_sigma_prime_sqr_div_2_net)
  );
  */

  /*
  always@ (posedge clk) begin
    if (inv_sigma_max_sqr_div_2_val_net)
      inv_sigma_max_sqr_div_2_reg_l <= inv_sigma_max_sqr_div_2_net;
  end
  */

  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_ccs_reg_d
      always@ (posedge clk) begin
        ccs_reg_d[ii] <= ccs_reg;
      end
    end
  endgenerate




  // Clock-3
  /*
  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_inv_sigma_max_sqr_div_2_reg_l_d
      always@ (posedge clk) begin
        inv_sigma_max_sqr_div_2_reg_l_d[ii] <= inv_sigma_max_sqr_div_2_reg_l;
      end
    end
  endgenerate
  */


  // Clock-4


  // Clock-5
  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_inv_sigma_prime_sqr_div_2_reg_l_d
      always@ (posedge clk) begin
        inv_sigma_prime_sqr_div_2_reg_l_d[ii] <= inv_sigma_prime_sqr_div_2_reg_l;
      end
    end
  endgenerate




  // Sampling Loop
  generate
    for (ii = 0; ii < NUM_SAMPLING_LOOPS; ii = ii + 1) begin : gen_multi_sampling_loop
      // Clock-0
      base_sampler_v2 base_sampler_v2_inst (
        .clk (clk),
        .rand_72_i (rand_72_i[ii]),
        .z0_o (z0_net[ii])
      );

      always@ (posedge clk) begin
        rand_72_val_i_d[ii] <= rand_72_val_i; // when BaseSampler is done.
      end

      always@ (posedge clk) begin
        if (rand_1_val_i)
          b_reg_l[ii] <= rand_1_i[ii];
      end


      // Clock-1
      double_mult_v3 #(
        .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
        .OUTPUT_LATENCY (MULT2_OUTPUT_LATENCY)
      ) double_mult_z0_sqr_inst (
        .clk (clk),

        .a_tvalid (rand_72_val_i_d[ii]),
        .a_tready (),
        .a_tdata (z0_net[ii]),

        .b_tvalid (rand_72_val_i_d[ii]),
        .b_tready (),
        .b_tdata (z0_net[ii]),

        .result_tvalid (z0_sqr_val_net[ii]),
        .result_tready (1'b1),
        .result_tdata (z0_sqr_net[ii])
      );

      always@ (posedge clk) begin
        if (rand_72_val_i_d[ii]) begin
          z_next_reg_val[ii] <= 'b1; // currently unused
          if (b_reg_l[ii] =='b1)
            z_next_reg[ii] <= {7'b0, b_reg_l[ii]} + z0_net[ii];
          else
            z_next_reg[ii] <= {7'b0, b_reg_l[ii]} - z0_net[ii];
        end else begin
          z_next_reg_val[ii] <= 'b0;
        end
      end


      // Clock-2
      assign process_next_z[ii] = process_next_z_reg;

      int_to_double #(
        .OUTPUT_LATENCY (INT_TO_DOUBLE_LATENCY)
      ) int_to_double_z_current_inst (
        .clk (clk),

        //.a_tvalid (fpu_mf1_result_tvalid),
        .a_tvalid (din_val_i_d[Z_NEXT_DELAY] | process_next_z[ii]),
        .a_tready (),
        .a_tdata (z_next_reg[ii]),

        .result_tvalid (z_current_net_val[ii]),
        .result_tready (1'b1),
        .result_tdata (z_current_net[ii])
      );

      always@ (posedge clk) begin
        if (z_next_reg_val[ii]) begin
          z_next_reg_l[ii] <= z_next_reg[ii];
        end
      end

      /*
      always@ (posedge clk) begin
        if (din_val_i_d[Z_NEXT_DELAY]) begin
          start_sampling_loop[ii] <= 'b1;
          //z_reg_current[ii] <= z_reg_next[ii];
        end else begin // need to add more conditions here
          start_sampling_loop[ii] <= 'b0;
        end
      end
      */

      if (DOUBLE_SUB_LATENCY == 1) begin
        assign z_current[ii] = z_current_net[ii];
        assign start_sampling_loop[ii] = z_current_net_val[ii];
      end else if (DOUBLE_SUB_LATENCY == 2) begin
        always@ (posedge clk) begin
          z_current_net_d[ii] <= z_current_net[ii];
          z_current_net_val_d[ii] <= z_current_net_val[ii];
        end
        assign z_current[ii] = z_current_net_d[ii];
        assign start_sampling_loop[ii] = z_current_net_val_d[ii];
      end else begin
        assign z_current[ii] = z_current_net[ii];
        assign start_sampling_loop[ii] = z_current_net_val[ii];
      end


      // Clock-3
      double_sub #(
        .OUTPUT_LATENCY (DOUBLE_SUB_LATENCY)
      ) double_sub_z_sub_r_inst (
        .clk (clk),

        //.a_tvalid (i2d_floor_mu_val_net),
        .a_tvalid (start_sampling_loop[ii]),
        .a_tdata (z_current[ii]),

        //.b_tvalid (i2d_floor_mu_val_net),
        .b_tvalid (start_sampling_loop[ii]),
        .b_tdata (r_net),

        .result_tvalid (z_sub_r_val_net[ii]),
        .result_tdata (z_sub_r_net[ii])
      );

      /*
      double_add #(
        .OUTPUT_LATENCY (DOUBLE_SUB_LATENCY)
      ) double_add_return_value_inst (
        .clk (clk),

        //.a_tvalid (i2d_floor_mu_val_net),
        .a_tvalid (z_current_net_val[ii]),
        .a_tdata (z_current_net[ii]),

        //.b_tvalid (i2d_floor_mu_val_net),
        .b_tvalid (z_current_net_val[ii]),
        .b_tdata (floor_mu_reg_l),

        .result_tvalid (return_value_val_net[ii]),
        .result_tdata (return_value_net[ii])
      );
      */

      always@ (posedge clk) begin
        return_value_p[ii] <= z_next_reg_l[ii] + floor_mu_reg_l;
      end

      always@ (posedge clk) begin
        if (z_current_net_val[ii]) begin
          z_current_reg_l[ii] <= z_current_net[ii];
        end
      end

      always@ (posedge clk) begin
        if (z0_sqr_val_net[ii]) begin
          z0_sqr_reg_l[ii] <= z0_sqr_net[ii];
        end
      end


      // Clock-4
      double_mult_v3 #(
        .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
        .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
      ) double_mult_z_sub_r_sqr_inst (
        .clk (clk),

        .a_tvalid (z_sub_r_val_net[ii]),
        .a_tready (),
        .a_tdata (z_sub_r_net[ii]),

        .b_tvalid (z_sub_r_val_net[ii]),
        .b_tready (),
        .b_tdata (z_sub_r_net[ii]),

        .result_tvalid (z_sub_r_sqr_val_net[ii]),
        .result_tready (1'b1),
        .result_tdata (z_sub_r_sqr_net[ii])
      );

      always@ (posedge clk) begin
        return_value[ii] <= return_value_p[ii];
      end


      // Clock-5


      // Clock-6
      double_mult_v3 #(
        .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
        .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
      ) double_mult_x_part_1_inst (
        .clk (clk),

        .a_tvalid (z_sub_r_sqr_val_net[ii]),
        .a_tready (),
        .a_tdata (z_sub_r_sqr_net[ii]),

        .b_tvalid (z_sub_r_sqr_val_net[ii]),
        .b_tready (),
        .b_tdata (inv_sigma_prime_sqr_div_2_reg_l_d[ii]),

        .result_tvalid (x_part_1_val_net[ii]),
        .result_tready (1'b1),
        .result_tdata (x_part_1_net[ii])
      );

      double_mult_v3 #(
        .OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY
        .OUTPUT_LATENCY (MULT_OUTPUT_LATENCY)
      ) double_mult_x_part_2_inst (
        .clk (clk),

        .a_tvalid (z_sub_r_sqr_val_net[ii]),
        .a_tready (),
        .a_tdata (z0_sqr_reg_l[ii]),

        .b_tvalid (z_sub_r_sqr_val_net[ii]),
        .b_tready (),
        //.b_tdata (inv_sigma_max_sqr_div_2_reg_l_d[ii]),
        .b_tdata (PAR_INV_SIGMA_MAX_SQR_DIV_2),

        .result_tvalid (x_part_2_val_net[ii]),
        .result_tready (1'b1),
        .result_tdata (x_part_2_net[ii])
      );


      // Clock-7


      // Clock-8
      double_sub #(
        .OUTPUT_LATENCY (DOUBLE_SUB_LATENCY)
      ) double_sub_x_inst (
        .clk (clk),

        //.a_tvalid (i2d_floor_mu_val_net),
        .a_tvalid (x_part_1_val_net[ii]),
        .a_tdata (x_part_1_net[ii]),

        //.b_tvalid (i2d_floor_mu_val_net),
        .b_tvalid (x_part_2_val_net[ii]),
        .b_tdata (x_part_2_net[ii]),

        .result_tvalid (x_val_net[ii]),
        .result_tdata (x_net[ii])
      );


      // Clock-9
      berexp_v6 #(
        .MULT_OPT (MULT_OPT), // 0 = SPEED, 1 = LATENCY for multiplier()
        .MULT_OUTPUT_LATENCY (MULT_OUTPUT_LATENCY), // LATENCY for multiplier(). Supports 1, 2.
        .FLOOR_OUTPUT_LATENCY (FLOOR_OUTPUT_LATENCY), // only supports 1. Floor/Round latency
        .INT_TO_DOUBLE_LATENCY (INT_TO_DOUBLE_LATENCY), // currently supports 1.
        .DOUBLE_SUB_LATENCY (DOUBLE_SUB_LATENCY), // currently supports 1.
        .EXP_OUTPUT_LATENCY (EXP_OUTPUT_LATENCY)
      ) berexp_v6_inst (
        .clk (clk),
        .rst (rst),

        .din_val_i (x_val_net[ii]),
        .din_rdy_o (),
        .ccs_i (ccs_reg_d[ii]),
        .x_i (x_net[ii]),
        .rand_8_i (rand_8_i_l[ii]),

        .dout_val_o (w_val_net[ii]),
        .dout_rdy_i (1'b1),
        .w_o (w_net[ii])
      );

    end
  endgenerate

  // As the BerExp starts, request new random values. At this point, all random data is either consumed
  // or sent to BEREXP, so new data can be processed.
  assign request_rand = x_val_net[0];

  generate
  if (NUM_SAMPLING_LOOPS == 6) begin : gen_w_reg_6
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else if (w_net[1] == 'b1) begin
          w_reg <= return_value[1];
          w_reg_val <= 'b1;
        end else if (w_net[2] == 'b1) begin
          w_reg <= return_value[2];
          w_reg_val <= 'b1;
        end else if (w_net[3] == 'b1) begin
          w_reg <= return_value[3];
          w_reg_val <= 'b1;
        end else if (w_net[4] == 'b1) begin
          w_reg <= return_value[4];
          w_reg_val <= 'b1;
        end else if (w_net[5] == 'b1) begin
          w_reg <= return_value[5];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end else if (NUM_SAMPLING_LOOPS == 5) begin : gen_w_reg_5
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else if (w_net[1] == 'b1) begin
          w_reg <= return_value[1];
          w_reg_val <= 'b1;
        end else if (w_net[2] == 'b1) begin
          w_reg <= return_value[2];
          w_reg_val <= 'b1;
        end else if (w_net[3] == 'b1) begin
          w_reg <= return_value[3];
          w_reg_val <= 'b1;
        end else if (w_net[4] == 'b1) begin
          w_reg <= return_value[4];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end else if (NUM_SAMPLING_LOOPS == 4) begin : gen_w_reg_4
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else if (w_net[1] == 'b1) begin
          w_reg <= return_value[1];
          w_reg_val <= 'b1;
        end else if (w_net[2] == 'b1) begin
          w_reg <= return_value[2];
          w_reg_val <= 'b1;
        end else if (w_net[3] == 'b1) begin
          w_reg <= return_value[3];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end else if (NUM_SAMPLING_LOOPS == 3) begin : gen_w_reg_3
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else if (w_net[1] == 'b1) begin
          w_reg <= return_value[1];
          w_reg_val <= 'b1;
        end else if (w_net[2] == 'b1) begin
          w_reg <= return_value[2];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end else if (NUM_SAMPLING_LOOPS == 2) begin : gen_w_reg_2
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else if (w_net[1] == 'b1) begin
          w_reg <= return_value[1];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end else if (NUM_SAMPLING_LOOPS == 1) begin : gen_w_reg_1
    always_ff@ (posedge clk) begin
      process_next_z_reg <= 'b0;
      w_reg_val <= 'b0;
      if (w_val_net[0]) begin
        if (w_net[0] == 'b1) begin
          w_reg <= return_value[0];
          w_reg_val <= 'b1;
        end else begin
          process_next_z_reg <= 'b1;
          w_reg_val <= 'b0;
        end
      end else begin
        process_next_z_reg <= 'b0;
        w_reg_val <= 'b0;
      end
    end
  end
  endgenerate

  assign w_o = w_reg;
  assign dout_val_o = w_reg_val;

endmodule