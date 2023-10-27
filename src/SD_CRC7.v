module SD_CRC7( 
                    crcIn,
                    crcEn,
                    sdClk,
                    crcRst,
                    crcOut);
                    
    input     crcIn;
    input     crcEn;
    input     sdClk;
    input     crcRst;
    
    output [6:0]   crcOut;
    
    reg    [6:0]   crcOut;
    reg    [6:0]   crc_in; 
    
    reg       temp_0;    
    
    // CRC register
    always @(posedge sdClk or posedge crcRst)
      begin : CRC_REG
        if (crcRst)
          crcOut <= 7'h00;
        else if (crcEn)
          crcOut <= crc_in;
      end // block: CRC_REG  
  
    // Input to CRC register   
    always @(crcEn or crcOut or crcIn)
      begin 
        if (crcEn)
          begin
            crc_in = crcOut;          
            begin
              temp_0 = crcIn ^ crc_in[6];
              crc_in = crc_in << 1;
              if (temp_0)
                crc_in = crc_in ^ 7'h09; 
            end
          end
        else
          begin
            crc_in = crcOut;
            temp_0 = 1'b0; 	
          end
      end// block: CRC_0   
endmodule                    