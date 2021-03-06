
//
// Module: core_pipe_fetch_buffer
//
//  Fetch data buffer. Accepts between 0, 2, 4, 6 or 8 bytes per cycle, drains
//  0, 2 or 4 bytes per cycle.
//
module core_pipe_fetch_buffer (

input  wire         g_clk       , // Global clock
input  wire         g_resetn    , // Global active low sync reset.

input  wire         flush       , // Flush data from the buffer.
output reg  [ 4:0]  depth       , // How many bytes are in the buffer?
output wire [ 4:0]  n_depth     , // Buffer depth for next cycle.

input  wire         fill_en     , // Buffer fill enable.
input  wire [63:0]  data_in     , // Data in
input  wire         error_in    , // Tag with error?
input  wire         fill_2      , // Load top 2 bytes of input data.
input  wire         fill_4      , // Load top 4 bytes of input data.
input  wire         fill_6      , // Load top 6 bytes of input data.
input  wire         fill_8      , // Load top 8 bytes of input data.

output wire [FD_IBUF_R:0]  data_out    , // Data out of the buffer.
output wire [ FD_ERR_R:0]  error_out   , // Is data tagged with fetch error?
input  wire         drain_2     , // Drain 2 bytes of data.
input  wire         drain_4       // Drain 4 bytes of data.

);

`include "core_common.svh"

localparam BUFFER_DEPTH_BITS    = 128;
localparam BR                   = BUFFER_DEPTH_BITS - 1;
localparam ER                   = (BUFFER_DEPTH_BITS / 16) - 1;
localparam MAX_DEPTH            = BUFFER_DEPTH_BITS / 8;

reg [BR:0]  d_buffer;   // Data bits storage.
reg [ER:0]  e_buffer;   // Error buts storage.

assign      data_out = d_buffer[FD_IBUF_R:0];
assign      error_out= e_buffer[ FD_ERR_R:0];

//
// Buffer Depth Tracking
// ------------------------------------------------------------------

wire [3:0] bd_add = {
    fill_8              ,
    fill_4 || fill_6    ,
    fill_2 || fill_6    ,
    1'b0
};

wire [3:0] bd_sub = {
    1'b0                ,
    drain_4             ,
    drain_2             ,
    1'b0
};

assign n_depth = flush ? 0 : depth + bd_add - bd_sub;

wire [4:0] shf_up = depth - bd_sub;

always @(posedge g_clk) begin
    if(!g_resetn || flush) begin
        depth <= 0;
    end else if(update_buffer) begin
        depth <= n_depth;
    end
end


//
// Buffer Data Tracking
// ------------------------------------------------------------------

// Does the buffer need updating this cycle?
wire update_buffer = 
    (fill_en && (fill_2  || fill_4  || fill_6  || fill_8))  ||
    drain_2 || drain_4 ;

// Which bytes of the input data should be selected?
wire [BR:0] n_d_buffer_in_pre_shift     =
    fill_2  ? {32'b0, 80'b0, data_in[63:48]} :
    fill_4  ? {32'b0, 64'b0, data_in[63:32]} :
    fill_6  ? {32'b0, 48'b0, data_in[63:16]} :
    fill_8  ? {32'b0, 32'b0, data_in[63: 0]} :
                                         0   ;

wire [ER:0] n_e_buffer_in_pre_shift     =
    fill_2  ? { 7'b0, {1{error_in}}}    :
    fill_4  ? { 6'b0, {2{error_in}}}    :
    fill_6  ? { 5'b0, {3{error_in}}}    :
    fill_8  ? { 4'b0, {4{error_in}}}    :
                                0       ;

// Shift the bytes-to-load up to their new position in the buffer register.
wire [BR:0] n_d_buffer_in_shift_up    = n_d_buffer_in_pre_shift << (8*shf_up);

wire [ER:0] n_e_buffer_in_shift_up    = n_e_buffer_in_pre_shift << (  shf_up);

// Shift current buffer data down by the number of bits being drained.
wire [BR:0] n_d_buffer_out_shift_down =
    drain_2  ? {16'b0, d_buffer[BR:16]} :
    drain_4  ? {32'b0, d_buffer[BR:32]} :
               {       d_buffer       } ;

wire [ER:0] n_e_buffer_out_shift_down =
    drain_2  ? { 1'b0, e_buffer[ER: 1]} :
    drain_4  ? { 2'b0, e_buffer[ER: 2]} :
               {       e_buffer       } ;

// Or together the shifted out and shifted in data
wire [BR:0] n_d_buffer = n_d_buffer_in_shift_up | n_d_buffer_out_shift_down;

wire [ER:0] n_e_buffer = n_e_buffer_in_shift_up | n_e_buffer_out_shift_down;

always @(posedge g_clk) begin
    if(!g_resetn) begin
        d_buffer <= 0;
        e_buffer <= 0;
    end else if (flush) begin
        d_buffer <= 0;
        e_buffer <= 0;
    end else if(update_buffer) begin
        d_buffer <= n_d_buffer;
        e_buffer <= n_e_buffer;
    end
end

//
// Designer Assertions
// ------------------------------------------------------------

`ifdef DESIGNER_ASSERTION_CORE_FETCH_BUFFER

always @(posedge g_clk) if(g_resetn) begin

    // Fetch buffer can store a maximum of 16 bytes.
    assert(depth <= MAX_DEPTH);

end

`endif

`ifdef DESIGNER_ASSUMPTION_CORE_FETCH_BUFFER
always @(posedge g_clk) if(g_resetn) begin
    // This assumption is used for proofs by induction to make sure that
    // the fetch buffer starts in a valid state.
    // Fetch buffer can store a maximum of 16 bytes.
    assume(depth <= MAX_DEPTH);
end
`endif

endmodule

