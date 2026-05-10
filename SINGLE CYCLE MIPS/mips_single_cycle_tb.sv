module tb;
  logic clk;
  logic reset;
  logic [31:0] writedata, dataadr;
  logic memwrite;

  top dut(clk, reset, writedata, dataadr, memwrite);

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
    reset = 1;
    #10 reset = 0;
    #100 $finish;
  end
endmodule