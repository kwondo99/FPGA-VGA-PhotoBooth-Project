`timescale 1ns / 1ps

// =====================================================
// setup_rom
//  - Holds the OV7670 register table as {reg_addr, reg_data} words,
//    initialized from setup_table.mem.
// =====================================================
module setup_rom(
    input  logic [6:0] setup_idx,
    output logic [7:0] reg_addr,
    output logic [7:0] reg_data
);

    logic [15:0] config_mem [0:78];

    initial begin
        $readmemh("setup_table.mem", config_mem);
    end

    always_comb begin
        {reg_addr, reg_data} = config_mem[setup_idx];
    end

endmodule
