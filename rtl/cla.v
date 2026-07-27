`timescale 1ns / 1ps

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
   assign g = a & b;
   assign p = a | b;
endmodule

module gp2(input wire [1:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire cout);
   assign cout = gin[0] | (pin[0] & cin);
   assign pout = pin[1] & pin[0];
   assign gout = gin[1] | (pin[1] & gin[0]);
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits internally would generate a carry-out (independent of cin)
 * @param pout whether these 4 bits internally would propagate an incoming carry from cin
 * @param cout the carry outs for the low-order 3 bits
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout);
   
   wire g_low, p_low, g_high, p_high;
   wire c2;
   
   // Process lower 2 bits (bits 1-0)
   gp2 gp2_low (
       .gin(gin[1:0]),
       .pin(pin[1:0]),
       .cin(cin),
       .gout(g_low), // g_10
       .pout(p_low), // p_10
       .cout(cout[0])
   );
   
   // Carry into upper 2 bits
   assign c2 = g_low | (p_low & cin); // g_10 | (p_10 & c_0)
   
   // Process upper 2 bits (bits 3-2)
   gp2 gp2_high (
       .gin(gin[3:2]),
       .pin(pin[3:2]),
       .cin(c2),
       .gout(g_high),
       .pout(p_high),
       .cout(cout[2])
   );
   
   // Carry out for bit 1 (middle position)
   assign cout[1] = c2;
   
   // Overall generate and propagate for 4-bit window
   assign gout = g_high | (p_high & g_low);
   assign pout = p_high & p_low;
   
endmodule

/** Same as gp4 but for an 8-bit window instead */
module gp8(input wire [7:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [6:0] cout);
   wire g_low, p_low, g_high, p_high;
   wire [2:0] cout_low, cout_high;
   wire c4;
   gp4 gp4_low (
       .gin(gin[3:0]),
       .pin(pin[3:0]),
       .cin(cin),
       .gout(g_low),
       .pout(p_low),
       .cout(cout_low)
   );
   assign c4 = g_low | (p_low & cin);
   gp4 gp4_high (
       .gin(gin[7:4]),
       .pin(pin[7:4]),
       .cin(c4),
       .gout(g_high),
       .pout(p_high),
       .cout(cout_high)
   );
   assign gout = g_high | (p_high & g_low);
   assign pout = p_high & p_low;
   assign cout = {cout_high, c4, cout_low};
endmodule

module cla
  (input wire [31:0]  a, b,
   input wire         cin,
   output wire [31:0] sum);
   wire [31:0] g, p;
   wire [31:0] carry;
   wire [6:0] cout0, cout1, cout2, cout3;
   wire gout0, pout0, gout1, pout1, gout2, pout2, gout3, pout3;
   wire c8, c16, c24;
   genvar i;
   for (i = 0; i < 32; i = i + 1) begin
       gp1 gp1_inst (
           .a(a[i]),
           .b(b[i]),
           .g(g[i]),
           .p(p[i])
       );
   end
   assign carry[0] = cin;
   gp8 gp8_0 (
       .gin(g[7:0]),
       .pin(p[7:0]),
       .cin(cin),
       .gout(gout0),
       .pout(pout0),
       .cout(cout0)
   );
   assign c8 = gout0 | (pout0 & cin);
   assign carry[1 +: 7] = cout0;
   assign carry[8] = c8;
   gp8 gp8_1 (
       .gin(g[15:8]),
       .pin(p[15:8]),
       .cin(c8),
       .gout(gout1),
       .pout(pout1),
       .cout(cout1)
   );
   assign c16 = gout1 | (pout1 & c8);
   assign carry[9 +: 7] = cout1;
   assign carry[16] = c16;
   gp8 gp8_2 (
       .gin(g[23:16]),
       .pin(p[23:16]),
       .cin(c16),
       .gout(gout2),
       .pout(pout2),
       .cout(cout2)
   );
   assign c24 = gout2 | (pout2 & c16);
   assign carry[17 +: 7] = cout2;
   assign carry[24] = c24;
   gp8 gp8_3 (
       .gin(g[31:24]),
       .pin(p[31:24]),
       .cin(c24),
       .gout(gout3),
       .pout(pout3),
       .cout(cout3)
   );
   assign carry[25 +: 7] = cout3;
   assign sum = a ^ b ^ carry;
endmodule