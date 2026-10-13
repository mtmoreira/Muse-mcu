`timescale 1ns/1ps
module inv(input a, output y);
  assign y = ~a;
  specify
    (a => y) = 5.0;
  endspecify
endmodule
module tb;
  reg a = 0; wire y;
  inv i(.a(a), .y(y));
  initial begin
    $monitor("t=%0t a=%b y=%b", $time, a, y);
    #3 a = 1;
    #20 $finish;
  end
endmodule
