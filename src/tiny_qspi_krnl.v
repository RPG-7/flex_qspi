module tiny_qspi_krnl(
    input clk,rst_i,
    input cpol, cpha,
    //Operation interface
    input [31:0] data_input,
    input [4:0] cycle_cnt,
    input [1:0] mode_sel,
    input [7:0] baud_reg,
    output reg load_flag,
    input op_read,
    input op_valid,
    output reg op_end,
    output reg [31:0] data_out,
	output reg dataout_valid,

    //QSPI interface
     
   input        [3:0]   QSPI_QIN,
   output reg   [3:0]   QSPI_QOUT,
   output reg   [3:0]   QSPI_QOE,
   output	            SCLK//,
   //output reg [DEVSEL_NUM-1:0]MCS
);

    reg [4:0] bit_cnt,bit_cnt_next;
	localparam
	IDLE = 0,
	PHASE1 = 1,
	PHASE2 = 2;
    reg sclk_reg;
    reg curr_rd,sf;
	reg [7:0]baud_cnt, baud_cnt_next;
   	reg [1:0] spi_seq, spi_seq_next;
    reg [1:0] mode_sel_latch;
    reg [31:0]data_sft32,data_sft32_next;

   	always @(posedge clk or posedge rst_i)
	if (rst_i)
		spi_seq <= IDLE;
	else
		spi_seq <= spi_seq_next;

   	always @(posedge clk)
    begin
		baud_cnt <= baud_cnt_next;
		bit_cnt <= bit_cnt_next;
    end

   always @(op_valid or bit_cnt or baud_cnt or baud_reg or cpha or cpol or spi_seq)
     begin
		sclk_reg = cpol;
		baud_cnt_next = (baud_reg==0)?1:baud_reg; 
		bit_cnt_next = bit_cnt;
		load_flag = 1'b0;
		sf = 1'b0;
		case (spi_seq)
		IDLE:
			begin
				if (op_valid)
				begin
					bit_cnt_next = (cycle_cnt>>mode_sel);
					load_flag = 1'b1;
					spi_seq_next = PHASE2;
				end
				else
					spi_seq_next = IDLE;
			end
		PHASE2:
			begin
				sclk_reg = (cpol ^ cpha);
				if (baud_cnt == 0)
					spi_seq_next = PHASE1;
				else
				begin
					baud_cnt_next = baud_cnt - 1;
					spi_seq_next = PHASE2;
				end
			end
		PHASE1:
			begin
			sclk_reg = ~(cpol ^ cpha);
			if (baud_cnt == 0)
				begin
					bit_cnt_next = bit_cnt -1;
					sf = 1'b1;
					if (bit_cnt == 0)
					begin
						load_flag = 1'b1;
						if (op_valid)
						begin
							bit_cnt_next = cycle_cnt;
							spi_seq_next = PHASE2;
						end
						else
							spi_seq_next = IDLE;
					end
					else
						spi_seq_next = PHASE2;
				end
			else
				begin
					baud_cnt_next = baud_cnt - 1;
					spi_seq_next = PHASE1;
				end
			end
		default:spi_seq_next = IDLE;
		endcase
     end

//DATA WRITE BLOCK
    always @(posedge clk)
    begin

		if (load_flag)   // Now operation is read
			curr_rd <= op_read;
		else
			curr_rd <= curr_rd;

		if (load_flag)   // shift reg
			mode_sel_latch <= mode_sel;

		if (load_flag)   // shift reg
			data_sft32 <= data_input;
		else if (sf)
			data_sft32 <= data_sft32_next;
		else
			data_sft32 <= data_sft32;

    end // always @ (posedge PCLK)

    always@(*)
    begin
        case(mode_sel_latch)
            2'b00: data_sft32_next={data_sft32[30:0],QSPI_QIN[1]};
            2'b01: data_sft32_next={data_sft32[29:0],QSPI_QIN[1:0]};
            2'b10,
            2'b11: data_sft32_next={data_sft32[27:0],QSPI_QIN};
        endcase
    end
    always@(*)
    begin
        case({(curr_rd|spi_seq == IDLE),mode_sel_latch})
            3'b000: QSPI_QOE=4'b0001;
            3'b001: QSPI_QOE=4'b0011;
            3'b010,
            3'b011: QSPI_QOE=4'b1111;
            3'b100, 
            3'b101, 
            3'b110,
            3'b111: QSPI_QOE=4'b0000;
        endcase
    end

    always@(*)
    begin
        case(mode_sel_latch)
            2'b00: QSPI_QOUT={3'b111,data_sft32[31]};
            2'b01: QSPI_QOUT={2'b11,data_sft32[31:30]};
            2'b10,
            2'b11: QSPI_QOUT=data_sft32[31:28];
        endcase
    end
    assign SCLK = sclk_reg;
    //assign data_out = (spi_seq == IDLE) ? data_sft32 : data_sft32_next;
    always@(posedge clk or posedge rst_i)
    if(rst_i)
        op_end<=1'b1;
    else if(spi_seq_next == IDLE )
        op_end<=1'b1;
    else
        op_end<=1'b0;
        
    
    always@(posedge clk or posedge rst_i)
    if(rst_i)
        dataout_valid<=1'b0;
    else 
        dataout_valid<=load_flag && (!op_valid);
		
    always@(posedge clk)
    if(load_flag && (!op_valid) )
        data_out<=data_sft32_next;
    else
        data_out<=data_out;    
	//assign op_end = (spi_seq == IDLE);
	//assign op_rdy = ~buf_flg;
endmodule
