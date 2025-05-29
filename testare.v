module testare (
    input wire clk,
    input wire reset,
    input wire [31:0] address,
    input wire [31:0] write_data,
    input wire read,
    input wire write,
    output reg [31:0] read_data,
    output reg hit,
    output reg miss,
    output reg busy
);

    parameter CACHE_SIZE = 32768;  // 32 KB
    parameter BLOCK_SIZE = 64;     // 64 bytes
    parameter NUM_SETS = 128;      // Number of sets
    parameter ASSOCIATIVITY = 4;   // 4-way set associative

    parameter NUM_BLOCKS = CACHE_SIZE / BLOCK_SIZE;
    parameter INDEX_BITS = $clog2(NUM_SETS);
    parameter OFFSET_BITS = $clog2(BLOCK_SIZE);
    parameter TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    parameter IDLE = 3'd0;
    parameter READ_HIT = 3'd1;
    parameter READ_MISS = 3'd2;
    parameter WRITE_HIT = 3'd3;
    parameter WRITE_MISS = 3'd4;
    parameter EVICT = 3'd5;



reg [2:0] state, next_state;

    reg [31:0] cache_data [0:NUM_SETS-1][0:ASSOCIATIVITY-1][0:BLOCK_SIZE/4-1];
    reg [TAG_BITS-1:0] cache_tags [0:NUM_SETS-1][0:ASSOCIATIVITY-1];
    reg valid [0:NUM_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_counter [0:NUM_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty [0:NUM_SETS-1][0:ASSOCIATIVITY-1];

    reg [INDEX_BITS-1:0] index;
    reg [OFFSET_BITS-1:0] offset;
    reg [TAG_BITS-1:0] tag;
    integer i, j, way, ok;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        case (state)
            IDLE: begin
                if (read) begin
                    index = address[OFFSET_BITS +: INDEX_BITS];
                    tag = address[31 -: TAG_BITS];
                    next_state = IDLE;
		    ok = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (valid[index][i] && cache_tags[index][i] == tag && !ok) begin
                            next_state = READ_HIT;
                            way = i;
                            ok = 1;
                        end
                    end
                    if (next_state == IDLE) next_state = READ_MISS;
                end else if (write) begin
                    index = address[OFFSET_BITS +: INDEX_BITS];
                    tag = address[31 -: TAG_BITS];
                    next_state = IDLE;
		    ok = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (valid[index][i] && cache_tags[index][i] == tag && !ok) begin
                            next_state = WRITE_HIT;
                            way = i;
                            ok=1;
                        end
                    end
                    if (next_state == IDLE) next_state = WRITE_MISS;
                end else begin
                    next_state = IDLE;
                end
            end
            READ_HIT: next_state = IDLE;
            READ_MISS: next_state = EVICT;
            WRITE_HIT: next_state = IDLE;
            WRITE_MISS: next_state = EVICT;
            EVICT: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid[i][j] <= 0;
                    dirty[i][j] <= 0;
                    lru_counter[i][j] <= 0;
                end
            end
            busy <= 0;
            hit <= 0;
            miss <= 0;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 0;
                    hit <= 0;
                    miss <= 0;
                end
                READ_HIT: begin
                    offset = address[OFFSET_BITS-1:0];
                    read_data <= cache_data[index][way][offset];
                    hit <= 1;
                    busy <= 0;
                    // LRU Update
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (i != way && lru_counter[index][i] < lru_counter[index][way]) begin
                            lru_counter[index][i] = lru_counter[index][i] + 1;
                        end
                    end
                    lru_counter[index][way] = 0;
                end
                READ_MISS: begin
                    miss <= 1;
                    busy <= 1;
                    #10;  // Simulate memory fetch delay
                    index = address[OFFSET_BITS +: INDEX_BITS];
                    offset = address[OFFSET_BITS-1:0];
                    tag = address[31 -: TAG_BITS];
                    // Find an empty way or LRU way
                    way = 0;
		    ok = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (!valid[index][i] && !ok) begin
                            way = i;
                            break;
                        end
                    end
                    if (i == ASSOCIATIVITY) begin
                        way = 0;
                        for (i = 1; i < ASSOCIATIVITY; i = i + 1) begin
                            if (lru_counter[index][i] > lru_counter[index][way]) begin
                                way = i;
                            end
                        end
                    end
                    cache_tags[index][way] <= tag;
                    valid[index][way] <= 1;
                    dirty[index][way] <= 0;
                    for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                        cache_data[index][way][j] <= address;  // Dummy memory read
                    end
                    // LRU Update
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (i != way && lru_counter[index][i] < lru_counter[index][way]) begin
                            lru_counter[index][i] = lru_counter[index][i] + 1;
                        end
                    end
                    lru_counter[index][way] = 0;
                end
                WRITE_HIT: begin
                    offset = address[OFFSET_BITS-1:0];
                    cache_data[index][way][offset] <= write_data;
                    dirty[index][way] <= 1;
                    hit <= 1;
                    busy <= 0;
                    // LRU Update
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (i != way && lru_counter[index][i] < lru_counter[index][way]) begin
                            lru_counter[index][i] = lru_counter[index][i] + 1;
                        end
                    end
                    lru_counter[index][way] = 0;
                end
                WRITE_MISS: begin
                    miss <= 1;
                    busy <= 1;
                    #10;  // Simulate memory fetch delay
                    index = address[OFFSET_BITS +: INDEX_BITS];
                    offset = address[OFFSET_BITS-1:0];
                    tag = address[31 -: TAG_BITS];
                    // Find an empty way or LRU way
                    way = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (!valid[index][i]) begin
                            way = i;
                            break;
                        end
                    end
                    if (i == ASSOCIATIVITY) begin
                        way = 0;
                        for (i = 1; i < ASSOCIATIVITY; i = i + 1) begin
                            if (lru_counter[index][i] > lru_counter[index][way]) begin
                                way = i;
                            end
                        end
                    end
                    cache_tags[index][way] <= tag;
                    valid[index][way] <= 1;
                    dirty[index][way] <= 0;
                    for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                        cache_data[index][way][j] <= address;  // Dummy memory read
                    end
                    // Write data to cache
                    cache_data[index][way][offset] <= write_data;
                    dirty[index][way] <= 1;
                    // LRU Update
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (i != way && lru_counter[index][i] < lru_counter[index][way]) begin
                            lru_counter[index][i] = lru_counter[index][i] + 1;
                        end
                    end
                    lru_counter[index][way] = 0;
                end
                EVICT: begin
                    busy <= 1;
                    index = address[OFFSET_BITS +: INDEX_BITS];
                    tag = address[31 -: TAG_BITS];
                    // Find LRU way
                    way = 0;
                    for (i = 1; i < ASSOCIATIVITY; i = i + 1) begin
                        if (lru_counter[index][i] > lru_counter[index][way]) begin
                            way = i;
                        end
                    end
                    if (dirty[index][way]) begin
                        #10;  // Simulate memory write-back delay
                        for (j = 0; j < BLOCK_SIZE/4; j = j + 1) begin
                            // Dummy memory write
                        end
                    end
                    valid[index][way] <= 0;
                    dirty[index][way] <= 0;
                    next_state = IDLE;
                end
            endcase
        end
    end

endmodule

module testare_tb;
    reg clk;
    reg reset;
    reg [31:0] address;
    reg [31:0] write_data;
    reg read;
    reg write;
    wire [31:0] read_data;
    wire hit;
    wire miss;
    wire busy;

    testare uut (
        .clk(clk),
        .reset(reset),
        .address(address),
        .write_data(write_data),
        .read(read),
        .write(write),
        .read_data(read_data),
        .hit(hit),
        .miss(miss),
        .busy(busy)
    );

    initial begin
        clk = 0;
        reset = 1;
        #10 reset = 0;

	// Write miss case
        read = 0;
        write = 1;
        address = 32'h0000_0004;
        write_data = 32'hDEAD_BEEF;
        #20;

        // Write hit case
        read = 0;
        write = 1;
        address = 32'h0000_0004;
        write_data = 32'hCAFE_BABE;
        #20;

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



        $stop;
    end

    always #5 clk = ~clk;
endmodule
