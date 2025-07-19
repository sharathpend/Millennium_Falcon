//=====================================================
// Designer: 
// email: 
//=====================================================

// Latency = 1

// rand_72_i uniform random 8 bits

module base_sampler_v2 (
  input  wire        clk,
  input  wire [71:0] rand_72_i,
  output wire [63:0] z0_o
);

  (* max_fanout = 10 *) wire [17:0] z0_step;
  (* max_fanout = 10 *) wire [71:0] rand_72;
  (* max_fanout = 10 *) reg  [63:0] z0_reg = 'd0;

  assign rand_72 = rand_72_i;

  assign z0_step[0]  = ((rand_72 <  72'd1) ? 1'b1 : 1'b0); // RCDT[17]
  assign z0_step[1]  = ((rand_72 <  72'd198) ? 1'b1 : 1'b0);
  assign z0_step[2]  = ((rand_72 <  72'd28824) ? 1'b1 : 1'b0);
  assign z0_step[3]  = ((rand_72 <  72'd3104126) ? 1'b1 : 1'b0);
  assign z0_step[4]  = ((rand_72 <  72'd247426747) ? 1'b1 : 1'b0);
  assign z0_step[5]  = ((rand_72 <  72'd14602316184) ? 1'b1 : 1'b0);
  assign z0_step[6]  = ((rand_72 <  72'd638331848991) ? 1'b1 : 1'b0);
  assign z0_step[7]  = ((rand_72 <  72'd20680885154299) ? 1'b1 : 1'b0);
  assign z0_step[8]  = ((rand_72 <  72'd496969357462633) ? 1'b1 : 1'b0);
  assign z0_step[9]  = ((rand_72 <  72'd8867391802663976) ? 1'b1 : 1'b0);
  assign z0_step[10] = ((rand_72 <  72'd117656387352093658) ? 1'b1 : 1'b0);
  assign z0_step[11] = ((rand_72 <  72'd1163297957344668388) ? 1'b1 : 1'b0);
  assign z0_step[12] = ((rand_72 <  72'd8595902006365044063) ? 1'b1 : 1'b0);
  assign z0_step[13] = ((rand_72 <  72'd47667343854657281903) ? 1'b1 : 1'b0);
  assign z0_step[14] = ((rand_72 <  72'd199560484645026482916) ? 1'b1 : 1'b0);
  assign z0_step[15] = ((rand_72 <  72'd636254429462080897535) ? 1'b1 : 1'b0);
  assign z0_step[16] = ((rand_72 <  72'd1564742784480091954050) ? 1'b1 : 1'b0);
  assign z0_step[17] = ((rand_72 <  72'd3024686241123004913666) ? 1'b1 : 1'b0); // RCDT[0]

  always@ (posedge clk) begin
    z0_reg[6:0] <=  (((z0_step[ 0] + z0_step[15]) + (z0_step[ 1] + z0_step[14])) + 
                     ((z0_step[ 2] + z0_step[13]) + (z0_step[ 3] + z0_step[12]))) + 
                    (((z0_step[ 4] + z0_step[11]) + (z0_step[ 5] + z0_step[10])) + 
                     ((z0_step[ 6] + z0_step[ 9]) + (z0_step[ 7] + z0_step[ 8]))) + 
                    (z0_step[16] + z0_step[17]);
  end

  assign z0_o = z0_reg;

endmodule