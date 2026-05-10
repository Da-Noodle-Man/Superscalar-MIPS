module top(input  logic clk, reset, 
           output logic [31:0] writedata, dataadr, 
           output logic memwrite);

  logic [31:0] pc, instr, readdata;

  mips mips(clk, reset, pc, instr, memwrite, dataadr, writedata, readdata);
  imem imem(pc[7:2], instr);
  dmem dmem(clk, memwrite, dataadr, writedata, readdata);
endmodule

module mips(input  logic clk, reset,
            output logic [31:0] pc,
            input  logic [31:0] instr,
            output logic memwrite,
            output logic [31:0] aluout, writedata,
            input  logic [31:0] readdata);

  logic [2:0] alucontrol_d;
  logic memtoreg_d, memwrite_d, pcsrc_d, alusrc_d, regdst_d, regwrite_d, jump_d, branch_d;
  logic [31:0] instr_d;

  controller c(instr_d[31:26], instr_d[5:0], 
               memtoreg_d, memwrite_d, alusrc_d, 
               regdst_d, regwrite_d, jump_d, branch_d, alucontrol_d);

  datapath dp(clk, reset, memtoreg_d, memwrite_d, pcsrc_d, alusrc_d, 
              regdst_d, regwrite_d, jump_d, branch_d, alucontrol_d,
              pc, instr, memwrite, aluout, writedata, readdata, instr_d);
endmodule

module controller(input  logic [5:0] op, funct,
                  output logic memtoreg, memwrite, alusrc,
                  output logic regdst, regwrite, jump, branch,
                  output logic [2:0] alucontrol);

  logic [1:0] aluop;
  maindec md(op, memtoreg, memwrite, branch, alusrc, regdst, regwrite, jump, aluop);
  aludec  ad(funct, aluop, alucontrol);
endmodule

module maindec(input  logic [5:0] op,
               output logic memtoreg, memwrite, branch, alusrc,
               output logic regdst, regwrite, jump,
               output logic [1:0] aluop);

  logic [8:0] controls;
  assign {regwrite, regdst, alusrc, branch, memwrite, memtoreg, jump, aluop} = controls;

  always_comb
    case(op)
      6'b000000: controls = 9'b1100000_10; 
      6'b100011: controls = 9'b1010010_00; 
      6'b101011: controls = 9'b0010100_00; 
      6'b000100: controls = 9'b0001000_01; 
      6'b001000: controls = 9'b1010000_00; 
      6'b000010: controls = 9'b0000001_00; 
      default:   controls = 9'b0000000_00;
    endcase
endmodule

module aludec(input  logic [5:0] funct,
              input  logic [1:0] aluop,
              output logic [2:0] alucontrol);

  always_comb
    case(aluop)
      2'b00: alucontrol = 3'b010; 
      2'b01: alucontrol = 3'b110; 
      default: case(funct)          
          6'b100000: alucontrol = 3'b010; 
          6'b100010: alucontrol = 3'b110; 
          6'b100100: alucontrol = 3'b000; 
          6'b100101: alucontrol = 3'b001; 
          6'b101010: alucontrol = 3'b111; 
          default:   alucontrol = 3'bxxx; 
        endcase
    endcase
endmodule

module datapath(input  logic clk, reset,
                input  logic memtoreg_d, memwrite_d, 
                output logic pcsrc_d,
                input  logic alusrc_d, regdst_d, regwrite_d, 
                input  logic jump_d, branch_d,
                input  logic [2:0] alucontrol_d,
                output logic [31:0] pc_f,
                input  logic [31:0] instr_f,
                output logic memwrite_m,
                output logic [31:0] aluout_m, writedata_m,
                input  logic [31:0] readdata_m,
                output logic [31:0] instr_d);

  logic [31:0] pcnext_f, pcplus4_f, pcplus4_d, pcbranch_d;
  logic [31:0] rd1_d, rd2_d, rd1_d_final, rd2_d_final;
  logic [31:0] signimm_d, signimmsh_d, srca_e, srcb_e, writedata_e;
  logic [31:0] aluout_e, aluout_w, readdata_w, result_w, signimm_e;
  logic [4:0]  rs_e, rt_e, rd_e, writereg_e, writereg_m, writereg_w;
  logic [2:0]  alucontrol_e;
  logic        alusrc_e, regdst_e, regwrite_e, memtoreg_e, memwrite_e;
  logic        regwrite_m, memtoreg_m, regwrite_w, memtoreg_w;
  logic [1:0]  forwarda_e, forwardb_e;
  logic        stall_f, stall_d, flush_e;
  logic [31:0] srca_e_final, writedata_e_final;

  hazard h(instr_d[25:21], instr_d[20:16], rs_e, rt_e, writereg_e, writereg_m, writereg_w,
           regwrite_e, regwrite_m, regwrite_w, memtoreg_e, memtoreg_m, branch_d, pcsrc_d,
           forwarda_e, forwardb_e, stall_f, stall_d, flush_e);

  assign pcsrc_d = branch_d & (rd1_d_final == rd2_d_final);

  floprc #(32) pcreg(clk, reset, 1'b0, ~stall_f, pcnext_f, pc_f);
  adder         pcadd1(pc_f, 32'b100, pcplus4_f);
  mux2 #(32)    pcbrmux(pcplus4_f, pcbranch_d, pcsrc_d, pcnext_f);

  floprc #(32) f_d_instr(clk, reset, pcsrc_d, ~stall_d, instr_f, instr_d);
  floprc #(32) f_d_pc(clk, reset, pcsrc_d, ~stall_d, pcplus4_f, pcplus4_d);

  regfile rf(clk, regwrite_w, instr_d[25:21], instr_d[20:16], writereg_w, result_w, rd1_d, rd2_d);
  signext se(instr_d[15:0], signimm_d);
  sl2     immsh(signimm_d, signimmsh_d);
  adder   pcadd2(pcplus4_d, signimmsh_d, pcbranch_d);

  assign rd1_d_final = (instr_d[25:21] != 0) ? ((instr_d[25:21] == writereg_m && regwrite_m) ? aluout_m : rd1_d) : 0;
  assign rd2_d_final = (instr_d[20:16] != 0) ? ((instr_d[20:16] == writereg_m && regwrite_m) ? aluout_m : rd2_d) : 0;

  always_ff @(posedge clk, posedge reset)
    if (reset || flush_e) begin
      regwrite_e <= 0; memtoreg_e <= 0; memwrite_e <= 0;
      alucontrol_e <= 0; alusrc_e <= 0; regdst_e <= 0;
      srca_e <= 0; writedata_e <= 0; rs_e <= 0; rt_e <= 0; rd_e <= 0; signimm_e <= 0;
    end else begin
      regwrite_e <= regwrite_d; memtoreg_e <= memtoreg_d; memwrite_e <= memwrite_d;
      alucontrol_e <= alucontrol_d; alusrc_e <= alusrc_d; regdst_e <= regdst_d;
      srca_e <= rd1_d; writedata_e <= rd2_d; rs_e <= instr_d[25:21]; 
      rt_e <= instr_d[20:16]; rd_e <= instr_d[15:11]; signimm_e <= signimm_d;
    end

  mux3 #(32) faemux(srca_e, result_w, aluout_m, forwarda_e, srca_e_final);
  mux3 #(32) fbemux(writedata_e, result_w, aluout_m, forwardb_e, writedata_e_final);
  
  mux2 #(32) srcbmux(writedata_e_final, signimm_e, alusrc_e, srcb_e);
  alu        alu(srca_e_final, srcb_e, alucontrol_e, aluout_e, zero_e);
  mux2 #(5)  wrmux(rt_e, rd_e, regdst_e, writereg_e);
  logic zero_e;

  always_ff @(posedge clk, posedge reset)
    if (reset) begin
      regwrite_m <= 0; memtoreg_m <= 0; memwrite_m <= 0;
      aluout_m <= 0; writedata_m <= 0; writereg_m <= 0;
    end else begin
      regwrite_m <= regwrite_e; memtoreg_m <= memtoreg_e; memwrite_m <= memwrite_e;
      aluout_m <= aluout_e; writedata_m <= writedata_e_final; writereg_m <= writereg_e;
    end

  always_ff @(posedge clk, posedge reset)
    if (reset) begin
      regwrite_w <= 0; memtoreg_w <= 0; readdata_w <= 0; aluout_w <= 0; writereg_w <= 0;
    end else begin
      regwrite_w <= regwrite_m; memtoreg_w <= memtoreg_m;
      readdata_w <= readdata_m; aluout_w <= aluout_m; writereg_w <= writereg_m;
    end

  mux2 #(32) resmux(aluout_w, readdata_w, memtoreg_w, result_w);
endmodule

module hazard(input  logic [4:0] rs_d, rt_d, rs_e, rt_e, writereg_e, writereg_m, writereg_w,
              input  logic regwrite_e, regwrite_m, regwrite_w, memtoreg_e, memtoreg_m, 
              input  logic branch_d, pcsrc_d,
              output logic [1:0] forwarda_e, forwardb_e,
              output logic stall_f, stall_d, flush_e);

  logic lwstall, branchstall;

  always_comb begin
    forwarda_e = 2'b00; forwardb_e = 2'b00;
    if (rs_e != 0)
      if (rs_e == writereg_m && regwrite_m)      forwarda_e = 2'b10;
      else if (rs_e == writereg_w && regwrite_w) forwarda_e = 2'b01;
    if (rt_e != 0)
      if (rt_e == writereg_m && regwrite_m)      forwardb_e = 2'b10;
      else if (rt_e == writereg_w && regwrite_w) forwardb_e = 2'b01;
  end

  assign lwstall = ((rs_d == rt_e) || (rt_d == rt_e)) && memtoreg_e;
  
  assign branchstall = branch_d & 
                       (regwrite_e & (writereg_e == rs_d | writereg_e == rt_d) |
                        memtoreg_m & (writereg_m == rs_d | writereg_m == rt_d));

  assign stall_f = lwstall | branchstall;
  assign stall_d = lwstall | branchstall;
  assign flush_e = lwstall | branchstall | pcsrc_d;
endmodule

module regfile(input  logic clk, we3, input  logic [4:0] ra1, ra2, wa3,
               input  logic [31:0] wd3, output logic [31:0] rd1, rd2);
  logic [31:0] rf[31:0];
  always_ff @(negedge clk) if (we3) rf[wa3] <= wd3;
  assign rd1 = (ra1 != 0) ? rf[ra1] : 0;
  assign rd2 = (ra2 != 0) ? rf[ra2] : 0;
endmodule

module alu(input  logic [31:0] a, b, input  logic [2:0] alucontrol,
           output logic [31:0] result, output logic zero);
  always_comb
    case(alucontrol)
      3'b010: result = a + b;
      3'b110: result = a - b;
      3'b000: result = a & b;
      3'b001: result = a | b;
      3'b111: result = a < b ? 32'd1 : 32'd0;
      default: result = 32'bx;
    endcase
  assign zero = (result == 32'b0);
endmodule

module dmem(input  logic clk, we, input  logic [31:0] a, wd, output logic [31:0] rd);
  logic [31:0] RAM[63:0];
  assign rd = RAM[a[31:2]];
  always_ff @(posedge clk) if (we) RAM[a[31:2]] <= wd;
endmodule

module imem(input  logic [5:0] a, output logic [31:0] rd);
  logic [31:0] RAM[63:0];
  initial $readmemh("mips_pipeline_memfile.dat", RAM);
  assign rd = RAM[a];
endmodule

module adder(input  logic [31:0] a, b, output logic [31:0] y);
  assign y = a + b;
endmodule

module sl2(input  logic [31:0] a, output logic [31:0] y);
  assign y = {a[29:0], 2'b00};
endmodule

module signext(input  logic [15:0] a, output logic [31:0] y);
  assign y = {{16{a[15]}}, a};
endmodule

module floprc #(parameter WIDTH = 8)
                (input  logic clk, reset, clear, en, input  logic [WIDTH-1:0] d, output logic [WIDTH-1:0] q);
  always_ff @(posedge clk, posedge reset)
    if (reset)      q <= 0;
    else if (clear) q <= 0;
    else if (en)    q <= d;
endmodule

module mux2 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, input  logic s, output logic [WIDTH-1:0] y);
  assign y = s ? d1 : d0;
endmodule

module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2, input  logic [1:0] s, output logic [WIDTH-1:0] y);
  assign y = (s == 2'b10) ? d2 : (s == 2'b01 ? d1 : d0);
endmodule