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
parameter READ_WAIT = 4'b1010;
parameter WRITE = 4'b0010;
parameter WRITE_WAIT = 4'b1011;
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
        READ: nxt_st = READ_WAIT;
        READ_WAIT: nxt_st = hit ? READ_HIT : READ_MISS;
        WRITE: nxt_st = WRITE_WAIT;
        WRITE_WAIT: nxt_st = hit ? WRITE_HIT : WRITE_MISS;
        READ_HIT, WRITE_HIT: nxt_st = IDLE;
        READ_MISS, WRITE_MISS: nxt_st = CHECK;
        CHECK: nxt_st = full ? EVICT : EXIT;
        EVICT: nxt_st = EXIT;
        EXIT: nxt_st = IDLE;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'd0;
    else begin
        {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'd0;
        case (nxt_st)
            IDLE: if (!bgn) c0 <= 1;
            READ: c1 <= 1;
            READ_WAIT: c1 <= 1;
            WRITE: c2 <= 1;
            WRITE_WAIT: c2 <= 1;
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
// Cache.v
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
    output reg hit, full, ask_for_data
);

    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS = $clog2(NO_SETS);
    localparam TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS;

    reg [511:0] data_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [TAG_BITS-1:0] tag_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg valid_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg dirty_array [0:NO_SETS-1][0:ASSOCIATIVITY-1];
    reg [1:0] lru_counter [0:NO_SETS-1][0:ASSOCIATIVITY-1];

    reg [31:0] addr_reg;
    reg [TAG_BITS-1:0] tag_reg;
    reg [INDEX_BITS-1:0] index_reg;

    integer i, j;
    reg found;
    reg [1:0] hit_index;
    reg [1:0] replace_index;

    reg [511:0] simulated_memory_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_reg <= 0;
            tag_reg <= 0;
            index_reg <= 0;
        end else begin
            addr_reg <= address;
            tag_reg <= address[31 -: TAG_BITS];
            index_reg <= address[OFFSET_BITS +: INDEX_BITS];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hit <= 0;
            and_val <= 4'b0;
        end else begin
            hit <= 0;
            and_val <= 4'b0000;
            found = 0;
            for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                if (valid_array[index_reg][i] && tag_array[index_reg][i] == tag_reg) begin
                    hit <= 1;
                    found = 1;
                    hit_index = i[1:0];
                    and_val[i] <= 1;
                end
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NO_SETS; i = i + 1)
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    lru_counter[i][j] <= j;
                end
            ask_for_data <= 0;
            read_data <= 0;
            dirty <= 4'b0000;
            full <= 0;
            simulated_memory_data <= 512'h123456ABCD;
        end else begin
            dirty <= 4'b0000;
            read_data <= 0;
            ask_for_data <= 0;

            if ((c1 || c2) && hit && c3) begin
                read_data <= data_array[index_reg][hit_index];
                dirty <= {dirty_array[index_reg][3], dirty_array[index_reg][2], dirty_array[index_reg][1], dirty_array[index_reg][0]};
                if (write) dirty_array[index_reg][hit_index] <= 1;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index_reg][i] < lru_counter[index_reg][hit_index])
                        lru_counter[index_reg][i] <= lru_counter[index_reg][i] + 1;
                lru_counter[index_reg][hit_index] <= 0;
            end

            if (c4) begin
                ask_for_data <= 1;
                simulated_memory_data <= {16{addr_reg}};
                read_data <= simulated_memory_data;
            end

            full <= 1;
            for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                if (!valid_array[index_reg][i])
                    full <= 0;

            if (c7) begin
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index_reg][i] == ASSOCIATIVITY - 1)
                        replace_index = i;
            end

            if (c6) begin
                data_array[index_reg][replace_index] <= simulated_memory_data;
                tag_array[index_reg][replace_index] <= tag_reg;
                valid_array[index_reg][replace_index] <= 1;
                dirty_array[index_reg][replace_index] <= write;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index_reg][i] < lru_counter[index_reg][replace_index])
                        lru_counter[index_reg][i] <= lru_counter[index_reg][i] + 1;
                lru_counter[index_reg][replace_index] <= 0;
            end
        end
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
    output reg t0,t1,t2,t3,t4,t5,t6,t7,
    output wire hit,
    output wire miss,
    output wire full,
    output wire ask_for_data,
    output reg [3:0] and_val,
    output reg [3:0] dirty_bit_data,
    output wire hit_bar
);

    wire temp_hit, temp_full, temp_ask;
    wire [3:0] temp_and, temp_dirty;
    wire c0, c1, c2, c3, c4, c5, c6, c7;

    reg hit_r, miss_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hit_r <= 0;
            miss_r <= 0;
        end else begin
            hit_r <= temp_hit;
            miss_r <= (c1 || c2) ? ~temp_hit : 1'b0;
        end
    end

    fsm fsm_i(
        .clk(clk), .rst(rst), .bgn(bgn), .write(write), .read(read),
        .hit(hit_r), .miss(miss_r), .full(temp_full),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7)
    );

    Cache cache_i(
        .clk(clk), .rst(rst), .data_to_write(data), .address(address),
        .read(read), .write(write),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7),
        .read_data(read_data), .dirty(temp_dirty),
        .and_val(temp_and), .hit(temp_hit),
        .full(temp_full), .ask_for_data(temp_ask)
    );

    assign hit = hit_r;
    assign miss = miss_r;
    assign full = temp_full;
    assign ask_for_data = temp_ask;
    assign hit_bar = hit_r;

    always @(*) begin
        t0 = c0; t1 = c1; t2 = c2; t3 = c3;
        t4 = c4; t5 = c5; t6 = c6; t7 = c7;
        and_val = temp_and;
        dirty_bit_data = temp_dirty;
    end
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
    wire t0,t1,t2,t3,t4,t5,t6,t7;
    wire hit_bar;

    struct dut(
        .clk(clk), .rst(rst), .bgn(bgn), .write(write), .read(read),
        .data(data), .address(address), .read_data(read_data),
        .t0(t0), .t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5), .t6(t6), .t7(t7),
        .hit(hit), .miss(miss), .full(full), .ask_for_data(ask_for_data),
        .and_val(and_val), .dirty_bit_data(dirty), .hit_bar(hit_bar)
    );

    integer hit_count = 0, miss_count = 0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count=hit_count+1;
        if (miss) miss_count=miss_count+1;
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
        $stop;
    end
endmodule

