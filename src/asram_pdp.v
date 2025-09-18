module asram_pdp#(
    parameter   DWID = 8,
                DDEPTH = 64,
                AWID = $clog2(DDEPTH)
)(
    input [AWID-1:0]raddr,waddr,
    input we,clk,
    input [DWID-1:0]wdata,
    output [DWID-1:0]rdata
);



reg [DWID-1:0]memory[DDEPTH-1:0] /*synthesis ram_style = dram*/;

assign rdata = memory[raddr];

always@(posedge clk)
if(we)
    memory[waddr]<=wdata;

endmodule 