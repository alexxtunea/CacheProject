//============================
// Cache.v - updated: Removed ALLOCATE_READ state + Added debug in CAPTURE_ADDR
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
    localparam OFFSET_BITS = 6;
    localparam INDEX_BITS = 7;
    localparam TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS; // 19

    reg [3:0] state;
    localparam IDLE = 0, READ_HIT = 1, READ_MISS = 2, WRITE_HIT = 3,
               WRITE_MISS = 4, EVICT = 5,
               ALLOCATE_WRITE = 6, CAPTURE_ADDR = 7;

    reg [511:0] data_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [TAG_BITS-1:0] tag_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg valid_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];

    reg [TAG_BITS-1:0] tag;
    reg [INDEX_BITS-1:0] index;
    reg found;
    reg [1:0] hit_way, replace_idx;
    reg is_read_pending;
    reg [511:0] simulated_memory_data;
    integer i, j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            hit <= 0;
            miss <= 0;
            is_read_pending <= 0;
            read_data <= 0;
            simulated_memory_data <= 512'hCAFEBABE;
            for (i = 0; i < NO_SETS; i = i + 1)
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    lru_array[i][j] <= j;
                    data_array[i][j] <= 0;
                    tag_array[i][j] <= 0;
                end
        end else begin
            case (state)
                IDLE: begin
                    if (bgn && (read || write)) begin
                        tag <= address[31:32-TAG_BITS];
                        index <= address[OFFSET_BITS +: INDEX_BITS];
                        is_read_pending <= read;
                        state <= CAPTURE_ADDR;
                    end
                    hit <= 0;
                    miss <= 0;
                end

                CAPTURE_ADDR: begin
                    found = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (valid_array[index][i] && tag_array[index][i] == tag) begin
                            found = 1;
                            hit_way <= i;
                        end
                    state <= found ? (is_read_pending ? READ_HIT : WRITE_HIT) :
                                      (is_read_pending ? READ_MISS : WRITE_MISS);
                end

                READ_HIT: begin
                    hit <= 1;
                    miss <= 0;
                    read_data <= data_array[index][hit_way];
                    update_lru(index, hit_way);
                    $display("READ HIT: SET=%0d WAY=%0d DATA=%h DIRTY=%0b", index, hit_way, data_array[index][hit_way], dirty_array[index][hit_way]);
                    state <= IDLE;
                end

                WRITE_HIT: begin
                    hit <= 1;
                    miss <= 0;
                    data_array[index][hit_way] <= data_to_write;
                    dirty_array[index][hit_way] <= 1;
                    update_lru(index, hit_way);
                    $display("WRITE HIT: SET=%0d WAY=%0d DIRTY=%0b", index, hit_way, dirty_array[index][hit_way]);
                    state <= IDLE;
                end

                READ_MISS: begin
                    hit <= 0;
                    miss <= 1;
                    read_data <= simulated_memory_data;
                    $display("READ MISS: tag=%0h index=%0d - returning simulated %h", tag, index, simulated_memory_data);
                    state <= IDLE;
                end

                WRITE_MISS: begin
                    hit <= 0;
                    miss <= 1;
                    found = 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (!valid_array[index][i] && !found) begin
                            replace_idx = i;
                            found = 1;
                        end

                    if (found) begin
                        state <= ALLOCATE_WRITE;
                    end else begin
                        state <= EVICT;
                    end
                end

                EVICT: begin
                    replace_idx = get_lru(index);
                    $display("Evicting block: SET %0d WAY %0d (TAG = %h, DIRTY = %b)", 
                             index, replace_idx, tag_array[index][replace_idx], dirty_array[index][replace_idx]);
                    if (dirty_array[index][replace_idx]) begin
                        $display("Writing back dirty block: SET %0d WAY %0d DATA = %h", 
                                 index, replace_idx, data_array[index][replace_idx]);
                    end
                    dirty_array[index][replace_idx] <= 0;
                    state <= is_read_pending ? IDLE : ALLOCATE_WRITE;
                end

                ALLOCATE_WRITE: begin
                    tag_array[index][replace_idx] <= tag;
                    data_array[index][replace_idx] <= data_to_write;
                    valid_array[index][replace_idx] <= 1;
                    dirty_array[index][replace_idx] <= 1;
                    update_lru(index, replace_idx);
                    $display("ALLOCATE WRITE: tag %0h to set %0d way %0d DIRTY=%0b", tag, index, replace_idx, dirty_array[index][replace_idx]);
                    state <= IDLE;
                end
            endcase
        end
        state_debug <= state;
    end

    task update_lru(input [INDEX_BITS-1:0] set_idx, input [1:0] used_way);
        integer k;
        begin
            for (k = 0; k < ASSOCIATIVITY; k = k + 1)
                if (lru_array[set_idx][k] < lru_array[set_idx][used_way])
                    lru_array[set_idx][k] <= lru_array[set_idx][k] + 1;
            lru_array[set_idx][used_way] <= 0;
        end
    endtask

    function [1:0] get_lru(input [INDEX_BITS-1:0] set_idx);
        integer k;
        begin
            get_lru = 0;
            for (k = 0; k < ASSOCIATIVITY; k = k + 1)
                if (lru_array[set_idx][k] == (ASSOCIATIVITY - 1))
                    get_lru = k;
        end
    endfunction

endmodule


//============================
// struct.v - wrapper module
//============================
module struct(
    input clk, rst, bgn, write, read,
    input [511:0] data,
    input [31:0] address,
    output [511:0] read_data,
    output hit, miss,
    output [3:0] state_debug
);
    Cache cache_inst (
        .clk(clk), .rst(rst), .bgn(bgn),
        .write(write), .read(read),
        .address(address), .data_to_write(data),
        .read_data(read_data), .hit(hit), .miss(miss),
        .state_debug(state_debug)
    );
endmodule


//============================
// tb.v - testbench with extended read test cases
//============================
module tb;
    reg clk = 0, rst, bgn, read, write;
    reg [511:0] data;
    reg [31:0] address;
    wire [511:0] read_data;
    wire hit, miss;
    wire [3:0] state_debug;

    struct dut(
        .clk(clk), .rst(rst), .bgn(bgn),
        .write(write), .read(read),
        .data(data), .address(address),
        .read_data(read_data), .hit(hit),
        .miss(miss), .state_debug(state_debug)
    );

    integer hit_count = 0, miss_count = 0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count = hit_count + 1;
        if (miss) miss_count = miss_count + 1;
    end

    initial begin
        rst = 1; bgn = 0; read = 0; write = 0;
        #15 rst = 0;

        // Fill set 5 with 4 tags
        @(posedge clk); bgn = 1; write = 1; address = {19'd10, 7'd5, 6'd0}; data = 32'hAAAA_AAAA;
        @(posedge clk); bgn = 0; write = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; write = 1; address = {19'd11, 7'd5, 6'd0}; data = 32'hBBBB_BBBB;
        @(posedge clk); bgn = 0; write = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; write = 1; address = {19'd12, 7'd5, 6'd0}; data = 32'hCCCC_CCCC;
        @(posedge clk); bgn = 0; write = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; write = 1; address = {19'd13, 7'd5, 6'd0}; data = 32'hDDDD_DDDD;
        @(posedge clk); bgn = 0; write = 0; repeat(2) @(posedge clk);

        // Re-read all 4 to check for hits
        @(posedge clk); bgn = 1; read = 1; address = {19'd10, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; read = 1; address = {19'd11, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; read = 1; address = {19'd12, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        @(posedge clk); bgn = 1; read = 1; address = {19'd13, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        // Trigger eviction
        @(posedge clk); bgn = 1; write = 1; address = {19'd20, 7'd5, 6'd0}; data = 32'hEFEFEFEF;
        @(posedge clk); bgn = 0; write = 0; repeat(2) @(posedge clk);

        // Read evicted block -> miss
        @(posedge clk); bgn = 1; read = 1; address = {19'd11, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        // Final read (should hit)
        @(posedge clk); bgn = 1; read = 1; address = {19'd20, 7'd5, 6'd0};
        @(posedge clk); bgn = 0; read = 0; repeat(2) @(posedge clk);

        $display("Final Hits = %0d, Misses = %0d", hit_count, miss_count);
        $finish;
    end
endmodule

