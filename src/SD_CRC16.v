module SD_CRC16(
                     crcDat_in,
                     crcDat_en, 
                     sdClk, 
                     crcDat_rst,
                     crcDat_out);
                     
    input     crcDat_in;
    input     crcDat_en;
    input     sdClk;
    input     crcDat_rst;
    
    output [15:0]   crcDat_out;
    
    reg    [15:0]   crcDat_out;
    reg    [15:0]   crc_in; 
    
    reg       temp_0;    
    
    // CRC register
    always @(posedge sdClk or posedge crcDat_rst)
      begin : CRC_REG
        if (crcDat_rst)
          crcDat_out <= 16'h00;
        else if (crcDat_en)
          crcDat_out <= crc_in;
      end // block: CRC_REG  
  
    // Input to CRC register   
    always @(crcDat_en or crcDat_out or crcDat_in)
      begin  
        if (crcDat_en)
          begin
            crc_in = crcDat_out;          
            begin
              temp_0 = crcDat_in ^ crc_in[15];
              crc_in = crc_in << 1;
              if (temp_0)
                crc_in = crc_in ^ 16'h1021; 
            end
          end
        else
          begin
            crc_in = crcDat_out;
            temp_0 = 1'b0; 	
          end
      end// block: CRC_0   
endmodule                                         