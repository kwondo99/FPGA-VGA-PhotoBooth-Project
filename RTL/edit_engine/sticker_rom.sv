`timescale 1ns / 1ps

// =====================================================
// sticker_rom
//  - 4 slots (idx 0-3) x 4 sizes, matching the system controller's 2-bit
//    sticker ID. Data comes from a single generated file, sticker_rom_4slot.mem.
//    Slots: idx0=heart, idx1=star, idx2=smiley, idx3=empty (fully transparent).
//  - Each size is rendered and stored separately at native resolution
//    (see gen_sticker_rom.py), instead of storing one 32x32 original and
//    downsampling for smaller sizes -- downsampling produced visible
//    aliasing at small sizes. x/y are therefore in-box coordinates
//    (0 .. len-1) for the requested size, not fixed to a 32x32 grid.
//  - Each 4-slot ROM entry is 2048 words, holding all sizes at fixed offsets:
//      size=3 (32x32): local offset    0 -  1023
//      size=2 (16x16): local offset 1024 -  1279
//      size=1 ( 8x8 ): local offset 1280 -  1343
//      size=0 ( 4x4 ): local offset 1344 -  1359
//    (remaining range is padding, all transparent)
//  - Full address is {idx(2 bit), local_offset(11 bit)} = 4*2048 = 8192 words.
//    All sizes are powers of two, so the address is built with bit
//    concatenation/shifts only, no multiply.
//  - Word format (16-bit hex): [15]=transparent, [11:0]=RGB444
//  - 1-clock synchronous read (infers BRAM)
// =====================================================
module sticker_rom (
    input  logic       clk,
    input  logic [1:0] idx,  // 2-bit slot select, matches SC's 4 selectable slots
    input  logic [1:0] size,       // same code as i_stk_size: 0=4x4 1=8x8 2=16x16 3=32x32
    input  logic [4:0] x,          // 0 .. (side length for this size - 1)
    input  logic [4:0] y,
    output logic [11:0] rgb,
    output logic        transparent
);

    logic [15:0] mem [0:8191];  // 4 slots * 2048 words, half the BRAM of a full 32x32-only ROM
    initial $readmemh("sticker_rom_4slot.mem", mem);  // combined init file for the 4 retained slots

    // Local address within a size's slot region. Since size is always a power
    // of two (32/16/8/4), y*len+x reduces to concatenating y's and x's low
    // bits directly -- no multiplier needed. x/y are guaranteed to be within
    // 0 .. len-1 (marker coordinate minus the box origin), so bit widths are
    // left unsliced (iverilog handles constant part-select poorly in
    // always_comb, hence the plain addition instead).
    logic [10:0] local_addr;
    always_comb begin
        case (size)
            2'd3:    local_addr = 11'd0    + {y, x};             // 32x32: y*32+x
            2'd2:    local_addr = 11'd1024 + (11'(y) << 4) + x;  // 16x16: y*16+x
            2'd1:    local_addr = 11'd1280 + (11'(y) << 3) + x;  //  8x8 : y*8+x
            default: local_addr = 11'd1344 + (11'(y) << 2) + x;  //  4x4 : y*4+x
        endcase
    end

    logic [12:0] addr;  // 2-bit idx + 11-bit local address
    assign addr = {idx, local_addr};

    logic [15:0] data_d1;
    always_ff @(posedge clk)
        data_d1 <= mem[addr];

    assign rgb         = data_d1[11:0];
    assign transparent = data_d1[15];

endmodule
