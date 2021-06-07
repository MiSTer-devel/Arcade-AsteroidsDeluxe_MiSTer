//============================================================================
//  Arcade: Asteroids-Deluxe
//
//  Port to MiSTer
//  Copyright (C) 2018 
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,  
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;

`include "build_id.v" 
localparam CONF_STR = {
	"A.ASTDELUX;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"O34,Language,English,German,French,Spanish;",
//	"O56,Ships,2-4,3-5,4-6,5-7;", system locks up when activating above 3-5
	"-;",
	"OA,Background Graphic,On,Off;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Thrust,Shield,Start,Coin;",	
	"jn,A,B,X,Start,R;",
	"jp,B,A,Y,Start,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_25, clk_50, clk_100;
wire clk_mem = clk_100;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_50),	
	.outclk_1(clk_25),	
	.outclk_2(clk_6),	
	.outclk_3(clk_100),	
	.locked(pll_locked)
);


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

wire [10:0] ps2_key;

wire [15:0] joy_0, joy_1;
wire [15:0] joy = joy_0 | joy_1;
wire        forced_scandoubler;
wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
   .clk_sys(clk_25),
   .HPS_BUS(HPS_BUS),

   .conf_str(CONF_STR),

   .buttons(buttons),
   .status(status),
   .status_menumask(direct_video),
   .forced_scandoubler(forced_scandoubler),
   .gamma_bus(gamma_bus),
   .direct_video(direct_video),

   .ioctl_download(ioctl_download),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .ioctl_index(ioctl_index),
	
   .sdram_sz(sdram_sz),

   .joystick_0(joy_0),
   .joystick_1(joy_1),
   .ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_25) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'h03a: btn_fire         <= pressed; // M
			'h005: btn_one_player   <= pressed; // F1
			'h006: btn_two_players  <= pressed; // F2
			'h01C: btn_left      	<= pressed; // A
			'h023: btn_right      	<= pressed; // D
			'h004: btn_coin  	<= pressed; // F3
			'h04b: btn_thrust  	<= pressed; // L
			'h042: btn_shield  	<= pressed; // K
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h014: btn_fire        <= pressed; // ctrl
			'h011: btn_thrust      <= pressed; // Lalt
			'h029: btn_shield      <= pressed; // space
			// JPAC/IPAC/MAME Style Codes
			'h016: btn_one_player  <= pressed; // 1
			'h01E: btn_two_players <= pressed; // 2
			'h02E: btn_coin        <= pressed; // 5
			'h036: btn_coin        <= pressed; // 6
			
		endcase
	end
end

reg btn_right = 0;
reg btn_left = 0;
reg btn_one_player = 0;
reg btn_two_players = 0;
reg btn_fire = 0;
reg btn_coin = 0;
reg btn_thrust = 0;
reg btn_shield = 0;

wire [7:0] BUTTONS = {~btn_right & ~joy[0],~btn_left & ~joy[1],~btn_one_player & ~joy[7],~btn_two_players,~btn_fire & ~joy[4],~btn_coin & ~joy[7],~btn_thrust & ~joy[5],~btn_shield & ~joy[6]};

///////////////////////////////////////////////////////////////////


wire hblank, vblank;
wire hs, vs;
wire [3:0] r,g,b;

reg ce_pix;
always @(posedge clk_50) begin
       ce_pix <= !ce_pix;
end

wire fg = |{r,g,b};

arcade_video #(640,480,12) arcade_video
(
        .*,

        .clk_video(clk_50),
        .RGB_in(status[10] ? {r,g,b}  : (fg && !bg_a) ? {r,g,b} : {bg_r,bg_g,bg_b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .forced_scandoubler(0),
        .no_rotate(1),
        .rotate_ccw(0),
        .fx(0)
);



wire reset = (RESET | status[0] | buttons[1] | ioctl_download);
wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire [1:0] lang = status[4:3];
wire [1:0] ships = status[6:5];

ASTEROIDS_TOP ASTEROIDS_TOP
(
   .BUTTON(BUTTONS),
   .LANG(lang),
   .SHIPS(ships),
   .AUDIO_OUT(audio),
   .dn_addr(ioctl_addr[15:0]),
   .dn_data(ioctl_dout),
   .dn_wr(ioctl_wr&(ioctl_index==0)),	
   .VIDEO_R_OUT(r),
   .VIDEO_G_OUT(g),
   .VIDEO_B_OUT(b),
   .HSYNC_OUT(hs),
   .VSYNC_OUT(vs),
   .VGA_DE(vgade),
   .VID_HBLANK(hblank),
   .VID_VBLANK(vblank),

   .RESET_L (~reset),	
   .clk_6(clk_6),
   .clk_25(clk_25)
);


wire bg_download = ioctl_download && (ioctl_index == 2);

reg [7:0] ioctl_dout_r;
always @(posedge clk_25) if(ioctl_wr & ~ioctl_addr[0]) ioctl_dout_r <= ioctl_dout;

wire [15:0] pic_data;
wire ram_ready;
sdram sdram
(
        .*,

        .init(~pll_locked),
        .clk(clk_mem),
        .addr(bg_download ? ioctl_addr[24:0] : pic_addr),
        .dout(pic_data),
        .din(ioctl_dout),
        .we(bg_download ? ioctl_wr : 1'b0),
        .rd(pic_req),
	.ready(ram_ready)
);

reg        pic_req;
reg [24:0] pic_addr;
reg  [3:0] bg_r,bg_g,bg_b,bg_a;

always @(posedge clk_50) begin
        reg old_vs;
        reg use_bg = 0;

        if(bg_download && sdram_sz[2:0]) use_bg <= 1;

        pic_req <= 0;

        if(use_bg) begin
                if(ce_pix) begin
                        old_vs <= vs;
                        {bg_b,bg_a,bg_r,bg_g} <= pic_data;
                        if(~(hblank|vblank)) begin
                                pic_addr <= pic_addr + 2'd2;
                                pic_req <= 1;
                        end

                        if(~old_vs & vs) begin
                                pic_addr <= 0;
                                pic_req <= 1;
                        end
                end
        end
        else begin
                {bg_a,bg_b,bg_g,bg_r} <= 0;
        end
end


endmodule
