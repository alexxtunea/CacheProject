module fsm(
    input clk, rst, bgn,
    input write,
    input read,
    input hit, miss,
    input full,
    output reg c0,c1,c2,c3,c4,c5,c6,c7
);

//FSM States 
parameter IDLE = 4'b0000;
parameter READ = 4'b0001;
parameter WRITE = 4'b0010;
parameter READ_HIT = 4'b0011;
parameter READ_MISS = 4'b0100;
parameter WRITE_HIT = 4'b0101;
parameter WRITE_MISS = 4'b0110;
parameter CHECK = 4'b0111;
parameter EVICT = 4'b1000;
parameter EXIT = 4'b1001;

reg [3:0] st, nxt_st;


always @(posedge clk,negedge rst) begin

    if(rst) begin
        st <= IDLE;
        {c0, c1, c2, c3, c4, c5, c6, c7} <= 8'b0;
    end
    else begin
        st <= nxt_st;
    end

end


always @(*) begin
    nxt_st = st;
    case(st)
        IDLE : begin
            if(bgn == 1'b0)begin
                nxt_st <= IDLE;
            end
            else begin
		if(read == 1'b1) begin
                nxt_st <= READ;
           	end
            	else if(write == 1'b1) begin
                nxt_st <= WRITE;
            	end
            	else begin
                nxt_st <= IDLE;
            	end
	    end     	
        end
        READ : begin
            if(hit == 1'b1) begin
                nxt_st <= READ_HIT;
            end
            else if(miss == 1'b1) begin
                nxt_st <= READ_MISS;
                
            end
        end
        WRITE : begin
            if(hit == 1'b1) begin
                nxt_st <= WRITE_HIT;
            end
            else if(miss == 1'b1) begin
                nxt_st <= WRITE_MISS;
            end
        end
        READ_HIT : begin
            nxt_st <= IDLE;
        end
        WRITE_HIT : begin
            nxt_st <= IDLE;
        end
        WRITE_MISS : begin
            nxt_st <= CHECK;
        end
        READ_MISS : begin
            nxt_st <= CHECK;
        end
        CHECK : begin 
            if(full == 1'b0) begin
                nxt_st <= EXIT;
            end
            if(full == 1'b1) begin
                nxt_st <= EVICT;
            end
        end
        EVICT : begin
            nxt_st <= EXIT;
        end
        EXIT : begin
            nxt_st <= IDLE;
        end

    endcase
end


always @(posedge clk,posedge rst) begin
    {c0, c1, c2, c3, c4, c5, c6, c7} <= 8'b0;

    case(nxt_st)
        IDLE : begin
            c0 <= 1'b1;
        end
        READ : begin
            c1 <= 1'b1;
        end
        WRITE : begin
            c2 <= 1'b1;
        end
        READ_HIT : begin
            c1 <= 1'b1;
            c3 <= 1'b1;
        end
        WRITE_HIT : begin
            c2 <= 1'b1;
            c3 <= 1'b1;
        end
        READ_MISS : begin
            c1 <= 1'b1;
            c4 <= 1'b1;
        end
        WRITE_MISS : begin
            c2 <= 1'b1;
            c4 <= 1'b1;
        end
        CHECK : begin
            c5 <= 1'b1;
        end
        EVICT : begin
            c7 <= 1'b1;
        end
        EXIT : begin
            c6 <= 1'b1;
        end
    endcase
end

endmodule
