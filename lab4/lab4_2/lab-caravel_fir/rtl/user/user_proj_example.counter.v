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
 
 //THIS CODE IS FOR LAB4-2

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
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

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
    wire [`MPRJ_IO_PADS-1:0] io_in;
    wire [`MPRJ_IO_PADS-1:0] io_out;
    wire [`MPRJ_IO_PADS-1:0] io_oeb;
    wire Wishbone_valid;

    //Lab 4-2 FIR Engine AXI-Interface
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

    //clk & rst
    assign clk = wb_clk_i;
    assign rst = wb_rst_i;
    assign axis_clk = clk;
    assign axis_rst_n = ~rst;

    //Block RAM
    wire [3:0] BRAM_WE;
    wire [31:0] BRAM_Di0;
    wire [31:0] BRAM_Do0;
    wire [31:0] BRAM_A0;
    wire BRAM_EN0;
    reg [3:0] delay_cnt;
    wire Access_BRAM_Flag;

    //Wishbone-AXI Interface
    wire Access_FIR_Flag;
    wire [(pADDR_WIDTH-1):0] AXI_address;
    reg [(pADDR_WIDTH-1):0] addr_w,addr_r;
    reg ss_tvalid_w,sm_tready_w;
    reg rready_w,arvalid_w;
    reg awvalid_w,wvalid_w;
    reg ss_tvalid_r,sm_tready_r;
    reg rready_r,arvalid_r;
    reg awvalid_r,wvalid_r;
    wire Access_AXI_Stream;

    assign Wishbone_valid = wbs_stb_i && wbs_cyc_i;
    assign Access_FIR_Flag = wbs_adr_i >= 32'h3000_0000 && wbs_adr_i < 32'h3800_0000;
    assign AXI_address = wbs_adr_i - 32'h3000_0000;
    assign Access_AXI_Stream = AXI_address[7:0] >= 8'h80;
    
    
    //Combinational part
    always@(*) begin
        ss_tvalid_w = 1'b0;
        sm_tready_w = 1'b0;
        awvalid_w = 1'b0;
        wvalid_w = 1'b0;
        rready_w = 1'b0;
        arvalid_w = 1'b0;
        addr_w = addr_r;
        if(Wishbone_valid && Access_FIR_Flag) begin
            if(Access_AXI_Stream) begin //AXI_Stream
                case(AXI_address[7:0])
                    8'h80:begin
                        if(!(ss_tvalid && ss_tready) && !wbs_ack_o)
                            ss_tvalid_w = 1'b1;
                    end
                    8'h84: begin
                        if(!(sm_tvalid && sm_tready) && !wbs_ack_o)
                            sm_tready_w = 1'b1;
                    end
                endcase
            end
            else begin //AXI-Lite
                addr_w = AXI_address;
                if(wbs_we_i) begin
                    if(!wbs_ack_o && !(awvalid && awready) && !(wvalid && wready)) begin
                        awvalid_w = 1'b1;
                        wvalid_w = 1'b1;
                    end
                    else begin
                        awvalid_w = 1'b0;
                        wvalid_w = 1'b0;
                    end
                end
                else begin
                    if(!wbs_ack_o && !(rready && rvalid) && !(arready && arvalid)) begin
                        rready_w = 1'b1;
                        arvalid_w = 1'b1;
                    end
                    else begin
                        rready_w = 1'b0;
                        arvalid_w = 1'b0;
                    end
                end
            end
        end
    end

    always@(posedge clk) begin //Don't know whether The data should be buffered into the register
        if(rst) begin
            ss_tvalid_r <=  1'b0;
            sm_tready_r <= 1'b0;
            rready_r <= 1'b0;
            arvalid_r <= 1'b0;
            awvalid_r <= 1'b0;
            wvalid_r <= 1'b0;
            addr_r <= 0;
        end
        else begin
            ss_tvalid_r <=  ss_tvalid_w;
            sm_tready_r <= sm_tready_w;
            rready_r <= rready_w;
            arvalid_r <= arvalid_w;
            awvalid_r <= awvalid_w;
            wvalid_r <= wvalid_w;
            addr_r <= addr_w;
        end
    end

    //Synchronous assignment to AXI protocal
    assign ss_tvalid = ss_tvalid_r;
    assign sm_tready = sm_tready_r;
    assign ss_tdata = wbs_dat_i;
    assign rready = rready_r;
    assign arvalid = arvalid_r;
    assign awvalid = awvalid_r;
    assign wvalid = wvalid_r;
    assign awaddr = addr_r;
    assign araddr = addr_r;
    assign wdata = wbs_dat_i;

    //Address Decoding
    assign Access_BRAM_Flag = wbs_adr_i >= 32'h3800_0000 && wbs_adr_i < 32'h3840_0000;
    assign BRAM_A0 = (Access_BRAM_Flag) ? ((wbs_adr_i - 32'h3800_0000) >> 2): 0;
    assign BRAM_WE = (Access_BRAM_Flag && Wishbone_valid && wbs_we_i) ? 4'b1111 : 4'b0000;
    assign BRAM_Di0 = wbs_dat_i;
    assign BRAM_EN0 = Wishbone_valid;

    //Wishbone output
    always@(posedge clk) begin
        if(rst)
            delay_cnt <= 0;
        else if(delay_cnt == 10)
            delay_cnt <= 0;
        else if(Wishbone_valid && !wbs_we_i) //read operation
            delay_cnt <= delay_cnt + 1;
    end

    //Synchronous output Transfer
    always@(posedge clk) begin
        if(rst)
            wbs_ack_o <= 1'b0;
        else begin
            if(Wishbone_valid) begin
                if(Access_BRAM_Flag) begin
                    if(wbs_we_i) begin
                        if(wbs_ack_o)
                            wbs_ack_o <= 1'b0;
                        else 
                            wbs_ack_o <= 1'b1;
                    end
                    else if(delay_cnt == 10)
                        wbs_ack_o <= 1'b1;
                    else
                        wbs_ack_o <= 1'b0;
                end
                else if(Access_FIR_Flag) begin
                    if((wready && wvalid) || (rready && rvalid) || (sm_tready && sm_tvalid) ||(ss_tready && ss_tvalid))
                        wbs_ack_o <= 1'b1;
                    else
                        wbs_ack_o <= 1'b0;
                end
                else
                    wbs_ack_o <= 1'b0;
            end
            else
                wbs_ack_o <= 1'b0;
        end
    end

    //Wishbone data output Selector
    /*
    always@(*) begin
        wbs_dat_o = 32'd0;
        if(Access_BRAM_Flag)
            wbs_dat_o = BRAM_Do0;
        else if(Access_FIR_Flag) begin
            if(AXI_address[7:0] >=  8'h80)
                wbs_dat_o = sm_tdata; //From AXI-Stream
            else
                wbs_dat_o = rdata; //From AXI-Lite
        end
    end
    */
    always@(posedge clk) begin
        if(rst)
            wbs_dat_o <= 32'd0;
        else begin
            if(Access_BRAM_Flag)
                wbs_dat_o <= BRAM_Do0;
            else if(Access_FIR_Flag) begin
                if(AXI_address[7:0] >=  8'h80)
                    wbs_dat_o <= sm_tdata; //From AXI-Stream
                else
                    wbs_dat_o <= rdata; //From AXI-Lite
            end
        end
    end


    //Lab 4-2 FIR Engine
    fir u0_fir(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),
        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),
        .ss_tvalid(ss_tvalid), 
        .ss_tdata(ss_tdata), 
        .ss_tlast(ss_tlast), 
        .ss_tready(ss_tready),
        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), 
        .sm_tdata(sm_tdata), 
        .sm_tlast(sm_tlast), 
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),
        .axis_clk(axis_clk),
        .axis_rst_n(axis_rst_n)
    );

    //Lab 4-1 BRAM
    bram User_bram (
        .CLK(clk),
        .WE0(BRAM_WE),
        .EN0(BRAM_EN0),
        .Di0(BRAM_Di0),
        .Do0(BRAM_Do0),
        .A0(BRAM_A0)
    );

    //Lab 4-2 TAP BRAM
    bram11 Tap_bram (
        .CLK(clk),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .Do(tap_Do),
        .A(tap_A)
    );

    //Lab 4-2 DATA BRAM
    bram11 Data_bram (
        .CLK(clk),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .Do(data_Do),
        .A(data_A)
    );
endmodule

`default_nettype wire
