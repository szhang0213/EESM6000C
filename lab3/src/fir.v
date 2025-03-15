module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
    
    //------------------------------------------------------------------------------------------
    //------------------------------------------------------------------------------------------
    //--- num_to_data_ram: If there is a value written into dataram, the variable is '1'--------
    //--- cnt_data_num: count the number of data transfered through Axi-Stream------------------
    //--- exe_times_reqd: Fir Engine should performe how many times to accumulation. -----------
    //------------------- 1 <= cnt_data_num <= 11, exe_times_reqd is cnt_data_num; -------------
    //------------------- cnt_data_num >=12, exe_times_reqd is 11 ------------------------------
    //--- cnt_cycles: count clodk cycles during the activation of FIR E ngine-------------------
    //------------------------------------------------------------------------------------------
    //------------------------------------------------------------------------------------------ 
    
    
    
    
    
    /*-------------- Axi-lite for intializing Tap_RAM ------------*/
    //--- write interface ---
    reg awready_r, wready_r;
    reg [(pADDR_WIDTH-1):0] addr_valid;
    reg [(pDATA_WIDTH-1):0] data_valid;
    
    //--- variable for fir ---
    reg ap_idle, ap_done, ap_start;
    reg num_to_dataram;
    reg [9:0] cnt_data_number;
    reg [3:0] exe_times_reqd;
    reg [4:0] cnt_cycles;
    
    // exe_times_reqd
    always @(*) begin
      if(cnt_data_number >= 10'd12) exe_times_reqd = 4'd11;
      else exe_times_reqd = cnt_data_number;
    end
      
    //--- variable for receving data from address 0x00
    wire [31:0] ap;
    
    assign awready = awready_r;
    assign wready = wready_r;
    
    assign ap = (addr_valid == 'b0) ? data_valid : 'b0; // addr_valid is 0x00, assign ap 
    
    // ap_idle, ap_done, ap_start
    // --ap_idle--
    always @(posedge axis_clk) begin
      if(~axis_rst_n | (cnt_cycles == exe_times_reqd + 4'd2)) ap_idle <= 1'b1;
      else if(ap[0] & num_to_dataram & ap_idle) ap_idle <= 1'b0;
    end
    
    // --ap_start--    
    always @(posedge axis_clk) begin
      if(~axis_rst_n | ~ap_idle) ap_start <= 1'b0;
      else if (ap[0] & num_to_dataram & ap_idle) ap_start<= 1'b1;
    end
        
    // --ap_done, see line 287 --
    
    
    
    // awready
    always @(posedge axis_clk) begin
      if(~axis_rst_n) awready_r <= 1'b0;
      else if(~awready & awvalid & wvalid) begin
        if((awaddr == 'b0) & (~ap_idle)) awready_r <= 1'b0; // if awaddris 0x00, should determine
        else begin                                         // fir is working or not
          awready_r <= 1'b1;
          addr_valid <= awaddr;
        end
      end
      else awready_r <= 1'b0;
    end
    
    // wready 
    always @(posedge axis_clk) begin
      if(~axis_rst_n) wready_r <= 1'b0;
      else if(~wready & awvalid & wvalid) begin
        if((awaddr == 'b0) & (~ap_idle)) wready_r <= 1'b0; // if awaddr is 0x00, should determine
        else begin                                         // fir is working or not
          wready_r <= 1'b1;
          data_valid <= wdata;
        end
      end
      else wready_r <= 1'b0;
    end
    
    
    //--- Read Interface ---
    // arready, araddr_valid
    reg arready_r;
    reg [(pADDR_WIDTH-1):0] araddr_valid;
    
    assign arready = arready_r;
    
    always @(posedge axis_clk) begin
      if(~axis_rst_n) arready_r <= 1'b0;
      else if((~arready_r) & arvalid & (~rvalid)) begin
        arready_r <= 1'b1;
        araddr_valid <= araddr;
      end
      else arready_r <= 1'b0;
    end
    
    // rvalid, rdata
    reg rvalid_r;
    reg [(pDATA_WIDTH-1):0] rdata_r;
    wire [(pDATA_WIDTH-1):0] h;
    
    assign rvalid = rvalid_r;
    assign rdata = rdata_r;
    
    always @(posedge axis_clk) begin
      if(~axis_rst_n) begin
        rvalid_r <= 1'b0;
        rdata_r <= 'b0;
      end
      else if((~rvalid_r) & arvalid & arready_r) begin
        rvalid_r <= 1'b1;
        if((araddr == 'b0)) rdata_r <= {29'b0, ap_idle, ap_done, ap_start}; // araddr is 0x00, return this value
        else rdata_r <= h; // araddr belogs to 0x20 ~ 0x48, returns tap_ram data output
      end
      else rvalid_r <= 1'b0;
    end
    
            
    //--- Tap_RAM ---
    localparam TAP_RAM_WIDTH = 4;
    wire [(TAP_RAM_WIDTH-1):0] waddr_tap_ram, araddr_tap_ram;
    reg [(TAP_RAM_WIDTH-1):0] addr_tap_ram;
    reg [(TAP_RAM_WIDTH-1):0] addrb_tap_ram;
    
    wire EN_wr_t, EN_rd_t, EN_wr, EN_rd;
    reg enb_tap_ram;
   
    
    // generate address for tap_ram
    assign waddr_tap_ram = {addr_valid[6], addr_valid[4:2]}; // write interface address for tap_ram
    assign araddr_tap_ram = ap_idle ? {araddr_valid[6], araddr_valid[4:2]} : addrb_tap_ram; // read interface address for tap_ram
    
  
                          
    // EN signal
    assign EN_wr_t = ((~addr_valid[7]) & (~addr_valid[6]) & addr_valid[5]) | 
                ((~addr_valid[7]) & addr_valid[6] & (~addr_valid[5]) & (~addr_valid[4]));
                
    assign EN_rd_t = ((~araddr_valid[7]) & (~araddr_valid[6]) & araddr_valid[5]) | 
                ((~araddr_valid[7]) & araddr_valid[6] & (~araddr_valid[5]) & (~araddr_valid[4]));
    
    assign EN_wr = EN_wr_t & awready & wready;
    assign EN_rd = ap_idle ? (EN_rd_t & arready) : enb_tap_ram;
    
    blk_mem_gen_0 tap_ram (
      .clka(axis_clk),
      .ena(EN_wr),
      .wea(1'b1),
      .addra(waddr_tap_ram),
      .dina(data_valid),
      .clkb(axis_clk),
      .enb(EN_rd),
      .addrb(araddr_tap_ram),
      .doutb(h)
    );
    
    /*------------ Axi Stream for x[n] --> data_ram----------------*/
    
    //--- variable for Axi-stream ---
    reg ss_tready_r= 1'b0; 
    reg [31:0] ss_data_valid;
    
        
    // Axi-Stream, write to data_ram
    assign ss_tready = ss_tready_r;
    
    always @(posedge axis_clk) begin
      if(~axis_rst_n) begin
        ss_tready_r <= 1'b0;
      end else if(ss_tvalid & ap_idle & (~num_to_dataram) & (~ss_tready)) begin // axi-stram data is valid,
        ss_tready_r <= 1'b1;                                                    // fir is idle,
        ss_data_valid <= ss_tdata;                                              // addr_rd_data_ram is 0                                                            // num_to_dataram == 0
      end else begin                                                               
        ss_tready_r <= 1'b0;
      end
    end
 
    
    // data_ram 
    reg [3:0] addra_data_ram, addrb_data_ram;
    reg ena_data_ram, enb_data_ram;
    wire [31:0] x;
    
    // num_to_dataram
    always @(posedge axis_clk) begin
      if(~axis_rst_n) num_to_dataram <= 1'b0;
      else if(ss_tvalid & ap_idle & (~num_to_dataram) & (~ss_tready)) num_to_dataram <= 1'b1;
      else if(ap[0] & num_to_dataram & ap_idle) num_to_dataram <= 1'b0;
    end
    
    
        
    always @(posedge axis_clk) begin
      if(~axis_rst_n) begin
        addra_data_ram <= 4'd10;
        ena_data_ram <= 1'b0;
        cnt_data_number <= 10'b0;
      end else begin
         if(ss_tvalid & ap_idle & (~num_to_dataram) & (~ss_tready)) begin
           ena_data_ram <= 1'b1;
           cnt_data_number <= cnt_data_number + 1'b1;
           if(addra_data_ram == 4'd10) addra_data_ram <= 4'b0;
           else addra_data_ram <= addra_data_ram + 1'b1; 
         end 
         else ena_data_ram <= 1'b0; 
      end
    end 
    
    blk_mem_gen_0 data_ram (
      .clka(axis_clk),
      .ena(ena_data_ram),
      .wea(1'b1),
      .addra(addra_data_ram),
      .dina(ss_data_valid),
      .clkb(axis_clk),
      .enb(enb_data_ram),
      .addrb(addrb_data_ram),
      .doutb(x)
    );
      
    /*----------------------- FIR Engine -------------------------*/
    
    reg [31:0] mulA, mulB; // multiple operand
    (*use_dsp = "no"*) reg [31:0] addA;   // product
    (*use_dsp = "no"*) reg [31:0] FIRResult;
    
    // generate addrb for tap_ram and data_ram 
    always @(posedge axis_clk) begin
      if(~axis_rst_n)  begin
        addrb_tap_ram <= 'b0;
        addrb_data_ram <= 'b0;
      end else begin
        // cnt_data_number <= 11
        if(cnt_data_number <= 11) begin
          if(ap[0] & num_to_dataram & ap_idle) begin   
            enb_tap_ram <= 1'b1;
            enb_data_ram <= 1'b1;
            addrb_tap_ram <= 'b0;
            addrb_data_ram <= exe_times_reqd - 1'b1;
          end
          else if(cnt_cycles == exe_times_reqd - 1'b1) begin
            enb_tap_ram <= 1'b0;
            enb_data_ram <= 1'b0;
          end
          else begin
            addrb_tap_ram <= addrb_tap_ram + 1'b1;
            addrb_data_ram <= addrb_data_ram - 1'b1;
          end
        end else begin
          // cnt_data_number >= 12
          if(ap[0] & num_to_dataram & ap_idle) begin 
            enb_tap_ram <= 1'b1;
            enb_data_ram <= 1'b1;
            addrb_tap_ram <= 'b0;
            addrb_data_ram <= addra_data_ram;
          end
          else if(cnt_cycles == exe_times_reqd - 1'b1) begin
            enb_tap_ram <= 1'b0;
            enb_data_ram <= 1'b0;
          end
          else begin
            addrb_tap_ram <= addrb_tap_ram + 1'b1;
            if(addrb_data_ram == 'b0) addrb_data_ram <= 4'd10;
            else addrb_data_ram <= addrb_data_ram - 1'b1;
          end
        end
      end
    end
    
    // how many times to performe addition
    // ap_done
    always @(posedge axis_clk) begin
      if(~axis_rst_n) begin
        cnt_cycles <= 'b0;
        ap_done <= 1'b0;
      end else begin
        if(cnt_cycles == exe_times_reqd + 4'd2) begin
          cnt_cycles <= 'b0; // assume muliplication and addition
          ap_done <= 1'b1;   // both need need 1 cycle
        end 
        else if(~ap_idle) begin 
          cnt_cycles <= cnt_cycles + 1'b1;                          
        end 
        else ap_done <= 1'b0; 
      end
    end
    
    //    
    always @(posedge axis_clk) begin
      mulA <= h;
      //if(ap_idle) mulB <= 'b0;
      //else mulB <= x;
      mulB <= x;
    end 
    
    always @(posedge axis_clk) begin
      //if(ap_idle) addA <= 'b0;
      //else addA <= mulA * mulB;
      if(~axis_rst_n) addA <= 'b0;
      else addA <= mulA * mulB;
    end 
    
    always @(posedge axis_clk) begin
      if(~axis_rst_n) FIRResult <= 'b0;
      else if(cnt_cycles == 4'd2) FIRResult <= 'b0;
      else FIRResult <= FIRResult + addA;
    end 
    
    //---------------Axi-Stream Maseter -------------//
    reg sm_tvalid_r;
    reg [(pDATA_WIDTH-1):0] sm_tdata_r;
    
    assign sm_tlast = 1'b0;
    assign sm_tvalid = sm_tvalid_r;
    assign sm_tdata = sm_tdata_r; 
    
    always @(posedge axis_clk) begin
      if(~axis_rst_n) begin
        sm_tvalid_r <= 1'b0;
        sm_tdata_r <= 32'hffff_ffff;
      end
      else if(ap_done) begin
        sm_tvalid_r <= 1'b1;
        sm_tdata_r <= FIRResult;
      end 
      else if(sm_tready) sm_tvalid_r <= 1'b0;
    end
      
    
    
    

endmodule