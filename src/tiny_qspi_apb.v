//////////////////////////////////////////////////////////////////////
////                                                              ////
////  tiny_qspi_apb.v                                             ////
////                                                              ////
////  This file is part of the TINY SPI IP core project           ////
////  http://www.opencores.org/projects/tiny_spi/                 ////
////                                                              ////
////  Author(s):                                                  ////
////      - Thomas Chou <thomas@wytron.com.tw>                    ////
////      - Xiaoyu Hong <xiaoyu.hong@anlogic.com>                 ////
////                                                              ////
////  All additional information is avaliable in the README       ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2024 Authors                                   ////
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

This is an 32 bits QSPI master controller. It features 
programmable baud rate and SPI mode selection. Altera SPI doesn't
support programmable rate which is needed for MMC SPI, nor does
Xilinx SPI.

//// It is small. It combines transmit and receive buffer and remove unused 
//// functions. It takes only 36 LEs for SPI flash controller, or 53 LEs for 
//// MMC SPI controller in an Altera CycoloneIII SOPC project. While Altera 
//// SPI takes around 143 LEs. OpenCores SPI takes 857 LEs and simple SPI 
//// takes 171 LEs.

//// It doesn't generate SS_n signal. Please use gpio core for SS_n, which
//// costs 3- LEs per pin. The gpio number is used for the cs number in
//// u-boot and linux drivers.


Parameters:


SPI_MODE: value 0-3 fixed mode CPOL,CPHA
          otherwise (eg, 4) programmable mode in control reg[1:0]

Registers map:

base+0 RW ASPI Ctrl reg
		[7:0] baud divider (optional)
		[9:8] spi mode
		irq enable
       	  [10] TXE_EN transter end irq enable
          [11] TXR_EN transfer ready irq enable
		  [12] TXBHWM_EN Tx Buffer high watermark intr
		  [13] RXBLWM_EN Rx Buffer low watermark intr
		  [14] TXBE_EN Tx Buffer empty intr
		  [15] RXBV_EN Rx Buffer valid intr
		  [16] CTO_EN Command Timeout
		  [17] CTF_EN Command finish (command FIFO empty)
		  [18] CRF_EN Command Rx Buffer Full
		[29] MSB First (no byte flip)
		[30] mode 0 = conventional 1 = command stream mode 
		[31] version, always 1

base+4  Command mode:
		R [31:0] Rx FIFO
        W [31:0] Tx FIFO
		Normal mode:
		R [15:0] read Buffer register
		W [15:0] write Buffer register
		////[27:26] Access bitwidth (now 32bit only in current version)
		[19:16] Unaligned access cycles
		[29:28] Q/D/SPI select (only for normal mode)
		00: SPI mode
		01: DPI mode
		10: QPI mode
		11: Reserved
		[30] non-aligned read enable (less than 16 cycles)
		[31] Read mode

base+8  R status event pending register
        [0] tx_end transter end (direct)
	  	[1] tx_rdy transfer ready (pending reg)
		[2] TXBHWM_EN Tx Buffer low watermark event
		[3] RXBLWM_EN Rx Buffer high watermark event
		[4] TXBE_EN Tx Buffer empty event
		[5] RXBV_EN Rx Buffer valid event
		[6] CTO_EN Command Timeout
		[7] CTF_EN Command finish (command FIFO empty)
		[8] CRF_EN Command Rx Buffer Full
		[9] TXBF Tx Buffer Full

base+12 RW Devsel (normal mode only)

base+16 R intr pending register
        [0] tx_end transter end
	  	[1] tx_rdy transfer ready
		[2] TXBHWM_EN Tx Buffer low watermark intr
		[3] RXBLWM_EN Rx Buffer hign watermark intr
		[4] TXBE_EN Tx Buffer empty intr
		[5] RXBV_EN Rx Buffer valid intr
		[6] CTO_EN Command Timeout
		[7] CTF_EN Command finish (command FIFO empty)
		[8] CRF_EN Command Rx Buffer Full

base+20 CMD FIFO
	W Command buffer
	R [7:0] Command FIFO waterlevel

base+24 Command timeout
	[23:0] maximum steps of single command

base+24 Command timeout

Command: 
	0x0XX SPI FSM Escape for {XX} cycles 
	0x1XX SPI Tx for {XX} bytes
	0x2XX SPI Rx for {XX} bytes 
	0x3XX SPI Tx/Rx for {XX} bytes 
	0x4XX DPI Tx for {XX} bytes
	0x5XX DPI Rx for {XX} bytes
	0x6XX QPI Tx for {XX} bytes
	0x7XX QPI Rx for {XX} bytes

	0x8XX LUREO SPI Rx loop until selected bits = 1
	0x9XX LUREZ SPI Rx loop until selected bits = 0
	0xAXX LUREQ SPI Rx loop until selected byte == {XX}
	0xBXX LURNE SPI Rx loop until selected byte != {XX}

	Others: NOP

	0xFXX Write {XX} into CS# register

This core uses zero-wait APB bus access. Clock crossing bridges between
CPU and this core might reduce performance.

*/
//////////////////////////////////////////////////////////////////////
`define INTR_PEDGE  2'b00
`define INTR_NEDGE  2'b01
`define INTR_HIGH   2'b10
`define INTR_LOW    2'b11
module tiny_qspi_apb(
   // system
   input	  			PRESETn,
   input	  			PCLK,
   // memory mapped
   input	  			PENABLE,
   input	  			PWRITE,
   output reg 	[31:0]  PRDATA,
   input 		[31:0]  PWDATA,
   input 		[4:0]	PADDR,
   input 	  			PSEL, 
   output 	  			PREADY, 
   output reg			PSLVERR, 
   output	  			int_o,

//    // spi
//    output	  MOSI_oe, //for Tri-wire SPI mode
//    output	  MOSI,
//    input	  MISO,
   
   input [3:0]			QSPI_QIN,
   output[3:0]			QSPI_QOUT,
   output[3:0]			QSPI_QOE,
   output	  			SCLK,
   output reg [DEVSEL_NUM-1:0]MCS
   );

	parameter SPI_MODE = 0;
	parameter BC_WIDTH = 3;
	parameter DEVSEL_NUM = 8;/*1~8 only*/

	localparam CMDFSM_IDLE = 2'b00;
	localparam CMDFSM_EXEC = 2'b01;
	localparam CMDFSM_WAIT = 2'b10;
	localparam CMDFSM_ABRT = 2'b11;

	localparam CMD_TOGGL= 4'b0000;
	localparam CMD_SPITX= 4'b0001;
	localparam CMD_SPIRX= 4'b0010;
	localparam CMD_SPITR= 4'b0011;
	localparam CMD_DPITX= 4'b0100;
	localparam CMD_DPIRX= 4'b0101;
	localparam CMD_QPITX= 4'b0110;
	localparam CMD_QPIRX= 4'b0111;
	localparam CMD_LUREO= 4'b1000;
	localparam CMD_LUREZ= 4'b1001;
	localparam CMD_LUREQ= 4'b1010;
	localparam CMD_LURNE= 4'b1011;
	/* Reserved */
	localparam CMD_SETCS= 4'b1111;

	wire rst_i = !PRESETn;
	wire [2:0]adr_i = PADDR[4:2];
	//Configure register
	reg [7:0]	baud_reg;
	reg op_mode;
	reg [8:0] intr_mask;
	reg msb_first;
	reg		  cpolr, cphar;
	//Intr penging
	wire [9:0] spi_events;
	wire [8:0] intr_pending;

	//
	wire [7:0]cmdfifo_waterlvl;
	reg [23:0]cmdto_cmp;

	wire		  data_wsel, istb, dstb;
	reg		  buf_flg;   // buffer flag
	//reg		  txren, txeen;
	wire 	  tx_rdy, tx_end;
	//SPI FSM signals
    wire [4:0] cycle_cnt;
    wire [1:0] mode_sel;
    wire load_flag;
    wire op_read;
	wire spi_fsm_op;
    wire op_end;
	wire cpol, cpha;
	wire dataout_valid;
	//CMD fsm signals
	reg cmd_rxfifo_we;
	reg [23:0]cmdto_cnt;
    reg [4:0] cmd_cycle_cnt;
    reg [1:0] cmd_mode_sel;
    reg cmd_op_read;
	wire cmd_spi_fsm_op;
	wire [11:0]cmd_data;
	reg [8:0]cmd_step_cnt,cmd_step_cnt_load; //1~256 steps
	reg [1:0]cmdfsm_stat,cmdfsm_stat_next;
	reg cmd_escape;
	wire cmd_data_wait; /*Rx buffer full or Tx buffer empty*/
	reg cmd_needs_compare;
	reg cmd_wr_csn;
	wire cmd_complete;
	wire cmd_timeout;
	wire cmd_keep_looping;
	reg cmd_cmp_hit;
	//bus signals
	wire 	  wr,rd;
	wire [31:0]data_input,data_out;
	wire [31:0]txfifo_in,rxfifo_out;
	wire txfifo_halfway,rxfifo_halfway;
	wire rxfifo_wr_halfway,txfifo_rd_halfway;

	assign PREADY = 1'b1; // zero wait
	assign wr = PENABLE & PSEL & PWRITE & PREADY;
	assign rd = PENABLE & PSEL & (!PWRITE) & PREADY;
	assign txfifo_write = wr & (adr_i == 1);
	assign rxfifo_read  = rd & (adr_i == 1);
	assign cmdfifo_write= wr & (adr_i == 5);

	assign istb = wr & (adr_i == 0);
	assign dstb = wr & (adr_i == 3);
	//assign sr8_sf = { sft8[6:0],misod };
	always@(*)
	case(adr_i)
		3'h0:PRDATA={1'b1,op_mode,msb_first,10'b0,intr_mask,cpolr,cphar,baud_reg} ;
		3'h1:PRDATA=rxfifo_out;
		3'h2:PRDATA={22'h0,spi_events};
		3'h3:PRDATA=MCS;
		3'h4:PRDATA={24'h0,intr_pending};
		3'h5:PRDATA=32'h0;
		3'h6:PRDATA=cmdto_cmp;
	endcase

//DATA WRITE BLOCK
   always @(posedge PCLK)
     begin
		if (istb) // instruction write enable
			{ intr_mask, cpolr, cphar , baud_reg} <= PWDATA[18:0];
		else
			{ intr_mask, cpolr, cphar , baud_reg} <= { intr_mask, cpolr, cphar , baud_reg};

		if (istb) // instruction write enable
			{ op_mode, msb_first } <= PWDATA[30:29];
		else
			{ op_mode, msb_first } <= { op_mode, msb_first };

     end // always @ (posedge PCLK)

	always @(posedge PCLK or posedge rst_i)
    begin
		if (rst_i)
			MCS <= {DEVSEL_NUM{1'b1}};
		else if(cmd_wr_csn & op_mode)
			MCS <= cmd_data[7:0];
		else if (dstb & (!op_mode))
			MCS <= PWDATA;
		else
			MCS <= MCS;
    end
	/*Todo: some intr related signals needed here*/
	assign { cpol, cpha } = ((SPI_MODE >= 0) & (SPI_MODE < 4)) ?
							SPI_MODE : { cpolr, cphar };

	assign spi_events = {	txfifo_full,
							rxfifo_full,
							cmdfifo_empty && (cmdfsm_stat == CMDFSM_IDLE) && op_mode,
							cmd_timeout,
							!rxfifo_empty,
							txfifo_empty,
							txfifo_rd_halfway,
							rxfifo_wr_halfway,
							tx_rdy,
							tx_end};
	assign tx_end = txfifo_empty;
	//assign tx_rdy = !txfifo_full;
	assign int_o = |intr_pending;
	intr_mgmt#(	
			.INTR_NUM(9),
			.INTR_CFG({9{`INTR_PEDGE}})
	)intr_mgmt_inst(
		.clk(PCLK),
		.intr_src(spi_events),
		.intr_clr(wr && (adr_i == 2)),
		.intr_clr_sel(PWDATA[8:0]),
		.intr_sig(intr_pending)
	);
	tiny_qspi_krnl qspi_fsm(
		.clk(PCLK),
		.rst_i(rst_i),
		.cpol(cpol),
		.cpha(cpha),
		.data_input(
			(msb_first)?
			data_input:
			{data_input[7:0],data_input[15:8],data_input[23:16],data_input[31:24]}
			),
		.cycle_cnt(cycle_cnt),
		.mode_sel(mode_sel),
		.baud_reg(baud_reg),
		.load_flag(load_flag),
		.op_read(op_read),
		.op_valid(spi_fsm_op),
		.op_end(tx_rdy),
		.data_out(data_out),
		.dataout_valid(dataout_valid),
		.QSPI_QIN(QSPI_QIN),
		.QSPI_QOUT(QSPI_QOUT),
		.QSPI_QOE(QSPI_QOE),
		.SCLK(SCLK)//,
	);
	//SPI triggers
	
    assign cycle_cnt= (op_mode)?cmd_cycle_cnt:
						data_input[30]?{1'b0,data_input[19:16]}:5'h0F;
	assign mode_sel = (op_mode)?cmd_mode_sel : data_input[29:28];
	assign op_read  = (op_mode)? cmd_op_read  : data_input[31];
	assign spi_fsm_op = (op_mode)?cmd_spi_fsm_op:((!txfifo_empty) & tx_rdy);
	assign rxfifo_we = (op_mode)?(cmd_rxfifo_we && dataout_valid) : (dataout_valid && op_read) ;
	assign cmdfifo_rd =!cmdfifo_empty && op_mode && (cmdfsm_stat==CMDFSM_IDLE);
	assign txfifo_rd = (op_mode)?(cmd_spi_fsm_op && (!cmd_op_read) && (!cmd_escape)):tx_rdy;//spi_fsm_op && ( () | !op_mode);
	assign cmd_spi_fsm_op =  (cmdfsm_stat==CMDFSM_EXEC) && (!cmd_escape) && (!cmd_data_wait); /*indeed we needs to trigger SPI FSM*/
	assign cmd_data_wait = (cmd_rxfifo_we && rxfifo_full) | (!cmd_op_read && txfifo_empty && (!cmd_escape));
	assign cmd_timeout = (cmdfsm_stat==CMDFSM_ABRT);
	assign cmd_keep_looping = (cmd_needs_compare)? !cmd_cmp_hit :cmd_step_cnt!=0; 
   	SyncFIFO_SPI #(
        .DWID(12),
        .DDEPTH(64))
    cmd_fifo(
        .clk(PCLK),
        .rst(rst_i),
        .ren(cmdfifo_rd),
        .wen(op_mode & cmdfifo_write),
        .fifoen(1'b1),
        .wdata(PWDATA[11:0]),
        .rdata(cmd_data),
        .full(cmdfifo_full),
        .empty(cmdfifo_empty),
        .halfway(),
        .about_empty(),
        .about_full()
    );
    SyncFIFO_SPI#(
        .DWID(32),
        .DDEPTH(128))
    data_tx_fifo(
        .clk(PCLK),
        .rst(rst_i),
        .ren(txfifo_rd),
        .wen(txfifo_write),
        .fifoen(op_mode),
        .wdata(PWDATA),
        .rdata(data_input),
        .full(txfifo_full),
        .empty(txfifo_empty),
        .halfway(txfifo_halfway),
        .about_empty(),
        .about_full()
	);
    SyncFIFO_SPI#(
        .DWID(32),
        .DDEPTH(128)
    )
    data_rx_fifo(
        .clk(PCLK),
        .rst(rst_i),
        .ren(rxfifo_read),
        .wen(rxfifo_we),
        .fifoen(op_mode),
        .wdata((msb_first)?
			data_out:
			{data_out[7:0],data_out[15:8],data_out[23:16],data_out[31:24]}),
        .rdata(rxfifo_out),
        .full(rxfifo_full),
        .empty(rxfifo_empty),
        .halfway(rxfifo_halfway),
        .about_empty(),
        .about_full()
    );
	assign txfifo_rd_halfway = txfifo_rd & txfifo_halfway;
	assign rxfifo_wr_halfway = rxfifo_we & rxfifo_halfway;
	//Command FSM
	
	always@(posedge PCLK or posedge rst_i)
	if(rst_i)
		cmdfsm_stat<=CMDFSM_IDLE;
	else
		cmdfsm_stat<=cmdfsm_stat_next;
	
	always@(*)
	case(cmdfsm_stat)
		CMDFSM_IDLE:
			if(!cmdfifo_empty && op_mode)
				cmdfsm_stat_next=CMDFSM_EXEC;
			else
				cmdfsm_stat_next=CMDFSM_IDLE;
		CMDFSM_EXEC: /* send this command downstream */
			if(cmd_escape) /*keep on waiting until FIFO ready*/
				cmdfsm_stat_next=CMDFSM_IDLE;
			else if(cmd_spi_fsm_op)//((!load_flag) | (!tx_rdy)) && (!cmd_escape)
				cmdfsm_stat_next=CMDFSM_WAIT;
			else 
				cmdfsm_stat_next=CMDFSM_EXEC;
		CMDFSM_WAIT:
			if(!load_flag)
				cmdfsm_stat_next=CMDFSM_WAIT;
			else if(cmdto_cnt==0)
				cmdfsm_stat_next=CMDFSM_ABRT;
			else if(cmd_keep_looping)
				cmdfsm_stat_next=CMDFSM_EXEC;
			// else if(!cmdfifo_empty && op_mode)
			// 	cmdfsm_stat_next=CMDFSM_IDLE;
			else 
				cmdfsm_stat_next=CMDFSM_IDLE;
		CMDFSM_ABRT:
			cmdfsm_stat_next=CMDFSM_IDLE;
	endcase

	//Parse command
	always@(*)
	begin
		cmd_wr_csn=1'b0;
		case(cmd_data[11:8])
		CMD_TOGGL:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load={5'h0,cmd_data[7:5]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?cmd_step_cnt_load[4:0]:5'h1F;
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
		end
		CMD_SPITX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{cmd_step_cnt_load[1:0],3'h7}:5'h1F;
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
		end
		CMD_SPIRX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{cmd_step_cnt_load[1:0],3'h7}:5'h1F;
			cmd_rxfifo_we=1'b1;
			cmd_needs_compare=1'b0;
		end
		CMD_SPITR:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{cmd_step_cnt_load[1:0],3'h7}:5'h1F;
			cmd_rxfifo_we=1'b1;
			cmd_needs_compare=1'b0;
		end
		CMD_DPITX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b01;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{1'b0,cmd_step_cnt_load[1:0],2'h3}:5'h0F;
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
			
		end
		CMD_DPIRX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b01;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{1'b0,cmd_step_cnt_load[1:0],2'h3}:5'h0F;
			cmd_rxfifo_we=1'b1;
			cmd_needs_compare=1'b0;
		end
		CMD_QPITX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b10;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{2'h0,cmd_step_cnt_load[1:0],1'b1}:5'h03;
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
			
		end
		CMD_QPIRX:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b10;
			cmd_step_cnt_load={2'h0,cmd_data[7:2]};
			cmd_cycle_cnt = (cmd_step_cnt == 0)?{2'h0,cmd_step_cnt_load[1:0],1'b1}:5'h03;
			cmd_rxfifo_we=1'b1;
			cmd_needs_compare=1'b0;
			
		end
		CMD_LUREO:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h01; /*always 01*/
			cmd_cycle_cnt = 5'h07;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b1;
		end
		CMD_LUREZ:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h01; /*always 01*/
			cmd_cycle_cnt = 5'h07;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b1;
			
		end
		CMD_LUREQ:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h01; /*always 01*/
			cmd_cycle_cnt = 5'h07;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b1;
			
		end
		CMD_LURNE:begin
			cmd_escape=1'b0;
			cmd_op_read=1'b1;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h01; /*always 01*/
			cmd_cycle_cnt = 5'h07;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b1;
		end
		CMD_SETCS:begin
			cmd_escape=1'b1;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h00; /*always 01*/
			cmd_cycle_cnt = 5'h00;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
			cmd_wr_csn=1'b1;
		end
		default:begin /* NOP */
			cmd_escape=1'b1;
			cmd_op_read=1'b0;
			cmd_mode_sel=2'b00;
			cmd_step_cnt_load=8'h00; /*always 01*/
			cmd_cycle_cnt = 5'h00;/*read a byte*/
			cmd_rxfifo_we=1'b0;
			cmd_needs_compare=1'b0;
		end
		endcase
	end
	//step counter
	always@(posedge PCLK)
	if((cmdfsm_stat == CMDFSM_IDLE) && (cmdfsm_stat_next == CMDFSM_EXEC))
		cmd_step_cnt<=cmd_step_cnt_load;
	else if((cmdfsm_stat == CMDFSM_WAIT) && (cmdfsm_stat_next == CMDFSM_EXEC))
		cmd_step_cnt<=cmd_step_cnt-1;
	else if(cmdfsm_stat_next == CMDFSM_IDLE)
		cmd_step_cnt<=8'hFF;
	else
		cmd_step_cnt<=cmd_step_cnt;
	
	always@(posedge PCLK)
	if((cmdfsm_stat == CMDFSM_IDLE) && (cmdfsm_stat_next == CMDFSM_EXEC) && cmd_needs_compare)
		cmdto_cnt<=cmdto_cmp;
	else if((cmdfsm_stat == CMDFSM_WAIT) && (cmdfsm_stat_next == CMDFSM_EXEC))
		cmdto_cnt<=cmdto_cnt-1;
	else if(cmdfsm_stat_next == CMDFSM_IDLE)
		cmdto_cnt<=24'hFFFFFF;
	else
		cmdto_cnt<=cmdto_cnt;

	always@(*)
	case (cmd_data[9:8])
	2'b00:cmd_cmp_hit=|(cmd_data[7:0] & data_out[31:28]);
	2'b01:cmd_cmp_hit=|(cmd_data[7:0] & (~data_out[31:28]));
	2'b10:cmd_cmp_hit= cmd_data[7:0] == data_out[31:28];
	2'b11:cmd_cmp_hit= cmd_data[7:0] != data_out[31:28];
	endcase

	always@(posedge PCLK or posedge rst_i)//READY GEN
	begin
	if(rst_i)
		PSLVERR<=1'b0;
	else if(rxfifo_read)
		PSLVERR<= rxfifo_empty;
	else if(txfifo_write)
		PSLVERR<= txfifo_full;
	else if(cmdfifo_write)
		PSLVERR<= cmdfifo_full;
	else 
		PSLVERR<=1'b0;
	end
	
endmodule
