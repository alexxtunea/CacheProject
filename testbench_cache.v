//============================
// fsm.v
//============================

module fsm(
    input clk, rst, bgn,
    input write,
    input read,
    input hit, miss,
    input full,
    output reg c0,c1,c2,c3,c4,c5,c6,c7
);

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

always @(posedge clk or posedge rst) begin
    if (rst)
        st <= IDLE;
    else
        st <= nxt_st;
end

always @(*) begin
    nxt_st = st;
    case (st)
        IDLE: begin
            if (!bgn) nxt_st = IDLE;
            else if (read) nxt_st = READ;
            else if (write) nxt_st = WRITE;
        end
        READ: nxt_st = hit ? READ_HIT : READ_MISS;
        WRITE: nxt_st = hit ? WRITE_HIT : WRITE_MISS;
        READ_HIT, WRITE_HIT: nxt_st = IDLE;
        READ_MISS, WRITE_MISS: nxt_st = CHECK;
        CHECK: nxt_st = full ? EVICT : EXIT;
        EVICT: nxt_st = EXIT;
        EXIT: nxt_st = IDLE;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'b0;
    else begin
        {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'b0;
        case (nxt_st)
            IDLE: c0 <= 1;
            READ: c1 <= 1;
            WRITE: c2 <= 1;
            READ_HIT: begin c1 <= 1; c3 <= 1; end
            WRITE_HIT: begin c2 <= 1; c3 <= 1; end
            READ_MISS: begin c1 <= 1; c4 <= 1; end
            WRITE_MISS: begin c2 <= 1; c4 <= 1; end
            CHECK: c5 <= 1;
            EVICT: c7 <= 1;
            EXIT: c6 <= 1;
        endcase
    end
end
endmodule


//============================
// Cache.v (FULLY IMPLEMENTED with Fixes)
//============================

module Cache #(
    parameter CACHE_SIZE = 32768,
    parameter BLOCK_SIZE = 64,
    parameter WORD_SIZE = 4,
    parameter NO_SETS = 128,
    parameter ASSOCIATIVITY = 4
)(
    input clk, rst,
    input c0, c1, c2, c3, c4, c5, c6, c7,
    input [31:0] address,
    input [511:0] data_to_write,
    input read, write,
    output reg [511:0] read_data,
    output reg [3:0] dirty,
    output reg [3:0] and_val,
    output reg hit, miss, free, ask_for_data
);

    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS = $clog2(NO_SETS);
    localparam TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS;

    reg [511:0] data_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [TAG_BITS-1:0] tag_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg valid_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_counter [0:NO_SETS-1][0:ASSOCIATIVITY-1];

    wire [TAG_BITS-1:0] tag = address[31 -: TAG_BITS];
    wire [INDEX_BITS-1:0] index = address[OFFSET_BITS +: INDEX_BITS];

    integer i, j;
    reg found;
    reg [1:0] hit_index;
    reg [1:0] replace_index;

    always @(*) begin
        hit = 0;
        miss = 0;
        found = 0;
        and_val = 4'b0000;
        for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
            if (valid_array[index][i] && tag_array[index][i] == tag) begin
                hit = 1;
                found = 1;
                hit_index = i[1:0];
                and_val[i] = 1;
            end
        end
        if (!found)
            miss = 1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NO_SETS; i = i + 1) begin
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    lru_counter[i][j] <= j;
                end
            end
            ask_for_data <= 0;
            read_data <= 0;
            dirty <= 4'b0000;
            and_val <= 4'b0000;
            free <= 1;
        end else begin
            dirty <= 4'b0000;
            read_data <= 0;
            ask_for_data <= 0;
            if (c1 || c2) begin
                if (hit) begin
                    read_data <= data_array[index][hit_index];
                    dirty <= {dirty_array[index][3], dirty_array[index][2], dirty_array[index][1], dirty_array[index][0]};
                    if (c3 && write) dirty_array[index][hit_index] <= 1;
                    if (c3) begin
                        for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                            if (lru_counter[index][i] < lru_counter[index][hit_index])
                                lru_counter[index][i] <= lru_counter[index][i] + 1;
                        lru_counter[index][hit_index] <= 0;
                    end
                end else if (miss) begin
                    ask_for_data <= 1;
                end
            end

            if (c5) begin
                free <= 0;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                    if (!valid_array[index][i]) begin
                        replace_index = i;
                        free <= 1;
                    end
                end
            end else begin
                free <= 0;
            end

            if (c7) begin
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index][i] == ASSOCIATIVITY - 1)
                        replace_index = i;
            end

            if (c6) begin
                data_array[index][replace_index] <= data_to_write;
                tag_array[index][replace_index] <= tag;
                valid_array[index][replace_index] <= 1;
                dirty_array[index][replace_index] <= write;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index][i] < lru_counter[index][replace_index])
                        lru_counter[index][i] <= lru_counter[index][i] + 1;
                lru_counter[index][replace_index] <= 0;
            end
        end
    end
endmodule


//============================
// tb.v (Testbench)
//============================

module tb;
    reg clk, rst, bgn;
    reg write, read;
    wire hit, miss;
    wire full;
    wire c0, c1, c2, c3, c4, c5, c6, c7;
    reg [31:0] address;
    reg [511:0] data_to_write;
    wire [511:0] read_data;
    wire [3:0] dirty, and_val;
    wire free, ask_for_data;

    integer hit_count = 0;
    integer miss_count = 0;

    fsm uut_fsm (
        .clk(clk), .rst(rst), .bgn(bgn),
        .write(write), .read(read),
        .hit(hit), .miss(miss), .full(!free),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3), .c4(c4), .c5(c5), .c6(c6), .c7(c7)
    );

    Cache uut_cache (
        .clk(clk), .rst(rst),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3), .c4(c4), .c5(c5), .c6(c6), .c7(c7),
        .address(address), .data_to_write(data_to_write),
        .read(read), .write(write),
        .read_data(read_data), .dirty(dirty), .and_val(and_val),
        .hit(hit), .miss(miss), .free(free), .ask_for_data(ask_for_data)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count = hit_count + 1;
        if (miss) miss_count = miss_count + 1;
    end

    initial begin
        clk = 0; rst = 1; bgn = 0; write = 0; read = 0;
        address = 0;
        data_to_write = 512'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5;

        #10 rst = 0;
        #10 bgn = 1; read = 1; address = 32'h00000000; #100; bgn = 0; read = 0;
        #20 bgn = 1; read = 1; address = 32'h00000000; #100; bgn = 0; read = 0;
        #20 bgn = 1; write = 1; address = 32'h00001000;
             data_to_write = 512'hDEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF;
             #100; bgn = 0; write = 0;
        #20 bgn = 1; read = 1; address = 32'h00001000; #100; bgn = 0; read = 0;
        #20 bgn = 1; write = 1; address = 32'h00002000;
             data_to_write = 512'hCAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE;
             #100; bgn = 0; write = 0;
        #20 bgn = 1; read = 1; address = 32'h00002000; #100; bgn = 0; read = 0;
        #20 bgn = 1; read = 1; address = 32'h0000F000; #100; bgn = 0; read = 0;
        #20 bgn = 1; write = 1; address = 32'h00001000;
             data_to_write = 512'hBADD_C0DE_BADD_C0DE_BADD_C0DE_BADD_C0DE_BADD_C0DE_BADD_C0DE_BADD_C0DE_BADD_C0DE;
             #100; bgn = 0; write = 0;
        #20 bgn = 1; read = 1; address = 32'h00001000; #100; bgn = 0; read = 0;

        #20;
        $display("Hit count: %0d", hit_count);
        $display("Miss count: %0d", miss_count);
    end
endmodule

