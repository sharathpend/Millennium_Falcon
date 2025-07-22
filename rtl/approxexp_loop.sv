//=====================================================
// Designer: 
// email: 
//=====================================================

// Horner's Method

module approxexp_loop (
  input  wire clk,

  input  wire C_index,
  input  wire y_init,
  input  wire y_loop,
  input  wire [63:0] z_i,

  output wire [63:0] y_o

);

  reg [63:0] y_reg = 'd0;
  wire [127:0] y_z_prod; 


  reg [63:0] C_reg [0:12] = { 64'h00000004741183A3,
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
                              64'h8000000000000000};
  
  assign y_z_prod = y_reg * z_i;

  always@ (posedge clk) begin
    if (y_init) begin
      y_reg <= C_reg[0];
    end else if (y_loop) begin
      y_reg <= C_reg[C_index] + y_z_prod[126:63];
    end
  end

  assign y_o = y_reg;


endmodule