
//
// module: core_pipe_exec_mdu
//
//  Core multiply divide unit
//
module core_pipe_exec_mdu (

input  wire         g_clk       , // Clock
input  wire         g_resetn    , // Active low synchronous reset.

input  wire         flush       , // Flush and stop any execution.

input  wire         valid       , // Inputs are valid.
input  wire         op_word     , // word-wise operation on 32-bit data.
input  wire         op_mul      , //
input  wire         op_mulh     , //
input  wire         op_mulhu    , //
input  wire         op_mulhsu   , //
input  wire         op_div      , //
input  wire         op_divu     , //
input  wire         op_rem      , //
input  wire         op_remu     , //
input  wire [XL: 0] rs1         , // Source register 1
input  wire [XL: 0] rs2         , // Source register 2

output wire         ready       , // Finished computing
output wire [XL: 0] rd            // Result

);

`include "core_common.svh"

localparam MLEN = XLEN*2;
localparam MW   = MLEN-1;

//
// Result signals.
// ------------------------------------------------------------

wire [XL:0] result_mul  ;
wire [XL:0] result_div  ;

wire        any_div     = op_div || op_divu || op_rem   || op_remu  ;
wire        any_mul     = op_mul || op_mulh || op_mulhu || op_mulhsu;

assign      rd          = any_mul ? result_mul  : result_div;

assign      ready       = any_mul ? mul_done    : 1'b0      ;

//
// Argument storage
// ------------------------------------------------------------

reg [XL:0] s_rs1;
reg [XL:0] s_rs2;

reg [XL:0] n_rs1_mul;
reg [XL:0] n_rs2_mul;

always @(posedge g_clk) begin
    if(!g_resetn || flush) begin
        s_rs1 <= {XLEN{1'b0}};
        s_rs2 <= {XLEN{1'b0}};
    end else if(mul_start) begin
        s_rs1 <= rs1;
        s_rs2 <= rs2;
    end else if(mul_run) begin
        s_rs1 <= n_rs1_mul;
        s_rs2 <= n_rs2_mul;
    end
end

//
// Multiplier
// ------------------------------------------------------------

parameter MUL_UNROLL = 4;
localparam MUL_END   = (MUL_UNROLL & 'd1) ==0 ? 0 : 1;

wire        mul_start = valid && any_mul && !mul_run && !mul_done;
wire        mul_hi    = op_mulh || op_mulhu || op_mulhsu;

assign      result_mul= 
              op_word ? {{32{mul_state[XL]}}, mul_state[XL:32]} :
    mul_hi            ? mul_state[MW:64]                        :
                        mul_state[XL: 0]                        ;

reg  [MW:0]   mul_state;
reg  [MW:0] n_mul_state;

reg         mul_run ;
reg         mul_done;
reg  [ 6:0] mul_ctr ;
reg  [XL:0] to_add  ;
reg  [XLEN:0] mul_add_l;
reg  [XLEN:0] mul_add_r;
reg  [XLEN:0] mul_sum;

reg         mul_l_sign;
reg         mul_r_sign;
reg         sub_last  ;

wire        lhs_signed = op_mulh;
wire        rhs_signed = op_mulh;

integer i;
always @(*) begin
    
    n_mul_state = mul_state;
    sub_last    = 1'b0;

    for(i = 0; i < MUL_UNROLL; i = i + 1) begin
        sub_last    = i == (MUL_UNROLL - 1) &&
                      mul_ctr == MUL_UNROLL &&
                      rhs_signed && s_rs2[MUL_UNROLL-1];
        to_add      = s_rs2[i] ? s_rs1 : 64'b0;
        mul_l_sign  = lhs_signed ? n_mul_state[MW] : 1'b0;
        mul_r_sign  = rhs_signed ? to_add[XL]      : 1'b0;
        mul_add_l   = {mul_l_sign,n_mul_state[MW:XLEN]};
        mul_add_r   = {mul_r_sign,to_add              };
        if(sub_last) begin
            mul_add_r = ~mul_add_r;
        end
        mul_sum     = mul_add_l + mul_add_r + {64'b0,sub_last};
        n_mul_state = {mul_sum, n_mul_state[XL:1]};
        n_rs1_mul   = s_rs1;
        n_rs2_mul   = s_rs2 >> MUL_UNROLL;
    end
end

always @(posedge g_clk) begin
    if (!g_resetn || flush) begin
        mul_run     <= 1'b0;
        mul_done    <= 1'b0;
        mul_ctr     <= 'd0;
        mul_state   <= {MLEN{1'b0}};
    end else if (mul_start) begin
        mul_run     <= 1'b1;
        mul_done    <= 1'b0;
        mul_state   <= 'b0;
        mul_ctr     <= op_word ? 'd32 : 'd64;
    end else if(mul_run) begin
        if(mul_ctr == MUL_END) begin
            mul_done    <= 1'b1;
            mul_run     <= 1'b0;
            if(MUL_UNROLL == 1) begin
                mul_state   <= n_mul_state;
            end
        end else begin
            mul_ctr     <= mul_ctr - MUL_UNROLL;
            mul_state   <= n_mul_state;
        end
    end
end

endmodule

