/*
 * Copyright (c) 2026 fivetonsofflax
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_parakeet (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

    wire        hsync_w, vsync_w, vis;
    wire [9:0]  hpos, vpos;
    hvsync_generator vga_sync_gen (
        .clk(clk), .reset(~rst_n),
        .hsync(hsync_w), .vsync(vsync_w),
        .display_on(vis), .hpos(hpos), .vpos(vpos)
    );

    wire dot = (hpos[9:2] == 8'd80) & (vpos[9:2] == 8'd60);
    wire [5:0] pix_color = vis ? {6{dot}} : 6'b0;

    assign uo_out = {hsync_w, pix_color[0], pix_color[2], pix_color[4],
                     vsync_w, pix_color[1], pix_color[3], pix_color[5]};
endmodule
