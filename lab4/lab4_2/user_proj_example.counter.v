// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);

    parameter pADDR_WIDTH = 12;
    parameter pDATA_WIDTH = 32;
    parameter Tape_Num    = 11;
    
    wire clk;
    wire rst;

        
//-----------------------------------------------------
//------------------- Variables -----------------------
//-----------------------------------------------------
    
    // wishbone
    wire wishbone_valid;
    wire [3:0] wstrb;
    
    reg [3:0] cnt_delay;

    // user bram
    wire [3:0] user_bram_wen;
    wire user_bram_en;
    wire [31:0] user_bram_Di;
    wire [31:0] user_bram_Do; // ??????????????????????
    wire [31:0] user_bram_A;  



    // lab3 interface
    wire awready;
    wire wready;
    wire awvalid;
    wire [(pADDR_WIDTH-1):0] awaddr;
    wire wvalid;
    wire [(pDATA_WIDTH-1):0] wdata;
    wire arready;
    wire rready;
    wire arvalid;
    wire [(pADDR_WIDTH-1):0] araddr;
    wire rvalid;
    wire [(pDATA_WIDTH-1):0] rdata;
    wire ss_tvalid;
    wire [(pDATA_WIDTH-1):0] ss_tdata;
    wire ss_tlast;
    wire ss_tready;
    wire sm_tready;
    wire sm_tvalid;
    wire [(pDATA_WIDTH-1):0] sm_tdata;
    wire sm_tlast;
    wire [3:0] tap_WE;
    wire tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;
    wire [3:0] data_WE;
    wire data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;
    wire axis_clk;
    wire axis_rst_n;
    

//--------------------------------------------------------
//--------------------- Operations -----------------------
//--------------------------------------------------------
//
    // clk & rst
    assign clk        = wb_clk_i;
    assign rst        = wb_rst_i;
    assign axis_clk   = clk;
    assign axis_rst_n = ~rst;

    // wishbone
    assign wishbone_valid = (wbs_stb_i && wbs_cyc_i);
    assign wstrb          = wbs_sel_i & {4{wbs_we_i}};
    assign wbs_ack_o      = (cnt_delay == (DELAYS - 1)); // ?????????????

    //// count delays
    always @(posedge clk) begin
    	if(rst) begin
    		cnt_delay <= 'b0;
    	end else if(valid && (cnt_delay < DELAYS)) begin
    		cnt_delay <= cnt_delay + 1;
    	end else begin
    		cnt_delay <= 'b0;
    	end
    end
    
    //------------------------------------------------------------------
    //---------------------------- user bram ---------------------------
    //------------------------------------------------------------------
    assign user_bram_en  = (wishbone_valid && (wbs_adr_i[31:24] == 8'h38));
    assign user_bram_wen = wstrb;
    assign user_bram_Di  = wbs_dat_i;
    assign user_bram_A   = wbs_adr_i;
    
    bram user_bram (
        .CLK(clk),
        .WE0(user_bram_wen),
        .EN0(user_bram_en),
        .Di0(user_bram_Di),
        .Do0(user_bram_Do),
        .A0 (user_bram_A)
    );
        
    //-------------------------------------------------------------------
    //--------------------------- WB --> AXI ----------------------------
    //-------------------------------------------------------------------
    wire is_access_axi;
    wire is_config_x;
    wire is_access_y;
    

    assign is_access_axi  = (wishbone_valid && (wbs_adr_i[31:24] == 8'h30));
    assign is_config_x    = is_access_axi && (wbs_adr_i[7:0] == 8'h40);
    assign is_access_y    = is_access_axi && (wbs_adr_i[7:0] == 8'h44);
    assign is_access_lite = is_access_axi && (~is_config_x) && (is_access_y);

    //-------------------------- WB --> AXI-L ---------------------------
    wire access_lite_wr;
    wire access_lite_rd;
    reg [3:0] cnt_val_deassert_awvld;

    assign access_lite_wr = is_access_lite && wbs_we_i;
    assign access_lite_rd = is_access_lite && (~wbs_we_i);

    // awaddr & awvalid
    always @(posedge clk) begin
      if(~axis_rst_n) begin
        awaddr                 <= 'b0;
        awvalid                <= 'b0;
        cnt_val_deassert_awvld <= 'b0;
      end else if(access_lite_wr) begin 
        awaddr  <= wbs_adr_i[pADDR_WIDTH-1 : 0];
        if((awvalid && awready) || (cnt_delay > cnt_val_deassert_awvld )) begin
          awvalid                <= 1'b0;
          cnt_val_deassert_awvld <= cnt_delay;
        end else
          awvalid <= 1'b1;
      end else begin
        awvalid <= 1'b0;
      end
    end
    
    // wdata & wvalid
    always @(posedge clk) begin
      if(~axis_rst_n) begin
        wdata <= 'b0;
        wvalid <= 'b0;
      end else if(access_lite_rd) begin
        wdata <= wbs_dat_i;
        if((wvalid && wready) || (cnt_delay > cnt_val_deassert_awvld)) begin
          wvalid <= 1'b0;
        end else 
          wvalid <= 1'b1;
        end
      end else begin
        wvalid <= 1'b0;
      end
    end

    // araddr & arvalid
    always @(posedge clk) begin
      if(~axis_rst_n) begin
        araddr <= 'b0;
        arvalid <= 'b0;
      end else if(access_lite_rd) begin
        araddr <= wbs_adr_i[pADDR_WIDTH-1 : 0];
        if((arvalid && rready) || (cnt_delay > cnt_val_deassert_awvld)) begin
          arvalid <= 1'b0;
        end else begin
          arvalid <= 1'b1;
        end
      end else begin
        arvalid <= 1'b0;
      end
    end


        

    //-------------------------- WB --> AXI-S -------------------------------
    
    // config x
    //// ss_tlast
    assign ss_tlast = 1'b0;
    
    //// ss_tvalid & ss_tdata
    always @(posedge clk) begin
      if(~axis_rst_n) begin
        ss_tvalid <= 1'b0;
        ss_tdata <= 'b0;
      end else if(is_config_x) begin
        ss_tdata <= wbs_dat_i;
        if((ss_tvalid && ss_tready) || (cnt_delay > cnt_val_deassert_awvld)) begin
          ss_tvalid <= 1'b0;
        end else begin
          ss_tvalid <= 1'b1;
        end
      end else begin
        ss_tvalid <= 1'b0;
      end
    end

    // read y
    always @(posedge clk) begin
      if(~axis_rst_n) begin
        sm_tready <= 1'b0;
      end else if(is_access_y) begin
        if((sm_tready && sm_tvalid) || (cnt_delay > cnt_val_deassert_awvld)) begin
          sm_tready <= 1'b0;
        end else begin
          sm_tready <= 1'b1;
        end
      end else begin
        sm_tready <= 1'b0;
      end
    end



    
    

   
endmodule



`default_nettype wire
