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


  localparam READ_AP = 2'b00;
  localparam READ_DATA_LEN = 2'b10;
  localparam READ_TAP_NUM = 2'b11;
  
  // FIR FSM Control
  localparam IDLE = 2'b00;
  localparam CALC = 2'b01;
  localparam STALL = 2'b10;
  
  //----------------------------------------------------
  //------------------- Variables ----------------------
  //----------------------------------------------------  
  
  // AXI-Lite
  //// Write Interface
  reg awready_r;
  reg wready_r;
  
  wire handshake_wr;
  
  wire is_awaddr_ap;          // awaddr for confiduring ap_start
  wire is_awaddr_data_length; // awaddr for configuring data length
  wire is_awaddr_tap_num;     // awaddr for configuring tap numbers
  wire is_awaddr_tap;         // awaddr for configuring tap ram
  
  reg [(pADDR_WIDTH-1):0] awaddr_valid; // sample awaddr when handshake occurs
  reg [(pDATA_WIDTH-1):0] wdata_valid;  // sample wdata when handshake occurs
  
  reg [(pDATA_WIDTH-1):0] ap;
  reg [(pDATA_WIDTH-1):0] data_length; // receive data length
  reg [(pDATA_WIDTH-1):0] tap_num;     // receive tap numbers
  
  
  //// Read Interface
  reg rvalid_r;
  reg arready_r;
  
  reg [(pDATA_WIDTH-1):0] rdata_r;
  
  wire handshake_rd;
  
  wire is_addr_ap;            // araddr for readfing from ap
  wire is_araddr_data_length; // araddr for reading from data_length
  wire is_araddr_tap_num;     // araddr for reading from tap_num
  wire is_araddr_tap;         // araddr for reading from tap ram
  
  reg [(pADDR_WIDTH-1):0] araddr_valid; // sample araddr when handshake occurs
  
  reg [(pDATA_WIDTH-1):0] rdata_valid;  // the data need transfer to axi_stream_master
  wire [(pDATA_WIDTH-1):0] rdata_valid_tap; // data read from tap ram
  
  
  // AXI-Stream Slave
  wire [(pDATA_WIDTH-1):0] ss_tdata_valid;
  
  wire ss_handshake;
  
  reg ss_has_trans_one_data;
  reg [(pDATA_WIDTH-1):0] ss_recv_tdata_num;
  
  // AXI_Stream Master
  reg sm_tvalid_r;
  reg [(pDATA_WIDTH-1):0] sm_tdata_r;
  
  
  // FIR Engine
  //// FSM Control
  reg ap_idle;
  wire fir_start;
  reg ap_done;
  reg [1:0] current_state, next_state;
  
  reg Stall;
  
  //// Calculate
  reg [(pDATA_WIDTH-1):0] mult_A, mult_B;
  wire [(pDATA_WIDTH-1):0] product;
  reg [(pDATA_WIDTH-1):0] adder_A;
  wire [(pDATA_WIDTH-1):0] sum;
  reg [(pDATA_WIDTH-1):0] fir_result;
  
  
  // Address Generator
  reg [(pADDR_WIDTH-1):0] fir_rd_tap_addr;
  wire [(pADDR_WIDTH-1):0] fir_rd_tap_addr_max; // It indicates the maximum tap address FIR can read
  reg [(pADDR_WIDTH-1):0] fir_rd_data_addr;
  reg [(pADDR_WIDTH-1):0] ss_wr_data_addr;
  
  // Tap RAM
  wire is_write_to_tap; // It indicates AXI-Lite writes to tap_ram or not
  wire [(pADDR_WIDTH-1):0] tap_addr_wr; // address for writing to tap ram
  wire [(pADDR_WIDTH-1):0] tap_addr_rd; // address for reading from tap ram
  
  
  // Data RAM
  wire [(pADDR_WIDTH-1):0] data_addr_wr;
  wire [(pADDR_WIDTH-1):0] data_addr_rd;
  
    
  //----------------------------------------------------
  //------------------- AXI-Lite -----------------------
  //----------------------------------------------------
  
  assign awready = awready_r;
  assign wready = wready_r;
  
  // Write interface
  //// write-address
  always @(posedge axis_clk) begin
    if(~axis_rst_n) begin
      awready_r <= 1'b0;
    end else if(awvalid & (~awready_r)) begin
      awready_r <= 1'b1;
      awaddr_valid <= awaddr;
    end else if(awvalid & awready_r) begin // awready is set to '1' for one cycle
      awready_r <= 1'b0;
    end
  end
  
  //// write-data
  always @(posedge axis_clk) begin
    if(~axis_rst_n) begin
      wready_r <= 1'b0;
    end else if(wvalid & (~wready_r)) begin
      wready_r <= 1'b1;
      wdata_valid <= wdata;
    end else if(wvalid & wready_r) begin // wready is set to '1' for one cycle
      wready_r <= 1'b0;
    end
  end
  
  assign handshake_wr = wvalid & wready_r & ap_idle;
  
  assign is_awaddr_ap = ({awaddr_valid[6], awaddr_valid[4], awaddr_valid[2]} == 3'b0);
  assign is_awaddr_data_length = ({awaddr_valid[6], awaddr_valid[4], awaddr_valid[2]} == 3'b010);
  assign is_awaddr_tap_num = ({awaddr_valid[6], awaddr_valid[4], awaddr_valid[2]} == 3'b011);
  assign is_awaddr_tap = awaddr_valid[6];
  
  ///// write to registers
  always @(posedge axis_clk) begin
    if(~axis_rst_n) begin
      ap <= 'b0;
    end else if(handshake_wr) begin
      if(is_awaddr_data_length) data_length <= wdata_valid;
      if(is_awaddr_tap_num) tap_num <= wdata_valid;
      if(is_awaddr_ap) ap <= wdata_valid;
     end
  end
  
  // Read interface
  assign rvalid = rvalid_r;
  assign arready = arready_r;
  assign rdata = rdata_r;
  
  assign handshake_rd = arready & arvalid;
  
  // arready
  always @(posedge axis_clk) begin
    if(~axis_rst_n) begin
      arready_r <= 1'b0;
    end else if(arvalid & (~arready_r)) begin
      arready_r <= 1'b1;
      araddr_valid <= araddr;
    end else if(arvalid & arready_r) begin
      arready_r <= 1'b0;
    end
  end
  
  // rdata_valid
  assign rdata_valid_tap = ap_idle ? tap_Do : 32'hffffffff;
  
  always @(*) begin
    case(araddr_valid[6])
      1'b0: begin
        case({araddr_valid[4], araddr_valid[2]})
          READ_AP: rdata_valid = {30'b0, ap_done, fir_start};
          READ_DATA_LEN: rdata_valid = data_length;
          READ_TAP_NUM: rdata_valid = tap_num;
          default: rdata_valid = 32'hffffffff;
        endcase
      end
      1'b1: rdata_valid = rdata_valid_tap;
    endcase
  end
         
  // rvalid & rdata
  always @(posedge axis_clk) begin
    if(~axis_rst_n) begin
      rvalid_r <= 1'b0;
    end else if(handshake_rd) begin
      rvalid_r <= 1'b1;
      rdata_r <= rdata_valid;
    end else if(rvalid & rready) begin
      rvalid_r <= 1'b0;
    end
  end


  //----------------------------------------------------
  //---------------- AXI-Stream Slave ------------------
  //----------------------------------------------------
  
  // ss_has_trans_one_data
  always @(posedge axis_clk) begin
    if(~axis_rst_n | fir_start)
      ss_has_trans_one_data <= 1'b0;
    else if(ss_handshake)
      ss_has_trans_one_data <= 1'b1;
  end
      
  
  // ss_tready
  assign ss_tready = ap_idle & (~ss_has_trans_one_data);
  
  // ss_handshake
  assign ss_handshake = ss_tvalid & ss_tready;
  
  // sample ss_tdata
  assign ss_tdata_valid = ss_handshake ? ss_tdata : 'b0;
  
  // ss_recv_data_num
  always @(posedge axis_clk) begin
    if(~axis_rst_n)
      ss_recv_tdata_num <= 'b0;
    else if(ss_handshake)
      ss_recv_tdata_num <= ss_recv_tdata_num + 1;
  end
  
  
  
  //----------------------------------------------------
  //------------------- FIR-Engine ---------------------
  //----------------------------------------------------
  
  // fir_start
  assign fir_start = ap[0] & ap_idle & ss_has_trans_one_data;
  
  // fir_rd_tap_addr_max;
  assign fir_rd_tap_addr_max = (ss_recv_tdata_num > 11) ? 40 : 4 * (ss_recv_tdata_num - 1) ;
                               
  
  // FSM Control
  //// States transfer
  always @(posedge axis_clk) begin
    if(~axis_rst_n) current_state <= IDLE;
    else current_state <= next_state;
  end
  
  //// Conditions for states transition
  always @(*) begin
    case(current_state)
      IDLE: begin
        ap_idle = 1'b1;
        ap_done = 1'b0;
        Stall = 1'b0;
        case(fir_start)
          1'b0: next_state = IDLE;
          1'b1: next_state = CALC;
        endcase
      end
      CALC: begin
        ap_idle = 1'b0;
        ap_done = 1'b0;
        Stall = 1'b0;
        case(fir_rd_tap_addr == fir_rd_tap_addr_max)
          1'b0: next_state = CALC;
          1'b1: next_state = STALL;
        endcase
      end
      STALL: begin
        ap_idle = 1'b0;
        ap_done = 1'b1;
        case(sm_tready)
          1'b0: begin
            Stall = 1'b1;
            next_state = STALL;
          end
          1'b1: begin
            Stall = 1'b0;
            next_state = IDLE;
          end
        endcase
      end  
      default: begin
        ap_idle = 1'b0;
        ap_done = 1'b0;
        Stall = 1'b0;
        next_state = IDLE;
      end
    endcase
  end
  
  
  // Calculate
  assign product = mult_A * mult_B;
  assign sum = adder_A + fir_result;
  
  //// calculate
  always @(posedge axis_clk) begin
    if(ap_idle) begin
      mult_A <= 'b0;
      mult_B <= 'b0;
      adder_A <= 'b0;
      fir_result <= 'b0;
    end else begin
      mult_A <= tap_Do;
      mult_B <= data_Do;
      adder_A <= product;
      if(~Stall) 
        fir_result <= sum;
    end   
  end
  
  reg one_more_cycle;
  always @(posedge axis_clk) begin
    if(ap_done) begin
      one_more_cycle <= 1'b1;
    end else begin
      one_more_cycle <= 1'b0;
    end
  end  
  


  //----------------------------------------------------
  //--------------- AXI_Stream Master -----------------
  //----------------------------------------------------
  
  // sm_tvalid
  assign sm_tvalid = sm_tvalid_r;
  always @(posedge axis_clk) begin
    if(one_more_cycle) begin
      sm_tvalid_r <= 1'b1;
     end else begin
      sm_tvalid_r <= 1'b0;
     end
  end
  
  // sm_tdata
  assign sm_tdata = sm_tdata_r;
  always @(posedge axis_clk) begin
    if(one_more_cycle)
      sm_tdata_r <= (product + sum);
  end
  
  
  //----------------------------------------------------
  //------------------- Tap RAM ------------------------
  //----------------------------------------------------
  assign tap_EN = 1'b1;
  assign is_write_to_tap = handshake_wr &        // Handshake occurs ,awaddr is in 0x40-0x7f,
                           is_awaddr_tap; // can write to tap_ram
                            
  assign tap_WE = is_write_to_tap ? 4'b1111: 4'b0;
  assign tap_Di = wdata_valid;
  assign tap_addr_wr = awaddr_valid;
  assign tap_addr_rd = ap_idle ? araddr : fir_rd_tap_addr;
  assign tap_A = handshake_wr ? tap_addr_wr : tap_addr_rd;
  
  
  //----------------------------------------------------
  //------------------- Data RAM ------------------------
  //----------------------------------------------------  
  assign data_EN = 1'b1;
  assign data_WE = (ap_idle & ss_handshake) ? 4'hf : 4'b0;
  assign data_Di = ss_tdata_valid;
  assign data_A = ss_handshake ? ss_wr_data_addr : fir_rd_data_addr;
  
  
  //----------------------------------------------------
  //--------------- Address Generator ------------------
  //---------------------------------------------------- 
  
  // ss_wr_data_addr
  always @(posedge axis_clk) begin
    if(~axis_rst_n)
      ss_wr_data_addr <= 'b0;
    else if(ss_handshake) begin
      if(ss_wr_data_addr == 40)
        ss_wr_data_addr <= 'b0;
      else
        ss_wr_data_addr <= ss_wr_data_addr + 4;
    end
  end
  
  // fir_rd_tap_addr  
  always @(posedge axis_clk) begin
    if(~axis_rst_n | ap_idle)
      fir_rd_tap_addr <= 'b0;
    else if(~ap_idle) begin
      if(fir_rd_tap_addr == fir_rd_tap_addr_max)
        fir_rd_tap_addr <= 'b0;
      else
        fir_rd_tap_addr <= fir_rd_tap_addr + 4;
    end
  end
  
  // fir_rd_data_addr
  always @(posedge axis_clk) begin
    if(ap_idle) begin
      if(ss_wr_data_addr == 'b0) begin
        fir_rd_data_addr <= 40;
      end else begin
        fir_rd_data_addr <= ss_wr_data_addr - 4;
      end
    end else begin
      if(fir_rd_data_addr == 'b0)
        fir_rd_data_addr <= 40;
      else
        fir_rd_data_addr <= fir_rd_data_addr - 4;
    end
  end 
   
endmodule