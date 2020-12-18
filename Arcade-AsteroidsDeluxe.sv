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
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	`ifdef USE_FB
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
	`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz
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
assign VGA_SCALER= 0;

assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

wire [1:0] ar = status[15:14];

assign VIDEO_ARX =  (!ar) ? ( 8'd4) : (ar - 1'd1);
assign VIDEO_ARY =  (!ar) ? ( 8'd3) : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.ASTDELUX;;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	//"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O78,Language,English,German,French,Spanish;",
	"O56,Ships,2-4,3-5,4-6,5-7;",// system locks up when activating above 3-5
	"OBC,Bonus,10000,12000,15000,None;",
	"-;",
	"OA,Background Graphic,On,Off;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Thrust,Shield,Start 1P,Start 2P,Coin;",	
	"jn,A,B,X,Start,Select,R;",
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
   .joystick_1(joy_1)
);

//	"J1,Fire,Thrust,Shield,Start 1P,Start 2P,Coin;",	
//    [0,1,2,3] Fire 4, Thrust 5, Shield 6, One Player 7, Two Player 8, Coin 9
wire [7:0] BUTTONS = {~joy[0],~joy[1],~joy[7],~joy[8],~joy[4],~joy[9],~joy[5],~joy[6]};

///////////////////////////////////////////////////////////////////


wire hblank, vblank;
wire hs, vs;
wire [3:0] r,g,b;

reg ce_pix;
always @(posedge clk_50) begin
       ce_pix <= !ce_pix;
end

wire fg = |{r,g,b};

arcade_video #(640,12) arcade_video
(
        .*,

        .clk_video(clk_50),
        .RGB_in(status[10] ? {r,g,b}  : (fg && !bg_a) ? {r,g,b} : {bg_r,bg_g,bg_b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .forced_scandoubler(0),
        .fx(0)
);



wire reset = (RESET | status[0] | buttons[1] | ioctl_download);
wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire [1:0] lang = status[8:7];
wire [1:0] ships = status[6:5];

ASTEROIDS_TOP ASTEROIDS_TOP
(
   .BUTTON(BUTTONS),
   .LANG(lang),
   .SHIPS(ships),
	.BONUS(status[12:11]),
   .AUDIO_OUT(audio),
   .dn_addr(ioctl_addr[15:0]),
   .dn_data(ioctl_dout),
   .dn_wr(ioctl_wr&(ioctl_index==0)),	
   .VIDEO_R_OUT(r),
   .VIDEO_G_OUT(g),
   .VIDEO_B_OUT(b),
   .HSYNC_OUT(hs),
   .VSYNC_OUT(vs),
   .VGA_DE(),
   .VID_HBLANK(hblank),
   .VID_VBLANK(vblank),

   .RESET_L (~reset),	
   .clk_6(clk_6),
   .clk_25(clk_25)
);


wire bg_download = ioctl_download && (ioctl_index == 2);


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
