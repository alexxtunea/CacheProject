module Cache #(
     parameter CACHE_SIZE = 32768, //32 KB
     parameter BLOCK_SIZE = 64, //64 bytes for each block
     parameter NO_SETS = 128, //numarul de seturi 
     parameter CACHE_TYPE = 4, // 4 way associativity
     parameter WORD_SIZE = 4 //each word has 4 bytes 
)(
     input clk, rst,
     input [31:0] address, data_to_write,
     input read, write,
     output reg [31:0] read_data,
     output reg hit, miss, free
);

parameter NO_BLOCKS = BLOCK_SIZE / WORD_SIZE;
parameter INDEX_BITS = $clog2(NO_SETS);
parameter OFFSET_BITS = $clog2(BLOCK_SIZE);
parameter TAG_BITS = 32 - (INDEX_BITS + OFFSET_BITS);

reg [31:0] data_cache[NO_SETS-1:0][CACHE_TYPE-1:0][BLOCK_SIZE/4-1:0];
reg [TAG_BITS-1:0] tags_cache[NO_SETS-1:0][CACHE_TYPE-1:0];
reg valid[NO_SETS-1:0][CACHE_TYPE-1:0];
reg [1:0] lru[NO_SETS-1:0][CACHE_TYPE-1:0];
reg dirty_bits[NO_SETS-1:0][CACHE_TYPE-1:0];

reg [INDEX_BITS- 1:0] index;
reg [OFFSET_BITS-1:0] offset;
reg [TAG_BITS-1:0] tag;
integer i, j, way_set, br;

parameter IDLE = 3'b000;
parameter READ = 3'b001;
parameter WRITE = 3'b010;
parameter READ_HIT = 3'b011;
parameter READ_MISS = 3'b100;
parameter WRITE_HIT = 3'b101;
parameter WRITE_MISS = 3'b110;
parameter EVICT = 3'b111;

reg [1:0] st, st_next;
reg ok;

always @(posedge clk or posedge rst) begin
        if (rst) begin
            st <= IDLE;
            for (i = 0; i < NO_SETS; i = i + 1) begin
                for (j = 0; j < CACHE_TYPE; j = j + 1) begin
                    valid[i][j] <= 0;
                    dirty_bits[i][j] <= 0;
                    lru[i][j] <= 0;
                end
            end
	    hit <= 0;
            miss <= 0;
	    free <= 1;
        end else begin
            st <= st_next;
        end
end

always @(*) begin
	case(st)
		IDLE: begin
			if(read) st_next = READ;
			else if (write) st_next = WRITE;
			else	st_next = IDLE;
		end
		READ: begin
			index = address[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
			tag = address[31 : 32 - TAG_BITS];
			ok = 0;
			br = 0;
                    	for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                            if (valid[index][i] && tags_cache[index][i] == tag && !br) begin
				ok = 1;
                                way_set = i;
				br = 1;
                            end
                        end
			if(ok == 1) st_next = READ_HIT;
			else st_next = READ_MISS;
		end
		WRITE: begin
			index = address[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
			tag = address[31 : 32 - TAG_BITS];
			ok = 0;
			br = 0;
                    	for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                            if (valid[index][i] && tags_cache[index][i] == tag && !br) begin
				ok = 1;
                                way_set = i;
				br = 1;
                            end
                        end
			if(ok == 1) st_next = WRITE_HIT;
			else st_next = WRITE_MISS;
		end
		READ_HIT: st_next = IDLE;
		READ_MISS: st_next = EVICT;
		WRITE_HIT: st_next = IDLE;
		WRITE_MISS: st_next = READ;
		EVICT: begin
			if(read & !write)      st_next = READ;
			else if(!read & write) st_next = WRITE;
		end
		default: st_next = IDLE;
	endcase
end


always @(posedge clk) begin
	case(st) 
		IDLE: begin
			free <= 1;
			hit <= 0;
			miss <= 0;
		end
		READ_HIT: begin
		    offset = address[OFFSET_BITS-1:0];
                    read_data <= data_cache[index][way_set][offset];
                    hit <= 1;
                    free <= 1;

                    // LRU Update
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (i != way_set && lru[index][i] < lru[index][way_set]) begin
                            lru[index][i] = lru[index][i] + 1;
                        end
                    end
                    lru[index][way_set] = 0;
		end
		READ_MISS: begin
		    miss <= 1;
                    free <= 0;

                    #10;  // Simulate memory fetch delay
		    index = address[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
                    offset = address[OFFSET_BITS-1:0];
                    tag = address[31 : 32 - TAG_BITS];

                    // Find an empty way or LRU way
                    way_set = 0;
		    br = 0;
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (!valid[index][i] && !br) begin
                            way_set = i;
			    br = 1;
                        end
                    end
                    if (i == CACHE_TYPE) begin
                        way_set = 0;
                        for (i = 1; i < CACHE_TYPE; i = i + 1) begin
                            if (lru[index][i] > lru[index][way_set]) begin
                                way_set = i;
                            end
                        end
                    end
                    tags_cache[index][way_set] <= tag;
                    valid[index][way_set] <= 1;
                    dirty_bits[index][way_set] <= 0;
                    for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                        data_cache[index][way_set][j] <= address;  // Dummy memory read
                    end
                    // LRU Update
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (i != way_set && lru[index][i] < lru[index][way_set]) begin
                            lru[index][i] = lru[index][i] + 1;
                        end
                    end
                    lru[index][way_set] = 0;
		end
		WRITE_HIT: begin
		    offset = address[OFFSET_BITS-1:0];
                    data_cache[index][way_set][offset] <= data_to_write;
		    dirty_bits[index][way_set] <= 1;
                    hit <= 1;
                    free <= 1;

                    // LRU Update
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (i != way_set && lru[index][i] < lru[index][way_set]) begin
                            lru[index][i] = lru[index][i] + 1;
                        end
                    end
                    lru[index][way_set] = 0;
		end
		WRITE_MISS: begin
	            miss <= 1;
                    free <= 0;

                    #10;  // Simulate memory fetch delay
		    index = address[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
                    offset = address[OFFSET_BITS-1:0];
                    tag = address[31 : 32 - TAG_BITS];

                    // Find an empty way or LRU way
                    way_set = 0;
		    br = 0;
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (!valid[index][i] && !br) begin
                            way_set = i;
			    br = 1;
                        end
                    end
                    if (i == CACHE_TYPE) begin
                        way_set = 0;
                        for (i = 1; i < CACHE_TYPE; i = i + 1) begin
                            if (lru[index][i] > lru[index][way_set]) begin
                                way_set = i;
                            end
                        end
                    end
                    tags_cache[index][way_set] <= tag;
                    valid[index][way_set] <= 1;
                    dirty_bits[index][way_set] <= 0;
                    for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                        data_cache[index][way_set][j] <= address;  // Dummy memory read
                    end

		    //Write data to cache 
	            data_cache[index][way_set][offset] <= data_to_write;
		    dirty_bits[index][way_set] <= 1;
		    
                    // LRU Update
                    for (i = 0; i < CACHE_TYPE; i = i + 1) begin
                        if (i != way_set && lru[index][i] < lru[index][way_set]) begin
                            lru[index][i] = lru[index][i] + 1;
                        end
                    end
                    lru[index][way_set] = 0;
		end
		EVICT: begin
	            free <= 0;
                    index = address[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
                    tag = address[31 : 32 - TAG_BITS];

                    // Find LRU way
                    way_set = 0;
                    for (i = 1; i < CACHE_TYPE; i = i + 1) begin
                        if (lru[index][i] > lru[index][way_set]) begin
                            way_set = i;
                        end
                    end
                    if (dirty_bits[index][way_set]) begin
                        #10;  // Simulate memory write-back delay
                        for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                            // Dummy memory write
                        end
                    end
                    valid[index][way_set] <= 0;
                    dirty_bits[index][way_set] <= 0;
		end
	endcase
end
endmodule

module Cache_tb;
    reg clk, rst;
    reg [31:0] address;
    reg [31:0] data_to_write;
    reg read;
    reg write;
    wire [31:0] read_data;
    wire hit;
    wire miss;
    wire free;

    Cache uut (
        .clk(clk),
        .rst(rst),
        .address(address),
        .data_to_write(data_to_write),
        .read(read),
        .write(write),
        .read_data(read_data),
        .hit(hit),
        .miss(miss),
        .free(free)
    );

    initial begin
        clk = 0;
        rst = 1;
        #10 rst = 0;

        // Read miss case
        read = 1;
        write = 0;
        address = 32'h0000_0000;
        #20;

        // Read hit case
        read = 1;
        write = 0;
        address = 32'h0000_0000;
        #20;

        // Write miss case
        read = 0;
        write = 1;
        address = 32'h0000_0004;
        data_to_write = 32'hDEAD_BEEF;
        #20;

        // Write hit case
        read = 0;
        write = 1;
        address = 32'h0000_0004;
        data_to_write = 32'hCAFE_BABE;
        #20;
    end

    always #5 clk = ~clk;
endmodule


