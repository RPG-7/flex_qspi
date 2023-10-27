//////////////////////////////////////////////////////////////////////
////                                                              ////
////  tiny_spi.v                                                  ////
////                                                              ////
////  This file is part of the TINY SPI IP core project           ////
////  http://www.opencores.org/projects/tiny_spi/                 ////
////                                                              ////
////  Author(s):                                                  ////
////      - Thomas Chou <thomas@wytron.com.tw>                    ////
////                                                              ////
////  All additional information is avaliable in the README       ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2010 Authors                                   ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
/*

This is an 8 bits SPI master controller. It features optional 
programmable baud rate and SPI mode selection. Altera SPI doesn't
support programmable rate which is needed for MMC SPI, nor does
Xilinx SPI.

It is small. It combines transmit and receive buffer and remove unused 
functions. It takes only 36 LEs for SPI flash controller, or 53 LEs for 
MMC SPI controller in an Altera CycoloneIII SOPC project. While Altera 
SPI takes around 143 LEs. OpenCores SPI takes 857 LEs and simple SPI 
takes 171 LEs.

It doesn't generate SS_n signal. Please use gpio core for SS_n, which
costs 3- LEs per pin. The gpio number is used for the cs number in
u-boot and linux drivers.


Parameters:

BAUD_WIDTH: bits width of programmable divider
  sclk = clk / ((baud_reg + 1) * 2)
  if BAUD_DIV is not zero, BAUD_WIDTH is ignored.

BAUD_DIV: fixed divider, must be even
  sclk = clk / BAUD_DIV

SPI_MODE: value 0-3 fixed mode CPOL,CPHA
          otherwise (eg, 4) programmable mode in control reg[1:0]

Registers map:

base+0 RW {TXR_EN,TXE_EN,spi mode,baud divider}
		baud divider (optional)
		[9:8] spi mode
		irq enable
          [11] TXR_EN transfer ready irq enable
       	  [10] TXE_EN transter end irq enable
base+4  R buffer register
        W buffer register
        [15] read mode enable
        [14] non-aligned send enable
        [10:8] non-aligned send bit (1~8)
base+8  R status
	  [1] tx_rdy transfer ready
          [0] tx_end transter end
base+12 RW Devsel


Program flow:

There is an 8-bits shift register and buffer register.

1. after reset or idle, tx_rdy=1, tx_end=1
2. first byte written to buffer register, tx_rdy=0, tx_end=1
3. buffer register swabbed with shift register, tx_rdy=1, tx_end=0   
   shift register has the first byte and starts shifting
   buffer register has (useless) old byte of shift register
4. second byte written to buffer register, tx_rdy=0, tx_end=0
5. first byte shifted,
   buffer register swabbed with shift register, tx_rdy=1, tx_end=0
   shift register has the second byte and starts shifting
   buffer register has the first received byte from shift register
6. third byte written to buffer register, tx_rdy=0, tx_end=0
7. repeat like 5.

9. last byte written to buffer register, tx_rdy=0, tx_end=0
10. last-1 byte shifted,
   buffer register swabbed with shift register, tx_rdy=1, tx_end=0
   shift register has the last byte and starts shifting
   buffer register has the last-1 received byte from shift register
11. last byte shifted, no more to write, tx_rdy=1, tx_end=1
   shift register has the last received byte
   
Interrupt usage:
Interrupt is controlled with irq enable reg.

For performace issue, at sclk > 200KHz, interrupt should not be used and 
polling will get better result. In this case, interrupt can be 
disconnected in SOPC builder to save 2 LEs. A 100MHz Nios2 is able to
serve 25 MHz sclk using polling.

This core uses zero-wait bus access. Clock crossing bridges between
CPU and this core might reduce performance.

*/
//////////////////////////////////////////////////////////////////////

module tiny_spi_apb(
   // system
   input	  PRESETn,
   input	  PCLK,
   // memory mapped
   input	  PENABLE,
   input	  PWRITE,
   output [31:0]  PRDATA,
   input [31:0]   PWDATA,
   input [4:0]	  PADDR,
   input 	  PSEL, 
   output 	  PREADY, 
   output	  int_o,

   // spi
   output	  MOSI_oe, //for Tri-wire SPI mode
   output	  MOSI,
   output	  SCLK,
   input	  MISO,
   output reg [DEVSEL_NUM-1:0]MCS
   );

	localparam BAUD_WIDTH = 8;
	parameter SPI_MODE = 0;
	parameter BC_WIDTH = 3;
	parameter DEVSEL_NUM = 1;
	localparam DIV_WIDTH = BAUD_WIDTH;

	wire rst_i = !PRESETn;
	wire [2:0]adr_i = PADDR[4:2];
	reg [7:0]	  sft8, buf_reg8;
	wire [7:0]	  sr8_sf;
	reg [BC_WIDTH - 1:0]		bit_cnt, bit_cnt_next;
	reg [DIV_WIDTH - 1:0]	baud_reg;
	reg [DIV_WIDTH - 1:0]	baud_cnt, baud_cnt_next;
	reg op_read,curr_rd;
    reg [2:0] exec_bitnum,curr_bitnum;
	wire		  misod;
	wire		  cstb, data_wsel, baud_wsel, istb, dstb;
	reg		  sclk_reg;
	reg		  sf, load_flag;
	reg		  buf_flg;   // buffer flag
	reg		  txren, txeen;
	wire 	  tx_rdy, tx_end;
	wire		  cpol, cpha;
	reg		  cpolr, cphar;
	wire 	  wr;

	assign PREADY = 1'b1; // zero wait
	assign wr = PENABLE & PSEL & PWRITE & PREADY;
	assign data_wsel = wr & (adr_i == 1);
	assign istb = wr & (adr_i == 0);
	assign cstb = wr & (adr_i == 0);
	assign baud_wsel = wr & (adr_i == 0);
	assign dstb = wr & (adr_i == 3);
	assign sr8_sf = { sft8[6:0],misod };
	assign PRDATA =
		      ({16'b0,4'b0,txren, txeen,cpolr,cphar,baud_reg} & {32{(adr_i == 0)}})
		    | (buf_reg8 & {32{(adr_i == 1)}})
		    | ({ tx_rdy, tx_end } & {32{(adr_i == 2)}})
			| ( MCS & {32{(adr_i == 3)}})
		    ;

	parameter
	IDLE = 0,
	PHASE1 = 1,
	PHASE2 = 2;

   	reg [1:0] spi_seq, spi_seq_next;
   	always @(posedge PCLK or posedge rst_i)
	if (rst_i)
		spi_seq <= IDLE;
	else
		spi_seq <= spi_seq_next;

   	always @(posedge PCLK)
    begin
		baud_cnt <= baud_cnt_next;
		bit_cnt <= bit_cnt_next;
    end
/*buf_flg or bit_cnt or baud_cnt or baud_reg or cpha or cpol or spi_seq*/
   always @(*)
     begin
		sclk_reg = cpol;
		baud_cnt_next = (baud_reg[DIV_WIDTH - 1:1]==0)?1:baud_reg[DIV_WIDTH - 1:1];//BAUD_DIV ? (BAUD_DIV / 2 - 1) : 
		bit_cnt_next = bit_cnt;
		load_flag = 1'b0;
		sf = 1'b0;

		case (spi_seq)
		IDLE:
			begin
				if (buf_flg)
				begin
					bit_cnt_next = curr_bitnum;
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
						if (buf_flg)
						begin
							bit_cnt_next = exec_bitnum;
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
   always @(posedge PCLK)
     begin
		if (cstb) // control reg
			{ cpolr, cphar } <= PWDATA[9:8];
		else
			{ cpolr, cphar } <= { cpolr, cphar };

		if (istb) // irq enable reg
			{ txren, txeen } <= PWDATA[11:10];
		else
			{ txren, txeen } <= { txren, txeen };

		if (baud_wsel) // baud reg
			baud_reg <= PWDATA;
		else
			baud_reg <= baud_reg;

		if (load_flag)   // Now operation is read
			curr_rd <= op_read;
		else
			curr_rd <= curr_rd;

		if (load_flag)   // Now running bit numbers
			curr_bitnum <= exec_bitnum;
		else
			curr_bitnum <= curr_bitnum;
            
		if (load_flag)   // shift reg
			sft8 <= buf_reg8;
		else if (sf)
			sft8 <= sr8_sf;
		else
			sft8 <= sft8;

		if (data_wsel) // buffer reg
			buf_reg8 <= PWDATA;
		else if (load_flag)
			buf_reg8 <= (spi_seq == IDLE) ? sft8 : sr8_sf;
		else
			buf_reg8 <= buf_reg8;
		
		if (data_wsel) // R/W flag reg
			op_read <= PWDATA[15];
		else
			op_read <= op_read;
      
		if (data_wsel) // R/W flag reg
			exec_bitnum <= PWDATA[14]?PWDATA[10:8]:3'h7;
		else
			exec_bitnum <= exec_bitnum;
     end // always @ (posedge PCLK)

   always @(posedge PCLK or posedge rst_i)
     begin
		if (rst_i)
			buf_flg <= 1'b0;
		else if (data_wsel)
			buf_flg <= 1'b1;
		else if (load_flag)
			buf_flg <= 1'b0;
		else
			buf_flg <= buf_flg;
     end
	always @(posedge PCLK or posedge rst_i)
    begin
		if (rst_i)
			MCS <= {DEVSEL_NUM{1'b1}};
		else if (dstb)
			MCS <= PWDATA;
		else
			MCS <= MCS;
    end
	assign { cpol, cpha } = ((SPI_MODE >= 0) & (SPI_MODE < 4)) ?
							SPI_MODE : { cpolr, cphar };
	assign tx_end = (spi_seq == IDLE);
	assign tx_rdy = ~buf_flg;
	assign int_o = (tx_rdy & txren) | (tx_end & txeen);
	assign SCLK = sclk_reg;
	assign MOSI = sft8[7];
	assign MOSI_oe=(!curr_rd) & (spi_seq != IDLE);
	assign misod = MISO;

endmodule
