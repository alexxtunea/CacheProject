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
    if (rst) {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'd128;
    else begin
        {c0,c1,c2,c3,c4,c5,c6,c7} <= 8'd128;
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
    output reg hit, miss, full, ask_for_data
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

    reg [511:0] simulated_memory_data;

    always @(*) begin
        hit = 0;
        and_val = 4'b0000;
        found = 0;
        for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
            if (valid_array[index][i] && tag_array[index][i] == tag) begin
                hit = 1;
                found = 1;
                hit_index = i[1:0];
                and_val[i] = 1;
            end
        end
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
            full <= 0;
            simulated_memory_data <= 512'h123456ABCD;
            miss <= 0;
        end else begin
            dirty <= 4'b0000;
            read_data <= 0;
            ask_for_data <= 0;
            miss <= 0;

            if ((c1 || c2) && hit && c3) begin
                read_data <= data_array[index][hit_index];
                dirty <= {dirty_array[index][3], dirty_array[index][2], dirty_array[index][1], dirty_array[index][0]};
                if (write) dirty_array[index][hit_index] <= 1;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index][i] < lru_counter[index][hit_index])
                        lru_counter[index][i] <= lru_counter[index][i] + 1;
                lru_counter[index][hit_index] <= 0;
            end

            if (c4) begin
                ask_for_data <= 1;
                simulated_memory_data <= {16{address}};
                read_data <= simulated_memory_data;
            end

            full <= 1;
            for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                if (!valid_array[index][i]) begin
                    full <= 0;
                end
            end

            if (c7) begin
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index][i] == ASSOCIATIVITY - 1)
                        replace_index = i;
            end

            if (c6) begin
                data_array[index][replace_index] <= simulated_memory_data;
                tag_array[index][replace_index] <= tag;
                valid_array[index][replace_index] <= 1;
                dirty_array[index][replace_index] <= write;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                    if (lru_counter[index][i] < lru_counter[index][replace_index])
                        lru_counter[index][i] <= lru_counter[index][i] + 1;
                lru_counter[index][replace_index] <= 0;
            end

            if ((c1 && !hit) || (c2 && !hit)) begin
                miss <= 1;
            end
        end
    end
endmodule


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

    wire temp_hit, temp_miss, temp_full, temp_ask;
    wire [3:0] temp_and, temp_dirty;
    wire c0, c1, c2, c3, c4, c5, c6, c7;

    fsm control_i(
        .clk(clk), .rst(rst), .bgn(bgn), .write(write), .read(read),
        .hit(temp_hit), .miss(temp_miss), .full(temp_full),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7)
    );

    Cache cache_i(
        .clk(clk), .rst(rst), .data_to_write(data), .address(address),
        .read(read), .write(write),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7),
        .read_data(read_data), .dirty(temp_dirty),
        .and_val(temp_and), .hit(temp_hit), .miss(temp_miss),
        .full(temp_full), .ask_for_data(temp_ask)
    );

    assign hit = temp_hit;
    assign miss = temp_miss;
    assign full = temp_full;
    assign ask_for_data = temp_ask;
    assign hit_bar = temp_hit;

    always @(*) begin
        t0 = c0;
        t1 = c1;
        t2 = c2;
        t3 = c3;
        t4 = c4;
        t5 = c5;
        t6 = c6;
        t7 = c7;
        and_val = temp_and;
        dirty_bit_data = temp_dirty;
    end
endmodule

//============================
// tb.v (Testbench)
//============================
/*
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
    wire ask_for_data;

    integer hit_count = 0;
    integer miss_count = 0;

    fsm uut_fsm (
        .clk(clk), .rst(rst), .bgn(bgn),
        .write(write), .read(read),
        .hit(hit), .miss(miss), .full(full),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7)
    );

    Cache uut_cache (
        .clk(clk), .rst(rst),
        .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .c4(c4), .c5(c5), .c6(c6), .c7(c7),
        .address(address), .data_to_write(data_to_write),
        .read(read), .write(write),
        .read_data(read_data), .dirty(dirty),
        .and_val(and_val), .hit(hit), .miss(miss),
        .full(full), .ask_for_data(ask_for_data)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1;
        bgn = 0; read = 0; write = 0;
        address = 0;
        data_to_write = 512'hA;
        #20;
        rst = 0;

        // WRITE 1
        #10;
        address = 32'h00000000;
        data_to_write = 512'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
        bgn = 1; write = 1;
        #60;
        bgn = 0; write = 0;

        // WRITE 2
        #10;
        address = 32'h00000010;
        data_to_write = 512'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB;
        bgn = 1; write = 1;
        #60;
        bgn = 0; write = 0;

        // WRITE 3
        #10;
        address = 32'h00000020;
        data_to_write = 512'hCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC;
        bgn = 1; write = 1;
        #60;
        bgn = 0; write = 0;

        // READ 1 (expect HIT)
        #10;
        address = 32'h00000000;
        bgn = 1; read = 1;
        #60;
        bgn = 0; read = 0;

        // READ 2 (expect HIT)
        #10;
        address = 32'h00000010;
        bgn = 1; read = 1;
        #60;
        bgn = 0; read = 0;

        // READ 3 (expect HIT)
        #10;
        address = 32'h00000020;
        bgn = 1; read = 1;
        #60;
        bgn = 0; read = 0;

        // Final report
        #50;
        $display("Simulation Finished");
        $display("Total Hits: %0d | Total Misses: %0d", hit_count, miss_count);
        $finish;
    end

    always @(posedge clk) begin
        if (read && hit) hit_count = hit_count + 1;
        if (write && miss) miss_count = miss_count + 1;
        $display("HIT: %b | MISS: %b | FULL: %b | READ_DATA: %h | DIRTY: %b",
                 hit, miss, full, read_data, dirty);
    end
endmodule
*/

module tb;
    reg clk, rst, bgn;
    reg write, read;
    reg [31:0] address;
    reg [511:0] data_to_write;

    wire [511:0] read_data;
    wire [3:0] dirty, and_val;
    wire ask_for_data;
    wire hit, miss;
    wire full;
    wire t0, t1, t2, t3, t4, t5, t6, t7;
    wire hit_bar;

    integer hit_count = 0;
    integer miss_count = 0;

    // Instan?ierea modulului struct (top-level wrapper)
    struct uut_struct (
        .clk(clk),
        .rst(rst),
        .bgn(bgn),
        .write(write),
        .read(read),
        .data(data_to_write),
        .address(address),
        .read_data(read_data),
        .t0(t0), .t1(t1), .t2(t2), .t3(t3),
        .t4(t4), .t5(t5), .t6(t6), .t7(t7),
        .hit_bar(hit_bar),
        .and_val(and_val),
        .dirty_bit_data(dirty),
        .hit(hit),
        .miss(miss),
        .full(full),
        .ask_for_data(ask_for_data)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hit) hit_count = hit_count + 1;
        if (miss) miss_count = miss_count + 1;

        $display("Time: %0t | HIT: %b | MISS: %b | FULL: %b | ASK: %b | READ_DATA: %h | DIRTY: %b",
                 $time, hit, miss, full, ask_for_data, read_data, dirty);
    end

    initial begin
        clk = 0;
        rst = 1;
        bgn = 0;
        read = 0;
        write = 0;
        address = 0;
        data_to_write = 512'hA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5;

        #20 rst = 0;

        // Scrie o valoare în cache
        bgn = 1; write = 1;
        address = 32'h00001000;
        data_to_write = 512'hDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;
        #100; bgn = 0; write = 0;

        // Cite?te de dou? ori din acea adres? (al doilea ar trebui s? fie HIT)
        #20;
        bgn = 1; read = 1;
        address = 32'h00001000;
        #100; bgn = 0; read = 0;

        #20;
        bgn = 1; read = 1;
        address = 32'h00001000;
        #100; bgn = 0; read = 0;

        #20;
        $display("Final HIT count: %0d | MISS count: %0d", hit_count, miss_count);
        $stop;
    end
endmodule

