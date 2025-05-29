`import "cache.v"
`import "fsm.v"

module modules(
    input clk,
    input rst,
    input bgn,
    input write,
    input read,
    input [511:0] data,
    input [31:0] address,
    output [511:0] outbus,
    output reg t0,t1,t2,t3,t4,t5,t6,t7,
    output reg hit_bar,
    output reg [3:0] and_val,
    output reg [3:0] dirty_bit_data
);


    reg hit;
    reg space;
    wire temp_hit;
    wire temp_space;
    wire temp_ask;
    wire [3:0] temp_and;
    wire [3:0] temp_dirty_bit;

    wire c0,c1,c2,c3,c4,c5,c6,c7;


    control control_i(  .clk(clk),.rst(rst),.bgn(bgn),.write(write),.read(read),.hit_or_miss(temp_hit),.space_in_lru(temp_space),
                        .c0(c0),.c1(c1),.c2(c2),.c3(c3),.c4(c4),.c5(c5),.c6(c6),.c7(c7));

    cache cache_i(  .clk(clk),.rst(rst),.data(data),.address(address),
                    .c0(c0),.c1(c1),.c2(c2),.c3(c3),.c4(c4),.c5(c5),.c6(c6),.c7(c7),
                    .hit_or_miss(temp_hit),.ask_for_data(temp_ask),.space_in_lru(temp_space),.outbus(outbus),.and_val(temp_and),.dirty_bit(temp_dirty_bit));

    always @(*) begin
        hit = temp_hit;
        space = temp_space;
        t0 = c0;
        t1 = c1;
        t2 = c2;
        t3 = c3;
        t4 = c4;
        t5 = c5;
        t6 = c6;
        t7 = c7;
        hit_bar = temp_hit;
        and_val = temp_and;
        dirty_bit_data = temp_dirty_bit;
    end

endmodule

