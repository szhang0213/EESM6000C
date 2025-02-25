module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 32,
    parameter POINTER_WIDTH = $clog2(DEPTH)
) (
    input clk, rst,

    // Write side
    input wr_en,
    input [WIDTH-1:0] din,
    output full,

    // Read side
    input rd_en,
    output [WIDTH-1:0] dout,
    output empty
);
    reg empty_r = 0, full_r = 0;
    reg [WIDTH-1:0] dout_r = 0;
    reg [POINTER_WIDTH-1:0] wr_ptr = 0;
    reg [POINTER_WIDTH-1:0] rd_ptr = 0;
    reg [POINTER_WIDTH:0] empty_cnt = 0; // count the number of empty sites in memory
    reg [WIDTH-1:0] MEM [DEPTH-1:0];
    
    assign full = full_r;
    assign empty = empty_r;
    assign dout = dout_r;

    // initalize MEM
    integer k;
    initial begin
        for (k = 0; k < WIDTH; k = k + 1) begin
            MEM[k] = 0;
        end
    end
    
    // full_r, empty_r
    always @(posedge clk) begin
        if(rst) begin
            empty_r <= 1'b1;
            full_r <= 1'b0;
            empty_cnt <= DEPTH; // the whole MEM is empty
        end
        else begin
            empty_r <= (empty_cnt==DEPTH)&(~wr_en) | (empty_cnt==DEPTH-1)&rd_en&(~wr_en); // if emptty == DEPTH-1, but read and write concurrently, fifo is not empty
            full_r <= (empty_cnt==0)&(~rd_en) | (empty_cnt==1)&wr_en;
        end
    end
    

    
    always @(posedge clk) begin
        if(rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0; 
        end
        else begin
            if((empty_cnt == 0) & ~rd_en) begin
                wr_ptr <= rd_ptr;
            end
            else if(wr_en & ~rd_en) begin  // write only
                wr_ptr <= wr_ptr + 1;
                empty_cnt <= empty_cnt - 1; 
                MEM[wr_ptr] <= din;
            end
            else if((empty_cnt != DEPTH) & rd_en & ~wr_en) begin // read only
                rd_ptr <= rd_ptr + 1;
                empty_cnt <= empty_cnt + 1;
                dout_r <= MEM[rd_ptr];
            end
            else if (wr_en & rd_en) begin // write and read concurrently
                wr_ptr <= wr_ptr + 1;
                rd_ptr <= rd_ptr + 1;
                MEM[wr_ptr] <= din;
                dout_r <= MEM[rd_ptr];
            end
        end
    end
      

endmodule
