//DISRAM Syncronous FIFO 

module SyncFIFO_SPI
#(
    parameter   DWID = 8,
                DDEPTH = 64
)
(
    input clk,rst,
    input ren,wen,
    input fifoen,
    input [DWID-1:0]wdata,
    output[DWID-1:0]rdata,
    output reg full,empty,halfway,
    output about_empty,about_full
);
localparam CNTWID = $clog2(DDEPTH);

reg [CNTWID-1:0] wptr;
reg [CNTWID-1:0] rptr;
wire [CNTWID-1:0] wptr_next,rptr_next;
reg [DWID-1:0]wr_buf,rsav;
wire [DWID-1:0]ram_rdata;
wire full_cmp,empty_cmp;
wire wen_internal,ren_internal;

assign wen_internal=wen&fifoen;
assign ren_internal=ren&fifoen;
assign full_cmp=(rptr_next=={!wptr_next[CNTWID-1],wptr_next[CNTWID-2:0]});
assign empty_cmp=(wptr_next==rptr_next);
assign wptr_next=(full)?wptr:wptr+wen_internal;
assign rptr_next=(empty)?rptr:rptr+ren_internal;
assign about_empty=(fifoen)?empty_cmp:empty;
assign rdata=(fifoen)?
                    (ren_internal)?ram_rdata:rsav:
                    wr_buf;
always@(posedge clk or posedge rst)//PTRs
begin
    if(rst) 
    begin
        wptr<=0;
        rptr<=0;
    end
    else
    begin
        if(wen_internal) 
            wptr<=wptr_next;
        else 
            wptr<=wptr;
        if(ren_internal)
            rptr<=rptr_next;
        else
            rptr<=rptr;
    end
end
/*
always@(posedge clk)//data
begin
    if(fifoen)
    begin
        if(wen) memory[wptr]<=wdata;
    end
    //else if(wen&empty)wr_buf<=wdata;
end
*/
asram_pdp #(
    .DWID(DWID),
    .DDEPTH(DDEPTH)
)ram_core(
    .raddr(rptr),
    .waddr(wptr),
    .we(fifoen & wen),
    .clk(clk),
    .wdata(wdata),
    .rdata(ram_rdata)
);
always@(posedge clk or posedge rst)//data
if(rst)
    wr_buf<=0;
else if(wen&empty)wr_buf<=wdata;

always@(posedge clk or posedge rst)//data
if(rst)
    rsav<=0;
else if(ren_internal && fifoen )rsav<=rdata;

always@(posedge clk or posedge rst)//Full & Empty
begin
    if(rst) 
    begin
        full<=0;
        empty<=1'b1;
    end
    else if(fifoen)
    begin
        //if(wen) 
            full<=full_cmp;
        //if(ren)
            empty<=empty_cmp;
    end
    else
    begin
        if(wen & !full)
        begin
            full<=1'b1;
            empty<=1'b0;
        end
        else if(ren & !empty)
        begin
            full<=1'b0;
            empty<=1'b1;
        end
        else
            begin
                full<=full;
                empty<=empty;
            end
    end
end

always@(posedge clk or posedge rst)//Halfway (pulse)
begin
    if(rst) 
        halfway<=0;
    else
        halfway<=(wptr[CNTWID-1] ^ rptr[CNTWID-1]);
end

endmodule
