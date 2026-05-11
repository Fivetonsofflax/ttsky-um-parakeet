// Copyright (c) 2026 Fivetonsofflax
// SPDX-License-Identifier: GPL3
// Project: Parakeet
// Description: This is based on demo tutorial 34 of my new node based verilog tool. 
//               Custom mode 7 tyle demo for ttsky26a. Built custom tool to aid in 
//               assisted development. Gate count should be low enough. 
//               Should work with VGA Playground.

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
    wire rst = ~rst_n;
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;
    // Spare bus inputs surfaced to tutorial bodies (free pins on the playground).
    wire [3:0] bus_dip = ui_in[3:0];   // 4 spare DIP-style inputs
    wire [7:0] bus_aux = uio_in;       // 8 spare bidir pins, default 0
    wire _unused = &{ena, ui_in[7], 1'b0};

    // VGA timing (provided by playground).
    wire        hsync_w, vsync_w, vis;
    wire [9:0]  hpos, vpos;
    hvsync_generator vga_sync_gen (
        .clk(clk), .reset(rst),
        .hsync(hsync_w), .vsync(vsync_w),
        .display_on(vis), .hpos(hpos), .vpos(vpos)
    );

    // Gamepad serial driver (provided by playground).
    wire inp_b, inp_y, inp_select, inp_start;
    wire inp_up, inp_down, inp_left, inp_right;
    wire inp_a, inp_x, inp_l, inp_r;
    gamepad_pmod_single driver (
        .rst_n(rst_n), .clk(clk),
        .pmod_data (ui_in[6]), .pmod_clk (ui_in[5]), .pmod_latch(ui_in[4]),
        .b(inp_b), .y(inp_y), .select(inp_select), .start(inp_start),
        .up(inp_up), .down(inp_down), .left(inp_left), .right(inp_right),
        .a(inp_a), .x(inp_x), .l(inp_l), .r(inp_r)
    );
    wire gp_start_held = inp_start;
    wire gp_a_held     = inp_a;
    wire gp_b_held     = inp_b;
    wire gp_left_held  = inp_left;
    wire gp_right_held = inp_right;
    wire gp_up_held    = inp_up;
    wire gp_down_held  = inp_down;
    // Spare gamepad buttons exposed to tutorial bodies.
    wire gp_select     = inp_select;
    wire gp_y          = inp_y;
    wire gp_x          = inp_x;
    wire _unused_pad = &{inp_l, inp_r, 1'b0};



    // ─── Frame tick: 1-cycle pulse on entering vblank (vpos == 480) ───
    // Most tutorials do not animate, but the few that do (bouncing dot,
    // rotated rect, starfield) want a "once per frame" pulse so they can
    // step their state. We always emit it because it costs ~10 gates and
    // makes the wrappers identical across all tutorials.
    reg vblank_d;
    wire in_vblank = (vpos >= 10'd480);
    wire frame_tick = in_vblank & ~vblank_d;
    always @(posedge clk) vblank_d <= in_vblank;

    // Free-running 8-bit frame counter — wraps every 256 frames (~4.27 s
    // at 60 Hz). Useful for animation, blinking, palette cycling.
    reg [7:0] frame_count;
    always @(posedge clk) begin
        if (rst) frame_count <= 8'd0;
        else if (frame_tick) frame_count <= frame_count + 8'd1;
    end

    // === TUTORIAL 34: OUTRUN RACE LITE — solid-box banner, ≈800 gates ===
    //
    // Tut 33's race FSM, trimmed harder than Tut 33-lite v1:
    //   • cam_x steering removed (road still scrolls via road_z)
    //   • brake + auto-cruise removed (A button = ramp speed up, decay otherwise)
    //   • Mode-7 LUT halved (32 entries, 8-px depth bands)
    //   • narrower road_z register (12-bit), no horizon line
    //   • on_road via sign-bit window (no abs() negation adder)
    //   • banner is one shared 160×40 box, colour cycles by stage

    reg [2:0] race_stage;
    reg [7:0] stage_timer;
    wire driving = (race_stage == 3'd2) || (race_stage == 3'd3);
    // Shared 256-frame stage duration.
    wire stage_done = (stage_timer == 8'hFF);

    always @(posedge clk) begin
        if (rst) begin
            race_stage  <= 3'd0;
            stage_timer <= 8'd0;
        end else if (frame_tick) begin
            if (gp_start_held) begin
                race_stage  <= 3'd0;
                stage_timer <= 8'd0;
            end else if (stage_done) begin
                stage_timer <= 8'd0;
                race_stage  <= (race_stage == 3'd4) ? 3'd0 : race_stage + 3'd1;
            end else begin
                stage_timer <= stage_timer + 8'd1;
            end
        end
    end

    // Speed: 4-bit ramp on A, decay otherwise. No brake, no cruise band.
    // For the simulator: even with no input, give the road a small idle
    // scroll so the tutorial visibly animates from the first frame.
    reg [3:0]  speed;
    reg [11:0] road_z;
    wire [3:0] speed_eff = driving ? speed : 4'd2;
    always @(posedge clk) begin
        if (rst) begin
            speed  <= 4'd0;
            road_z <= 12'd0;
        end else if (frame_tick) begin
            if (gp_start_held) begin
                speed  <= 4'd0;
                road_z <= 12'd0;
            end else if (driving) begin
                if (gp_a_held) begin
                    if (speed != 4'hF) speed <= speed + 4'd1;
                end else begin
                    if (speed != 4'd0) speed <= speed - 4'd1;
                end
            end else begin
                speed <= 4'd0;
            end
            road_z <= road_z + {8'd0, speed_eff};
        end
    end

    // Mode-7: 32-entry LUT, 8-px depth bands (vpos_below[7:3]).
    wire is_floor = (vpos >= 10'd240);
    wire [9:0] vpos_below = vpos - 10'd240;
    wire [4:0] depth_idx = vpos_below[7:3];
    reg [10:0] z_factor;
    always @(*) begin
        case (depth_idx)
            5'd0:  z_factor = 11'd1280; 5'd1:  z_factor = 11'd560;
            5'd2:  z_factor = 11'd352;  5'd3:  z_factor = 11'd256;
            5'd4:  z_factor = 11'd200;  5'd5:  z_factor = 11'd164;
            5'd6:  z_factor = 11'd140;  5'd7:  z_factor = 11'd121;
            5'd8:  z_factor = 11'd107;  5'd9:  z_factor = 11'd96;
            5'd10: z_factor = 11'd87;   5'd11: z_factor = 11'd80;
            5'd12: z_factor = 11'd74;   5'd13: z_factor = 11'd68;
            5'd14: z_factor = 11'd64;   5'd15: z_factor = 11'd60;
            5'd16: z_factor = 11'd56;   5'd17: z_factor = 11'd53;
            5'd18: z_factor = 11'd50;   5'd19: z_factor = 11'd48;
            5'd20: z_factor = 11'd45;   5'd21: z_factor = 11'd43;
            5'd22: z_factor = 11'd41;   5'd23: z_factor = 11'd39;
            5'd24: z_factor = 11'd37;   5'd25: z_factor = 11'd36;
            5'd26: z_factor = 11'd34;   5'd27: z_factor = 11'd33;
            5'd28: z_factor = 11'd32;   5'd29: z_factor = 11'd31;
            5'd30: z_factor = 11'd30;   5'd31: z_factor = 11'd29;
        endcase
    end

    // dx_road = hpos - 320 (no cam_x steering).
    wire signed [11:0] dx_road = $signed({1'b0, hpos}) - 12'sd320;
    wire signed [22:0] wx = dx_road * $signed({1'b0, z_factor});
    wire [21:0] wy = {{11{1'b0}}, z_factor} + {{10{1'b0}}, road_z};

    wire chk_grass = wx[16] ^ wy[6];
    // on_road via sign-bit window: |wx| < 6144 ↔ wx[22:13] is all-0 or all-1.
    wire [9:0] wx_hi = wx[22:13];
    wire on_road = (wx_hi == 10'd0) || (wx_hi == 10'h3FF);

    wire [5:0] sky      = 6'b10_00_10;
    wire [5:0] grass    = chk_grass ? 6'b00_10_00 : 6'b00_11_00;
    wire [5:0] asphalt  = wy[5] ? 6'b01_01_01 : 6'b10_10_10;
    wire [5:0] floor_color = on_road ? asphalt : grass;
    wire [5:0] road_color  = is_floor ? floor_color : sky;

    // ---- Solid-box banner ----
    // One 160×50 rect shared across stages 0..4. Stage 3 hides it.
    // Sits high in the sky (well above the horizon at vpos=240) so it
    // reads as a UI element instead of a roadside billboard.
    wire box = (hpos >= 10'd240) && (hpos < 10'd400)
            && (vpos >= 10'd80)  && (vpos < 10'd130);

    // GO overlay (stage 4 only). G shares the O ring construction:
    //   O = o_outer ∧ ¬o_inner             (2 rects)
    //   G = g_outer ∧ ¬g_inner ∧ ¬g_cut    (3 rects, cut opens top-right)
    wire o_outer = (hpos >= 10'd340) && (hpos < 10'd368)
                && (vpos >= 10'd86)  && (vpos < 10'd124);
    wire o_inner = (hpos >= 10'd346) && (hpos < 10'd362)
                && (vpos >= 10'd94)  && (vpos < 10'd116);
    wire o_pix   = o_outer && !o_inner;

    wire g_outer = (hpos >= 10'd272) && (hpos < 10'd300)
                && (vpos >= 10'd86)  && (vpos < 10'd124);
    wire g_inner = (hpos >= 10'd278) && (hpos < 10'd294)
                && (vpos >= 10'd94)  && (vpos < 10'd116);
    wire g_cut   = (hpos >= 10'd288) && (hpos < 10'd300)
                && (vpos >= 10'd86)  && (vpos < 10'd102);
    wire g_pix   = g_outer && !g_inner && !g_cut;
    wire go_pix  = g_pix || o_pix;

    // Per-stage box colour. Stage 3 hides the box (box_visible=0).
    wire box_visible = (race_stage != 3'd3);
    wire [5:0] box_color =
        (race_stage == 3'd0) ? 6'b11_00_00 :   // red
        (race_stage == 3'd1) ? 6'b11_11_00 :   // yellow
        (race_stage == 3'd2) ? 6'b00_11_00 :   // green
                               6'b00_11_00;    // stage 4: green base, GO punched white

    // Stage 4: GO letters render in white over the green box.
    wire show_go = (race_stage == 3'd4) && go_pix;
    wire [5:0] banner_color = show_go ? 6'b11_11_11 : box_color;
    wire banner_on = box && box_visible;

    wire [5:0] color = banner_on ? banner_color : road_color;
    wire [5:0] pix_color = vis ? color : 6'b0;

    // TinyVGA Pmod pin order (matches playground gamepad preset).
    assign uo_out = {hsync_w, pix_color[0], pix_color[2], pix_color[4],
                     vsync_w, pix_color[1], pix_color[3], pix_color[5]};
endmodule
