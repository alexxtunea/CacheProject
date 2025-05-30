//============================
// Cache.v (final fixed version with HIT logic fix)
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
    output reg [3:0] dirty,
    output reg [3:0] and_val,
    output reg hit, miss, full, ask_for_data,
    output reg [3:0] state_debug
);

    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS = $clog2(NO_SETS);
    localparam TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS;

    localparam IDLE = 4'd0;
    localparam CAPTURE_ADDR = 4'd1;
    localparam READ = 4'd2;
    localparam READ_WAIT = 4'd3;
    localparam WRITE = 4'd4;
    localparam WRITE_WAIT = 4'd5;
    localparam READ_HIT = 4'd6;
    localparam READ_MISS = 4'd7;
    localparam WRITE_HIT = 4'd8;
    localparam WRITE_MISS = 4'd9;
    localparam CHECK = 4'd10;
    localparam EVICT = 4'd11;
    localparam EXIT = 4'd12;

    reg [3:0] state, next_state;

    reg [511:0] data_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [TAG_BITS-1:0] tag_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg valid_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_counter [0:NO_SETS-1][0:ASSOCIATIVITY-1];

    reg [31:0] addr_reg;
    reg [TAG_BITS-1:0] tag_reg;
    reg [INDEX_BITS-1:0] index_reg;
    reg [511:0] simulated_memory_data;
    reg [1:0] hit_index, replace_index;
    reg [3:0] local_and_val;
    reg [1:0] local_hit_index;
    integer i, j;

    wire hit_comb;
    assign hit_comb = |local_and_val;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (bgn) next_state = CAPTURE_ADDR;
            CAPTURE_ADDR: next_state = read ? READ : (write ? WRITE : IDLE);
            READ: next_state = READ_WAIT;
            READ_WAIT: next_state = hit_comb ? READ_HIT : READ_MISS;
            WRITE: next_state = WRITE_WAIT;
            WRITE_WAIT: next_state = hit_comb ? WRITE_HIT : WRITE_MISS;
            READ_HIT, WRITE_HIT: next_state = IDLE;
            READ_MISS, WRITE_MISS: next_state = CHECK;
            CHECK: next_state = full ? EVICT : EXIT;
            EVICT: next_state = EXIT;
            EXIT: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(*) begin
        local_and_val = 4'b0000;
        local_hit_index = 0;
        for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
            if (valid_array[index_reg][i] && tag_array[index_reg][i] == tag_reg) begin
                local_and_val[i] = 1'b1;
                local_hit_index = i[1:0];
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NO_SETS; i = i + 1)
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    lru_counter[i][j] <= 0;
                end
            addr_reg <= 0;
            tag_reg <= 0;
            index_reg <= 0;
            read_data <= 0;
            and_val <= 0;
            hit <= 0;
            miss <= 0;
            full <= 0;
            ask_for_data <= 0;
            dirty <= 0;
            simulated_memory_data <= 512'h123456ABCD;
        end else begin
            case (state)
                CAPTURE_ADDR: begin
                    addr_reg <= address;
                    tag_reg <= address[31 -: TAG_BITS];
                    index_reg <= address[OFFSET_BITS +: INDEX_BITS];
                end
                READ, WRITE: begin
                    and_val <= local_and_val;
                    hit_index <= local_hit_index;
                end
                READ_WAIT, WRITE_WAIT: begin
                    hit <= hit_comb;
                    miss <= ~hit_comb;
                end
                READ_HIT: begin
                    ask_for_data <= 0;
                    read_data <= data_array[index_reg][hit_index];
                    dirty <= {dirty_array[index_reg][3], dirty_array[index_reg][2], dirty_array[index_reg][1], dirty_array[index_reg][0]};
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (lru_counter[index_reg][i] < lru_counter[index_reg][hit_index])
                            lru_counter[index_reg][i] <= lru_counter[index_reg][i] + 1;
                    lru_counter[index_reg][hit_index] <= 0;
                end
                WRITE_HIT: begin
                    ask_for_data <= 0;
                    data_array[index_reg][hit_index] <= data_to_write;
                    dirty_array[index_reg][hit_index] <= 1;
                    tag_array[index_reg][hit_index] <= tag_reg;
                    valid_array[index_reg][hit_index] <= 1;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (lru_counter[index_reg][i] < lru_counter[index_reg][hit_index])
                            lru_counter[index_reg][i] <= lru_counter[index_reg][i] + 1;
                    lru_counter[index_reg][hit_index] <= 0;
                end
                READ_MISS, WRITE_MISS: begin
                    ask_for_data <= 1;
                    simulated_memory_data <= {16{addr_reg}};
                end
                CHECK: begin
                    full <= 1;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (!valid_array[index_reg][i])
                            full <= 0;
                end
                EVICT: begin
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (lru_counter[index_reg][i] == ASSOCIATIVITY - 1)
                            replace_index = i;
                end
                EXIT: begin
                    data_array[index_reg][replace_index] <= simulated_memory_data;
                    tag_array[index_reg][replace_index] <= tag_reg;
                    valid_array[index_reg][replace_index] <= 1;
                    dirty_array[index_reg][replace_index] <= write;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                        if (lru_counter[index_reg][i] < lru_counter[index_reg][replace_index])
                            lru_counter[index_reg][i] <= lru_counter[index_reg][i] + 1;
                    lru_counter[index_reg][replace_index] <= 0;
                end
                default: begin
                    hit <= 0;
                    miss <= 0;
                    ask_for_data <= 0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        state_debug <= state;
    end
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
    output wire full,
    output wire ask_for_data,
    output wire [3:0] and_val,
    output wire [3:0] dirty_bit_data,
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
        .full(full),
        .ask_for_data(ask_for_data),
        .and_val(and_val),
        .dirty(dirty_bit_data),
        .state_debug(state_debug)
    );

endmodule


//============================
// tb.v
//============================

module tb;
    reg clk, rst, bgn, read, write;
    reg [511:0] data;
    reg [31:0] address;
    wire [511:0] read_data;
    wire hit, miss, full, ask_for_data;
    wire [3:0] dirty, and_val;
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
        .full(full),
        .ask_for_data(ask_for_data),
        .and_val(and_val),
        .dirty_bit_data(dirty),
        .state_debug(state_debug)
    );

    integer hit_count = 0, miss_count = 0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count = hit_count + 1;
        if (miss) miss_count = miss_count + 1;
    end

    initial begin
        clk = 0; rst = 1; bgn = 0; write = 0; read = 0; address = 0; data = 512'h0;
        #20 rst = 0;

        // Write 1
        bgn = 1; write = 1; address = 32'h00001000; data = 512'hDEADBEEF;
        #100; bgn = 0; write = 0;

        // Read HIT
        #20; bgn = 1; read = 1; address = 32'h00001000;
        #100; bgn = 0; read = 0;

        // Read MISS
        #20; bgn = 1; read = 1; address = 32'h00002000;
        #100; bgn = 0; read = 0;

        // Write 2 (different address)
        #20; bgn = 1; write = 1; address = 32'h00003000; data = 512'hABCDEFABCDEF;
        #100; bgn = 0; write = 0;

        // Read HIT again
        #20; bgn = 1; read = 1; address = 32'h00001000;
        #100; bgn = 0; read = 0;

        $display("Final Hits = %0d, Misses = %0d", hit_count, miss_count);
        $finish;
    end
endmodule

