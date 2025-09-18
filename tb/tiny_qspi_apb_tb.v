`timescale 1ns/100ps

module tiny_qspi_tb();


    reg PCLK,PRESETn,APB2SPI_PWRITE,APB2SPI_PSEL,APB2SPI_PENABLE;//input
    reg [31:0] APB2SPI_PWDATA;
    reg [4:0]    APB2SPI_PADDR;
    wire APB2SPI_PSLVERR,APB2SPI_PREADY,APB2SPI_INTERRUPT;//output
    wire [3:0]	QSPI_QIN;
    wire [3:0]	QSPI_QOUT;
    wire [3:0]	QSPI_QOE;
    wire 	  	SCLK;
    wire [7:0]MCS;
    wire [31:0] APB2SPI_PRDATA;
    reg [31:0]mode_reg;
    reg [31:0]data_tgt[255:0];
    reg [31:0]data_src[255:0];
    reg [3:0] QSPI_GIBERRISH; // in order to perform R/W unit test
    reg [31:0]apb_rddata;

    wire [3:0]QSPI_QDAT;
    assign QSPI_QIN = QSPI_QDAT;
    genvar j;
    generate for(j=0;j<4;j=j+1)
        begin:QSPI_DATGEN
            pullup(QSPI_QDAT[j]);
            assign QSPI_QDAT[j] = (QSPI_QOE[j])?QSPI_QOUT[j]:
                                    (!MCS[2])?QSPI_GIBERRISH[i]:1'bz;
        end
    endgenerate
    tiny_qspi_apb DUT(
    // system
    .PRESETn(PRESETn),
    .PCLK(PCLK),
    .PENABLE(APB2SPI_PENABLE),
    .PWRITE(APB2SPI_PWRITE),
    .PRDATA(APB2SPI_PRDATA),
    .PWDATA(APB2SPI_PWDATA),
    .PADDR(APB2SPI_PADDR),
    .PSEL(APB2SPI_PSEL), 
    .PREADY(APB2SPI_PREADY), 
    .int_o(APB2SPI_INTERRUPT),
    .QSPI_QIN(QSPI_QIN),
    .QSPI_QOUT(QSPI_QOUT),
    .QSPI_QOE(QSPI_QOE),
    .SCLK(SCLK),
    .MCS(MCS)
    );
    M23A1024 Model_PSRAM(
        .SI_SIO0(QSPI_QDAT[0]), 
        .SO_SIO1(QSPI_QDAT[1]), 
        .SCK(SCLK), 
        .CS_N(MCS[1]), 
        .SIO2(QSPI_QDAT[2]), 
        .HOLD_N_SIO3(QSPI_QDAT[3]), 
        .RESET(!PRESETn)
        );
    W25Q128JVxIM Model_Flash
    (
        .CSn(MCS[0]), 
        .CLK(SCLK), 
        .DIO(QSPI_QDAT[0]), 
        .DO(QSPI_QDAT[1]), 
        .WPn(QSPI_QDAT[2]), 
        .HOLDn(QSPI_QDAT[3])
    );

    initial
    forever 
    begin
        #10  PCLK=1'b1;
        #10  PCLK=1'b0;
    end
    reg [1:0] TEST_MODE=0; 
    reg [2:0] testsft_cnt;
    reg [7:0] testdata_cnt;
    reg [7:0] testdata_sft;
    /* QSPI test data(read) block */
    always@(posedge SCLK or posedge MCS[2])
    if(MCS[2])
    begin
        testdata_cnt<=0;
        testdata_sft<=0;
        testsft_cnt<=0;
    end
    else
    begin
        case(TEST_MODE)
        2'b00:
        begin
            testdata_sft<={testdata_sft[6:0],QSPI_QDAT[0]}; 
            if(testsft_cnt<7)
            begin  
                testsft_cnt<=testsft_cnt+1;
                testdata_cnt<=0;
            end
            else
            begin
                testsft_cnt<=testsft_cnt;
                testdata_cnt<=testdata_cnt+1;
            end
        end
        2'b01:
        begin
            testdata_sft<={testdata_sft[5:0],QSPI_QDAT[1:0]}; 
            if(testsft_cnt<3)
            begin  
                testsft_cnt<=testsft_cnt+1;
                testdata_cnt<=0;
            end
            else
            begin
                testsft_cnt<=testsft_cnt;
                testdata_cnt<=testdata_cnt+1;
            end
        end
        2'b10:
        begin
            testdata_sft<={testdata_sft[3:0],QSPI_QDAT}; 
            if(testsft_cnt<1)
            begin  
                testsft_cnt<=testsft_cnt+1;
                testdata_cnt<=0;
            end
            else
            begin
                testsft_cnt<=testsft_cnt;
                testdata_cnt<=testdata_cnt+1;
            end
        end
        2'b11:
        begin//RESERVED FOR OSPI
            testdata_cnt<=0;
            testdata_sft<=0;    
        end
        endcase
    end
    
    always@(negedge SCLK)
    if(!MCS[2])
        QSPI_GIBERRISH<=$random;
    else
        QSPI_GIBERRISH<=4'h0;
    
    
    task qspictl_reset;
        begin
            $display("------------------reset the APB_SPI,Active low-----------------------");
            #100
            PRESETn = 1;//Active low
            #300
            PRESETn = 0;
            #300
            PRESETn = 1;
        end
    endtask
    wire apb_reply_valid = PCLK & APB2SPI_PREADY;
    reg [31:0] apb_rdata;
    task apb_xfer;// finish data read/write
        //input mode;
        //input [1:0]addr1;
        input [31:0]addr;
        input we;
        input [31:0]wdata;
        output [31:0]rdata;
        begin //APB Timing body
            //@(posedge HCLK);
            @(posedge PCLK);
            APB2SPI_PADDR   = addr;
            APB2SPI_PSEL    = 1;
            APB2SPI_PENABLE = 0;
            APB2SPI_PWRITE  = we;
            APB2SPI_PWDATA  = wdata;
            //spi_mode        = mode;
            @(posedge PCLK);
            APB2SPI_PENABLE = 1;
            fork
                @(posedge PCLK)
                    APB2SPI_PENABLE = 0;
                @(posedge apb_reply_valid)
                    rdata = APB2SPI_PRDATA[31:0];
            join
            @(posedge PCLK);
            APB2SPI_PENABLE = 0;
            @(posedge PCLK);
        end
    endtask

    task apb_read_test;
    input [1:0]spi_mode;
    input [4:0]spi_cycles;
    input non_aligned;
    output [15:0]data_out;
    reg [7:0]timeout_cnt;
    reg loop_escape;
    begin
        timeout_cnt=8'hff;
        loop_escape=1'b0;
        apb_xfer(32'h4,1'b1,{1'b1,non_aligned,spi_mode,8'h00,spi_cycles[3:0],16'hFFFF},apb_rddata);
        apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
        while(loop_escape==0)//for(timeout_cnt=8'hff;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h02)==0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP does not go busy after req issued!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        loop_escape=1'b0;
        timeout_cnt=8'hff;
        while(loop_escape==0)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h02)!=0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP timeout for single command!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        apb_xfer(32'h4,1'b0,32'h00000000,data_out);
    end
    endtask

    task apb_write_test;
    input [1:0]spi_mode;
    input [4:0]spi_cycles;
    input non_aligned;
    input [15:0]data_in;
    reg [7:0]timeout_cnt;
    reg loop_escape;
    begin
        timeout_cnt=8'hff;
        loop_escape=1'b0;
        apb_xfer(32'h4,1'b1,{1'b0,non_aligned,spi_mode,8'h00,spi_cycles[3:0],data_in},apb_rddata);
        apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
        while(loop_escape==1'b0)//for(timeout_cnt=8'hff;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h02)==0;
            if(timeout_cnt == 0)
            begin
                $display("FATAL: IP does not go busy after req issued!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        loop_escape=1'b0;
        timeout_cnt=8'hff;
        while(loop_escape==1'b0)//for((timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h02)!=0;
            if(timeout_cnt == 0)
            begin
                $display("FATAL: IP timeout for single command!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end

    end
    endtask

    task cmd_read_test;
    input [1:0]spi_mode;
    input [7:0]spi_bytes;
    reg [7:0]cmd_steps;
    reg [3:0]cmd_test;
    reg [15:0]timeout_cnt;
    reg loop_escape;
    begin
        timeout_cnt=16'h00ff;
        case(spi_mode)
            2'b00:cmd_test=4'h2;
            2'b01:cmd_test=4'h5;
            2'b10:cmd_test=4'h7;
            2'b11:cmd_test=4'h0;/* reserved */
        endcase
        apb_xfer(32'h14,1'b1,{20'h00000,cmd_test,spi_bytes},apb_rddata);
        
        loop_escape=1'b0;
        timeout_cnt=16'h0fff;
        while(loop_escape!=1)//for(( & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h02)==0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP timeout for read command!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        loop_escape=1'b0;timeout_cnt=16'h0fff;
        while(loop_escape!=1'b1)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h100)!=0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP timeout for read buffer full!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        loop_escape=1'b0;
        while(loop_escape!=1'b1)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h4,1'b0,32'h00000000,apb_rddata);
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = apb_rddata[5]==1'b0;
        end
        loop_escape=1'b0;timeout_cnt=16'h0fff;
        while(loop_escape!=1'b1)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h080)!=0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP timeout waiting CMD finish!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
        loop_escape = apb_rddata[5]==1'b0;
        while(loop_escape!=1'b1)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h4,1'b0,32'h00000000,apb_rddata);
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = apb_rddata[5]==1'b0;
        end
    end
    endtask

    task cmd_write_test;
    input [1:0]spi_mode;
    input [7:0]spi_bytes;
    reg [7:0]cmd_steps;
    reg [3:0]cmd_test;
    reg [15:0]timeout_cnt;
    reg loop_escape;
    begin
        timeout_cnt=16'h00ff;
        loop_escape=1'b0;
        while(loop_escape!=1'b1)//for(timeout_cnt=16'h00ff;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h4,1'b1,$random,apb_rddata);
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h200)!=0; /*fill tx fifo until full*/;
            if(timeout_cnt==0)
            begin
                $display("FATAL: Tx fifo never full!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        case(spi_mode)
            2'b00:cmd_test=4'h1;
            2'b01:cmd_test=4'h4;
            2'b10:cmd_test=4'h6;
            2'b11:cmd_test=4'h1;/* reserved */
        endcase
        apb_xfer(32'h14,1'b1,{20'h00000,cmd_test,spi_bytes},apb_rddata);
        loop_escape=1'b0;timeout_cnt=16'h0fff;
        while(loop_escape!=1'b1)//for(;(timeout_cnt!=0 & (loop_escape!=0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h080)!=0;
            if(timeout_cnt==0)
            begin
                $display("FATAL: IP timeout for CMD finish!");
                $finish;
            end
            @(posedge PCLK);
            timeout_cnt=timeout_cnt-1;
        end
        
    end

    endtask
    task cmd_loop_test;
    input [1:0]loop_mode;
    reg [15:0]timeout_cnt;
    //input 
    reg [7:0]pattern_byte;
    reg loop_escape;
    integer i;
    begin //testdata_cnt
        TEST_MODE=0;
        loop_escape=0;
        pattern_byte=8'h01;
        apb_xfer(32'h14,1'b1,{20'h00000,4'hF,8'b11111011},apb_rddata);
        apb_xfer(32'h18,1'b1,32'h03,apb_rddata);//write a low timeout value
        for(i=0;i<4;i=i+1)
        begin
            loop_escape=0;
            apb_xfer(32'h14,1'b1,{20'h00000,4'h8+loop_mode,pattern_byte},apb_rddata);
            apb_xfer(32'h08,1'b0,32'h00000000,apb_rddata);
            for(timeout_cnt=16'hFFF;(timeout_cnt!=0 & (loop_escape==0));timeout_cnt=timeout_cnt-1)
            begin
                apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
                loop_escape = (apb_rddata & 32'hC0)!=0;
            end
            if(apb_rddata[7:6] ===2'b10 )
                $display("CMD finished with success!");
            else if(apb_rddata[7:6] ===2'b11 )
                $display("CMD timeout as intended!");
            else
                $display("CMD FSM stuck!");
            
            apb_xfer(32'h08,1'b1,32'h00000FFF,apb_rddata);
        end
        //$display("TBD!");
    end
    endtask

    task cmd_cstoggle_test;
    reg [7:0]toggle_reg,timeout_cnt;
    reg loop_escape;
    begin
        toggle_reg=8'h01;
        loop_escape=0;
        for(i=0;i<9;i=i+1)
        begin
            apb_xfer(32'h14,1'b1,{20'h00000,4'hF,~toggle_reg},apb_rddata);
            toggle_reg=toggle_reg<<1;
        end
        for(timeout_cnt=8'hff;(timeout_cnt!=0 & (loop_escape==0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'h80)!=0;
        end
        if(!loop_escape)
        begin
            $display("FATAL: IP does not ready long after req issued!");
            $finish;
        end
    end
    endtask
    task cmd_dummy_test;
    input [7:0]dummy_cycles;
    begin
        apb_xfer(32'h14,1'b1,{20'h00000,4'h0,dummy_cycles},apb_rddata);
    end
    endtask

    task cmd_sram_spi_rw_test;
    reg [15:0] timeout_cnt;
    reg [31:0]datagen;
    reg loop_escape;
    integer i,err_cnt;
    begin
        $display("Start SRAM SPI R/W test!");
        loop_escape=0;err_cnt=0;
        apb_xfer(32'h18,1'b1,{20'h00000,12'hFFF},apb_rddata);//set longer limit

        apb_xfer(32'h14,1'b1,{20'h00000,4'hF,8'b1111_1101},apb_rddata);
        apb_xfer(32'h14,1'b1,{20'h00000,4'h1,8'h0},apb_rddata);
        apb_xfer(32'h04,1'b1,{24'h000000,8'h02},apb_rddata);//write CMD
        apb_xfer(32'h14,1'b1,{20'h00000,4'h1,8'h78},apb_rddata);//write 128byte data
        for(i=0;i<31;i=i+1)
        begin
            datagen=$random;
            apb_xfer(32'h04,1'b1,datagen,apb_rddata);
            data_src[i]=datagen;
        end
        apb_xfer(32'h14,1'b1,{20'h00000,4'hF,8'b1111_1111},apb_rddata);//deselect
        apb_xfer(32'h14,1'b1,{20'h00000,4'h0,8'h08},apb_rddata);//wait 8 byte
        apb_xfer(32'h14,1'b1,{20'h00000,4'hF,8'b1111_1101},apb_rddata);
        apb_xfer(32'h14,1'b1,{20'h00000,4'h1,8'h0},apb_rddata);//write read cmd
        apb_xfer(32'h04,1'b1,{24'h000000,8'h03},apb_rddata);//read CMD
        apb_xfer(32'h14,1'b1,{20'h00000,4'h2,8'h80},apb_rddata);//read 128byte data
        for(timeout_cnt=16'hFFFF;(timeout_cnt!=0 & (loop_escape==0));timeout_cnt=timeout_cnt-1)
        begin
            apb_xfer(32'h8,1'b0,32'h00000000,apb_rddata);
            loop_escape = (apb_rddata & 32'hC0)!=0;
        end
        if(loop_escape)
        begin
            err_cnt=0;
            $display("Seems command sequence done!");
            for(i=0;i<31;i=i+1)
            begin
                apb_xfer(32'h04,1'b0,datagen,apb_rddata);
                if(data_src[i]!=apb_rdata)
                begin
                    $display("Data Cmp fail! exp:0x%x got:0x%x",data_src[i],apb_rdata);
                    err_cnt++;
                end
            end
            if(err_cnt===0)
                $display("PSRAM W/R test pass!");
        end
        else
            $display("Command sequence timeout!!!");
    end
    endtask

    integer i;
    initial begin /*Test module*/
    `ifdef WAVE_ON
        $dumpfile(`WAVE_NAME);
        $dumpvars;
    `endif    
        //QSPI_QIN=4'h0;
        qspictl_reset;
        apb_xfer(32'h0,1'b1,32'h00000000,apb_rddata);/*config at fastest normal mode*/
        for(i=0;i<32;i=i+1) /*SPI aligned read test*/
        begin
            $display("run SPI read test #%d",i);
            apb_read_test(2'b00,5'h0F,1'b0,apb_rddata);
            /*compare data TBD*/
        end
        for(i=0;i<32;i=i+1) /*SPI aligned write test*/
        begin
            $display("run SPI write test #%d",i);
            apb_rddata=$random;
            apb_write_test(2'b00,5'h0F,1'b0,apb_rddata[15:0]);
            /*compare data TBD*/
        end
        
        for(i=0;i<32;i=i+1) /*DPI aligned read test*/
        begin
            $display("run DPI read test #%d",i);
            apb_read_test(2'b01,5'h07,1'b0,apb_rddata);
            /*compare data TBD*/
        end
        for(i=0;i<32;i=i+1) /*DPI aligned write test*/
        begin
            $display("run DPI write test #%d",i);
            apb_rddata=$random;
            apb_write_test(2'b01,5'h07,1'b0,apb_rddata[15:0]);
            /*compare data TBD*/
        end

        for(i=0;i<32;i=i+1) /*QPI aligned read test*/
        begin
            $display("run QPI read test #%d",i);
            apb_read_test(2'b10,5'h03,1'b0,apb_rddata);
            /*compare data TBD*/
        end
        for(i=0;i<32;i=i+1) /*QPI aligned write test*/
        begin
            $display("run QPI write test #%d",i);
            apb_rddata=$random;
            apb_write_test(2'b10,5'h03,1'b0,apb_rddata[15:0]);
            /*compare data TBD*/
        end
        /*command mode test*/
        qspictl_reset;
        $display("Start testing CMD mode");
        apb_xfer(32'h0,1'b1,32'h40000000,apb_rddata);/*config at fastest cmd mode*/
        apb_xfer(32'h18,1'b1,32'h0000FFFF,apb_rddata);/*config at fastest cmd mode*/
        cmd_cstoggle_test;
        for(i=0;i<3;i=i+1)
        begin
            $display("Start testing CMD read mode");
            cmd_read_test(i,8'hFF);
            $display("Start testing CMD write mode");
            cmd_write_test(i,8'hFF);
        end
        for(i=0;i<4;i=i+1)
            cmd_loop_test(i);
        cmd_dummy_test($random);
        cmd_sram_spi_rw_test;
        $finish();
    end

endmodule

