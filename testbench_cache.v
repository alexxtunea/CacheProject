//============================
// Cache.v (COMPLETE: with all required FSM states)
//============================

module Cache #(
    parameter CACHE_SIZE = 32768,
    parameter BLOCK_SIZE = 64,
    parameter WORD_SIZE = 4,
    parameter NO_SETS = 128,
    parameter ASSOCIATIVITY = 4
)(
    input clk, rst,
    input [31:0] address,
    input [511:0] data_to_write,
    input read, write, bgn,
    output reg [511:0] read_data,
    output reg hit, miss,
    output reg [3:0] state_debug
);

    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS = $clog2(NO_SETS);
    localparam TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS;

    reg [3:0] state;
    localparam IDLE = 0,
               READ_HIT = 1,
               READ_MISS = 2,
               WRITE_HIT = 3,
               WRITE_MISS = 4,
               EVICT = 5,
               ALLOCATE = 6,
               CAPTURE_ADDR = 7;

    reg [511:0] data_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [TAG_BITS-1:0] tag_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg valid_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];

    reg [TAG_BITS-1:0] tag;
    reg [INDEX_BITS-1:0] index;
    integer i, j;

    reg found;
    reg [1:0] hit_idx, replace_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            hit <= 0;
            miss <= 0;
            read_data <= 0;
            for (i = 0; i < NO_SETS; i = i + 1) begin
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    lru_array[i][j] <= j;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    if (bgn && (read || write)) begin
                        tag <= address[31 -: TAG_BITS];
                        index <= address[OFFSET_BITS +: INDEX_BITS];
                        state <= CAPTURE_ADDR;
                    end
                    hit <= 0;
                    miss <= 0;
                end

                CAPTURE_ADDR: begin
                    found = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (valid_array[index][i] && tag_array[index][i] == tag) begin
                            found = 1;
                            hit_idx = i;
                        end
                    end
                    if (found) begin
                        state <= read ? READ_HIT : WRITE_HIT;
                    end else begin
                        state <= read ? READ_MISS : WRITE_MISS;
                    end
                end

                READ_HIT: begin
                    hit <= 1;
                    miss <= 0;
                    read_data <= data_array[index][hit_idx];
                    update_lru(index, hit_idx);
                    state <= IDLE;
                end

                WRITE_HIT: begin
                    hit <= 1;
                    miss <= 0;
                    data_array[index][hit_idx] <= data_to_write;
                    dirty_array[index][hit_idx] <= 1;
                    update_lru(index, hit_idx);
                    state <= IDLE;
                end

                READ_MISS, WRITE_MISS: begin
                    hit <= 0;
                    miss <= 1;
                    found = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (!valid_array[index][i]) begin
                            replace_idx = i;
                            found = 1;
                            state <= ALLOCATE;
                        end
                    end
                    if (!found)
                        state <= EVICT;
                end

                EVICT: begin
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (lru_array[index][i] == ASSOCIATIVITY - 1)
                            replace_idx = i;
                    if (dirty_array[index][replace_idx]) begin
                        $display("Evicting dirty block: SET %0d WAY %0d", index, replace_idx);
                    end
                    state <= ALLOCATE;
                end

                ALLOCATE: begin
                    tag_array[index][replace_idx] <= tag;
                    data_array[index][replace_idx] <= write ? data_to_write : 512'hCAFEBABE;
                    valid_array[index][replace_idx] <= 1;
                    dirty_array[index][replace_idx] <= write;
                    update_lru(index, replace_idx);
                    state <= IDLE;
                end
            endcase
        end
        state_debug <= state;
    end

    task update_lru(input [INDEX_BITS-1:0] set_idx, input [1:0] used_way);
        integer k;
        begin
            for (k = 0; k < ASSOCIATIVITY; k = k + 1) begin
                if (lru_array[set_idx][k] < lru_array[set_idx][used_way])
                    lru_array[set_idx][k] <= lru_array[set_idx][k] + 1;
            end
            lru_array[set_idx][used_way] <= 0;
        end
    endtask

endmodule


//============================
// struct.v
//============================

module struct(
    input clk,
    input rst,
    input bgn,
    input write,
    input read,
    input [511:0] data,
    input [31:0] address,
    output [511:0] read_data,
    output wire hit,
    output wire miss,
    output wire [3:0] state_debug
);

    Cache cache_i(
        .clk(clk),
        .rst(rst),
        .bgn(bgn),
        .write(write),
        .read(read),
        .address(address),
        .data_to_write(data),
        .read_data(read_data),
        .hit(hit),
        .miss(miss),
        .state_debug(state_debug)
    );

endmodule


//============================
// tb.v (extended to test eviction)
//============================

module tb;
    reg clk, rst, bgn, read, write;
    reg [511:0] data;
    reg [31:0] address;
    wire [511:0] read_data;
    wire hit, miss;
    wire [3:0] state_debug;

    struct dut(
        .clk(clk),
        .rst(rst),
        .bgn(bgn),
        .write(write),
        .read(read),
        .data(data),
        .address(address),
        .read_data(read_data),
        .hit(hit),
        .miss(miss),
        .state_debug(state_debug)
    );

    integer hit_count = 0, miss_count = 0, i;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count = hit_count + 1;
        if (miss) miss_count = miss_count + 1;
    end

    initial begin
        clk = 0; rst = 1; bgn = 0; read = 0; write = 0; address = 0; data = 0;
        #20 rst = 0;

        // Fill a set fully
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk); bgn = 1; write = 1; address = {20'd1, 7'd0, 5'(i * 16)}; data = i;
            @(posedge clk); bgn = 0; write = 0;
            repeat (2) @(posedge clk);
        end

        // Trigger eviction
        @(posedge clk); bgn = 1; write = 1; address = {20'd2, 7'd0, 5'd0}; data = 5;
        @(posedge clk); bgn = 0; write = 0;
        repeat (2) @(posedge clk);

        // Access one of the older entries to check LRU
        @(posedge clk); bgn = 1; read = 1; address = {20'd1, 7'd0, 5'd0};
        @(posedge clk); bgn = 0; read = 0;
        repeat (2) @(posedge clk);

        $display("Final Hits = %0d, Misses = %0d", hit_count, miss_count);
        $finish;
    end
endmodule

