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
    #12 reset = 0;
  end

  always @(negedge clk) begin
    if (memwrite) begin
      $display("Memory Write: Addr=%d, Data=%d", dataadr, writedata);
      if (dataadr === 84 && writedata === 7) begin
        $display("Simulation Succeeded!");
        $finish; 
      end 
    end
  end

  initial begin
    #1000; 
    $display("Simulation Timed Out.");
    $finish;
  end
endmodule