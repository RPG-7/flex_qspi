`define INTR_PEDGE  2'b00
`define INTR_NEDGE  2'b01
`define INTR_HIGH   2'b10
`define INTR_LOW    2'b11
module intr_mgmt#(
    parameter   INTR_NUM=8,
                INTR_CFG={INTR_NUM{`INTR_PEDGE}}
)(
    input clk,
    input [INTR_NUM-1:0]intr_src,
    input intr_clr,
    input [INTR_NUM-1:0]intr_clr_sel,
    output reg[INTR_NUM-1:0]intr_sig
);
reg [INTR_NUM-1:0]intr_pend,intr_pulse;
genvar j;
always@(posedge clk)
    intr_sig<=(intr_clr)?(intr_sig & (~intr_clr_sel)):(intr_sig | intr_pulse);
generate //GPIO Int type block
for (j=0 ;j<INTR_NUM ;j=j+1 ) //if(GPIO_INTENABLE)
begin:GPIOINT_BLK
    always@(posedge clk)
    begin
        if(INTR_CFG[(j+1)*2-1]==1'b0)
            intr_pend[j]<=intr_src[j];
        case(INTR_CFG[(j+1)*2-1:(j*2)])
            `INTR_PEDGE:intr_pulse[j]<=({intr_pend[j],intr_src[j]}==2'b01);
            `INTR_NEDGE:intr_pulse[j]<=({intr_pend[j],intr_src[j]}==2'b10);
            `INTR_HIGH :intr_pulse[j]<=intr_src[j];
            `INTR_LOW  :intr_pulse[j]<=!intr_src[j];
            default:intr_pulse[j]<=1'b0;
        endcase
    end
end
endgenerate


endmodule
