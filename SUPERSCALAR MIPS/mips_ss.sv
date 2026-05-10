module top(input  logic clk, reset,
           output logic [31:0] writedata, dataadr,
           output logic memwrite);

  logic [31:0] pc;
  logic [63:0] instr;
  logic [31:0] readdata;

  mips_ss mips(clk, reset, pc, instr, memwrite, dataadr, writedata, readdata);
  imem imem(pc, instr);
  dmem dmem(clk, memwrite, dataadr, writedata, readdata);
endmodule

module mips_ss(input  logic clk, reset,
               output logic [31:0] pc,
               input  logic [63:0] instr,
               output logic memwrite,
               output logic [31:0] aluout, writedata,
               input  logic [31:0] readdata);

  logic [2:0] alucontrol_da, alucontrol_db;
  logic memtoreg_da, memwrite_da, alusrc_da, regdst_da, regwrite_da, jump_da, branch_da;
  logic memtoreg_db, memwrite_db, alusrc_db, regdst_db, regwrite_db, jump_db, branch_db;
  logic [31:0] instr_da, instr_db;
  logic issue_b;

  controller ca(instr_da[31:26], instr_da[5:0], memtoreg_da, memwrite_da, alusrc_da,
                regdst_da, regwrite_da, jump_da, branch_da, alucontrol_da);
  controller cb(instr_db[31:26], instr_db[5:0], memtoreg_db, memwrite_db, alusrc_db,
                regdst_db, regwrite_db, jump_db, branch_db, alucontrol_db);

  datapath_ss dp(clk, reset, memtoreg_da, memwrite_da, alusrc_da, regdst_da, regwrite_da, 
                 jump_da, branch_da, alucontrol_da, memtoreg_db, memwrite_db, alusrc_db, 
                 regdst_db, regwrite_db, jump_db, branch_db, alucontrol_db,
                 pc, instr, memwrite, aluout, writedata, readdata, instr_da, instr_db, issue_b);
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

module datapath_ss(input  logic clk, reset,
                   input  logic memtoreg_da, memwrite_da, alusrc_da, regdst_da, regwrite_da, jump_da, branch_da,
                   input  logic [2:0] alucontrol_da,
                   input  logic memtoreg_db, memwrite_db, alusrc_db, regdst_db, regwrite_db, jump_db, branch_db,
                   input  logic [2:0] alucontrol_db,
                   output logic [31:0] pc_f,
                   input  logic [63:0] instr_f,
                   output logic memwrite_m,
                   output logic [31:0] aluout_m, writedata_m,
                   input  logic [31:0] readdata_m,
                   output logic [31:0] instr_da, instr_db,
                   output logic issue_b);

  logic [31:0] pcnext_f, pcplus4_f, pcplus8_f, pcbranch_d;
  logic [31:0] rd1a_d, rd2a_d, rd1b_d, rd2b_d;
  logic [31:0] signimma_d, signimmb_d;
  logic [31:0] aluouta_e, aluoutb_e, aluouta_m, aluoutb_m, result_wa, result_wb;
  logic [4:0]  wa3a, wa3b;
  logic        pcsrc_d, stall_f, stall_d, flush_e;

  hazard_ss h(instr_da[25:21], instr_da[20:16], instr_db[25:21], instr_db[20:16],
              regwrite_da, regwrite_db, memtoreg_da, memtoreg_db,
              wa3a, wa3b, issue_b, stall_f, stall_d, flush_e);

  assign pcsrc_d = branch_da & (rd1a_d == rd2a_d);
  assign pcplus4_f = pc_f + 4;
  assign pcplus8_f = pc_f + 8;
  assign pcnext_f = pcsrc_d ? pcbranch_d : (issue_b ? pcplus8_f : pcplus4_f);

  floprc #(32) pcreg(clk, reset, 1'b0, ~stall_f, pcnext_f, pc_f);
  
  floprc #(32) f_d_a(clk, reset, pcsrc_d, ~stall_d, instr_f[31:0], instr_da);
  floprc #(32) f_d_b(clk, reset, pcsrc_d | ~issue_b, ~stall_d, instr_f[63:32], instr_db);

  regfile_ss rf(clk, regwrite_wa, regwrite_wb, 
                instr_da[25:21], instr_da[20:16], instr_db[25:21], instr_db[20:16],
                wa3a_w, wa3b_w, result_wa, result_wb, 
                rd1a_d, rd2a_d, rd1b_d, rd2b_d);

  assign aluout_m = aluouta_m;
  assign result_wa = aluouta_m; 
  assign result_wb = aluoutb_m;

  alu alua(rd1a_d, rd2a_d, alucontrol_da, aluouta_e, zeroa);
  alu alub(rd1b_d, rd2b_d, alucontrol_db, aluoutb_e, zerob);

  always_ff @(posedge clk) begin
    aluouta_m <= aluouta_e;
    aluoutb_m <= aluoutb_e;
    regwrite_wa <= regwrite_da;
    regwrite_wb <= regwrite_db & issue_b;
    wa3a_w <= regdst_da ? instr_da[15:11] : instr_da[20:16];
    wa3b_w <= regdst_db ? instr_db[15:11] : instr_db[20:16];
  end

  logic regwrite_wa, regwrite_wb;
  logic [4:0] wa3a_w, wa3b_w;
  logic zeroa, zerob;
endmodule

module hazard_ss(input  logic [4:0] rs1a, rs2a, rs1b, rs2b,
                 input  logic regwrite_a, regwrite_b, memtoreg_a, memtoreg_b,
                 input  logic [4:0] wa3a, wa3b,
                 output logic issue_b, stall_f, stall_d, flush_e);

  always_comb begin
    issue_b = 1'b1;
    if (regwrite_a && (wa3a != 0)) begin
      if (wa3a == rs1b || wa3a == rs2b) issue_b = 1'b0;
    end
    if (memtoreg_a || memtoreg_b) issue_b = 1'b0;
  end

  assign stall_f = 1'b0;
  assign stall_d = 1'b0;
  assign flush_e = 1'b0;
endmodule

module regfile_ss(input  logic clk, we_a, we_b,
                  input  logic [4:0] ra1a, ra2a, ra1b, ra2b, wa_a, wa_b,
                  input  logic [31:0] wd_a, wd_b,
                  output logic [31:0] rd1a, rd2a, rd1b, rd2b);
  logic [31:0] rf[31:0];
  always_ff @(negedge clk) begin
    if (we_a) rf[wa_a] <= wd_a;
    if (we_b) rf[wa_b] <= wd_b;
  end
  assign rd1a = (ra1a != 0) ? rf[ra1a] : 0;
  assign rd2a = (ra2a != 0) ? rf[ra2a] : 0;
  assign rd1b = (ra1b != 0) ? rf[ra1b] : 0;
  assign rd2b = (ra2b != 0) ? rf[ra2b] : 0;
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

module imem(input  logic [31:0] a, output logic [63:0] rd);
  logic [31:0] RAM[63:0];
  initial $readmemh("mips_ss_memfile.dat", RAM); 
  assign rd = {RAM[a[7:2] + 1], RAM[a[7:2]]};
endmodule

module dmem(input  logic clk, we, input  logic [31:0] a, wd, output logic [31:0] rd);
  logic [31:0] RAM[63:0];
  assign rd = RAM[a[31:2]];
  always_ff @(posedge clk) if (we) RAM[a[31:2]] <= wd;
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