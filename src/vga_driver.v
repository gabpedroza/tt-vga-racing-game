/*
 * Racing game for VGA: dodge the traffic.
 *
 * To play, open Inspect > VGA output and press Run. Use the switches under the
 * picture, or the keyboard:
 *   ui_in[0]  steer left     (Left arrow, A or 1)
 *   ui_in[1]  steer right    (Right arrow, D or 2)
 *   ui_in[2]  boost          (Up arrow, W, Space or 3)
 *
 * The score bar at the top grows while you survive, and the traffic speeds up
 * as it grows. A crash flashes the screen red and starts the run again.
 *
 * How this file is laid out:
 *   1. SETTINGS   Colours, sizes and speeds. Change anything here and press Run
 *   2. WIRING     The pins and the sync generator. Leave this as it is.
 *   3. THE GAME   The rules: steering, traffic, crashes and the score.
 *   4. DRAWING    The colour of every pixel, from where things are.
 */

`default_nettype none

module tt_um_gabpedroza_vga_racing_game (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ========================================================================
    // 1. SETTINGS
    //    Change these freely. Nothing below needs editing when you do.
    // ========================================================================
    localparam BOARD_SIZE = 4;
    localparam [5:0] WORM_BOX_SIZE = 10'((40/BOARD_SIZE));
    localparam [5:0] WORM_BOX_BORDER = 10'(1);
    localparam [5:0] WORM_BOX_Y_CENTRE = 10'(WORM_BOX_SIZE/2 + WORM_BOX_BORDER);
    localparam BOARD_BITS = $clog2(BOARD_SIZE);
    localparam [5:0] HOLE_COLOUR = 6'b100100;
    localparam [5:0] BIRD_HEAD_SIZE = 10'd10;
    localparam [5:0] BIRD_BEAK_SIZE = 10'd4;
    localparam [5:0] BIRD_BEAK_LENGTH = 10'd4;
    localparam [5:0] BIRD_COLOUR = 6'b111000;
    localparam [5:0] BIRD_BEAK_COLOUR = 6'b110100;
    localparam [5:0] WORM_COLOUR = 6'b110101;
    localparam [5:0] WORM_NECK_COLOUR = 6'b110000; 
    localparam [5:0] WORM_SIZE = 10'(WORM_BOX_SIZE/6);
    localparam [5:0] WORM_LENGTH = 10'(WORM_BOX_SIZE/2 + BIRD_BEAK_LENGTH + 3);
    localparam [5:0] WORM_HEAD_SIZE = 10'(3);
    localparam [5:0] WORM_NECK_SIZE = 10'(2);


    // Colours. Six bits: two for red, two for green, two for blue (6'bRRGGBB).
    // Each pair goes from 00 (off) to 11 (full), so 6'b110000 is pure red.
    localparam [5:0] CAR_COLOUR     = 6'b000011;   // red
    localparam [5:0] WINDOW_COLOUR  = 6'b001011;   // glass
    localparam [5:0] WHEEL_COLOUR   = 6'b010101;   // dark grey
    localparam [5:0] TRAFFIC_COLOUR = 6'b111000;   // amber
    localparam [5:0] TRAFFIC_SHADE  = 6'b100000;   // the darker strip along its top
    localparam [5:0] ROAD_COLOUR    = 6'b010101;   // tarmac
    localparam [5:0] LINE_COLOUR    = 6'b111110;   // the dashed centre line
    localparam [5:0] KERB_COLOUR_A  = 6'b110000;   // the kerb is striped red ...
    localparam [5:0] KERB_COLOUR_B  = WORM_COLOUR;   // ... and white
    localparam [5:0] GRASS_COLOUR_A = 6'b001000;   // the two greens of the grass
    localparam [5:0] GRASS_COLOUR_B = 6'b000100;
    localparam [5:0] SCORE_COLOUR   = 6'b001100;   // green

    // Sizes, in pixels. The screen is 640 wide and 480 tall.
    localparam [9:0] CAR_W     = 10'd16;
    localparam [9:0] CAR_H     = 10'd16;
    localparam [9:0] TRAFFIC_W = 10'd32;   // keep to 48 or less, or it overhangs the kerb
    localparam [9:0] TRAFFIC_H = 10'd32;
    localparam       GRASS_BIT = 4;        // size of the grass squares: 3 is 8 pixels, 4 is 16, 5 is 32

    // Speeds, in pixels per frame. There are 60 frames every second.
    localparam [9:0] STEER_STEP  = 10'd4;  // how far the car moves sideways
    localparam [4:0] BASE_SPEED  = 5'd3;   // how fast the traffic comes at the start
    localparam [4:0] BOOST_SPEED = 5'd3;   // added while boost is held
                                           // keep BASE_SPEED + BOOST_SPEED to 16 or less

    // How long the red flash lasts after a crash, in frames. 63 at most.
    localparam [5:0] CRASH_FRAMES = 6'b111111;

    // The road. These numbers fit together, so change them as a set.
    localparam [9:0] ROAD_L    = 10'd160;  // outer edge of the left kerb
    localparam [9:0] ROAD_R    = 10'd480;  // outer edge of the right kerb
    localparam [9:0] LANE_L    = 10'd168;  // the part you can drive on
    localparam [9:0] LANE_R    = 10'd472;
    localparam [9:0] CAR_Y     = 10'd400;  // how far down the screen the car sits
    localparam [9:0] CAR_START = 10'd304;  // where the car starts each run

    // ========================================================================
    // 2. WIRING
    //    The pins and the monitor's timing. Leave this section as it is.
    // ========================================================================

    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [9:0] pix_x;          // the pixel being drawn now: 0 to 639 across
    wire [5:0] rpix_x = pix_x[9:4];
    wire [9:0] pix_y;          // and 0 to 479 down
    wire [5:0] rpix_y = pix_y[9:4];
    reg  [BOARD_SIZE - 1:0] last_input;
    reg [BOARD_BITS:0] decoded_press;
    reg first_press;

    reg [BOARD_BITS-1:0] last_pressed1;
    reg last_pressed0;
    reg [BOARD_BITS-1:0] bird_choice;
    reg [1:0] life;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // High for one clock as each frame ends. The game moves on once per frame.
    reg  vsync_q;
    wire new_frame = vsync & ~vsync_q;

    // ========================================================================
    // 3. THE GAME
    //    A few registers hold where everything is. They change once per frame.
    // ========================================================================

    reg [BOARD_BITS-1:0] q_markov [(BOARD_SIZE*2)-1:0];

    //wire [9:0] bird_x = 320;
    reg [2:0] bird_x = 3'd4;
    reg bird_y = 0;
    reg [9:0] actual_bird_y;
    always @(*) begin
        if (bird_y == 0) actual_bird_y = 0;
        else actual_bird_y = 30 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE - BIRD_HEAD_SIZE/2;
    end

    //reg [9:0] score;               // frames survived this run, up to 1023
    reg [5:0] crash_timer;         // frames of flash left after a crash, 0 when driving
    reg [4:0] random;             // shifts every clock, so its value looks random

    // The level goes up by one every 64 frames, and each level is one pixel faster.

    // A crash is the car's rectangle overlapping a vehicle's rectangle.


    // How far each vehicle moves this frame. The second is one pixel faster,


    always @(posedge clk) begin
        random  <= {random[3:0], random[4] ^ random[2]};
        vsync_q <= vsync;

        if (~rst_n) begin
            //score       <= 10'd0;
            crash_timer <= 6'b000000;
            first_press <= 0;
            random      <= 5'b00001;
            bird_x <= 3'd4;
            bird_y <= 0;
            life <= 0;
            last_input <= 4'd0;
            decoded_press <= 3'd0;
            q_markov[0] <= 2'd0;
            q_markov[1] <= 2'd0;
            q_markov[2] <= 2'd0;
            q_markov[3] <= 2'd0;
            q_markov[4] <= 2'd0;
            q_markov[5] <= 2'd0;
            q_markov[6] <= 2'd0;
            q_markov[7] <= 2'd0;
            //q_markov[8] <= 2'd0;
            //q_markov[9] <= 2'd0;
            //q_markov[10] <= 2'd0;
            //q_markov[11] <= 2'd0;
            //q_markov[12] <= 2'd0;
            //q_markov[13] <= 2'd0;
            //q_markov[14] <= 2'd0;
            //q_markov[15] <= 2'd0;

        end else begin
            if (~ first_press) begin
                q_markov[random[3:1]] <= random[1:0];
                //q_markov[0] <= random[1:0];
            end
            if (new_frame) begin
                last_input <= ui_in[3:0];
                if((last_input != ui_in[3:0]) & ((last_input | ui_in[3:0]) == ui_in[3:0]))begin // different from last and no buttons turned off => at least one turned on
                    first_press <= 1;
                    if     ((ui_in[3:0] == BOARD_SIZE'(1)) &   (BOARD_SIZE >= 1)) decoded_press <= {1'b1, BOARD_BITS'(0)};
                    else if((ui_in[3:0] == BOARD_SIZE'(2)) &   (BOARD_SIZE >= 2)) decoded_press <= {1'b1, BOARD_BITS'(1)};
                    else if((ui_in[3:0] == BOARD_SIZE'(4)) &   (BOARD_SIZE >= 3)) decoded_press <= {1'b1, BOARD_BITS'(2)};
                    else if((ui_in[3:0] == BOARD_SIZE'(8)) &   (BOARD_SIZE >= 4)) decoded_press <= {1'b1, BOARD_BITS'(3)};
                    else if((ui_in[3:0] == BOARD_SIZE'(16)) &  (BOARD_SIZE >= 5)) decoded_press <= {1'b1, BOARD_BITS'(4)};
                    else if((ui_in[3:0] == BOARD_SIZE'(32)) &  (BOARD_SIZE >= 6)) decoded_press <= {1'b1, BOARD_BITS'(5)};
                    else if((ui_in[3:0] == BOARD_SIZE'(64)) &  (BOARD_SIZE >= 7)) decoded_press <= {1'b1, BOARD_BITS'(6)};
                    else if((ui_in[3:0] == BOARD_SIZE'(128)) & (BOARD_SIZE >= 8)) decoded_press <= {1'b1, BOARD_BITS'(7)};
                    
                end else decoded_press <= {1'b0, decoded_press[BOARD_BITS-1:0]};
                
                if (crash_timer != 6'b000000) begin
                    // ---- after a crash: count the flash down, then start again
                    crash_timer <= crash_timer - 6'd1;
                    if (crash_timer == 6'b000001) begin
                        //score       <= 10'd0;
                        bird_y <= 0;
                        bird_x <= 3'd4;
                    end
                end else if (decoded_press[BOARD_BITS]) begin
                    last_pressed1 <= decoded_press[BOARD_BITS-1:0];
                    last_pressed0 <= last_pressed1[0];
                    q_markov[{last_pressed0, last_pressed1}] <= decoded_press[BOARD_BITS-1:0];
                    bird_choice <= q_markov[{last_pressed0, last_pressed1}];
                    if (q_markov[{last_pressed0, last_pressed1}] == decoded_press[BOARD_BITS-1:0]) life <= life + 2'd1;
                    crash_timer <= 6'b111111;
                    bird_y <= 1;
                    bird_x <= {1'b0, q_markov[{last_pressed0, last_pressed1}]};
                end else begin
                    last_pressed1 <= last_pressed1;
                    last_pressed0 <= last_pressed0;
                    q_markov[{last_pressed0, last_pressed1}] <= q_markov[{last_pressed0, last_pressed1}];
                    bird_choice <= bird_choice;
                end
            end
        end
    end

    // ========================================================================
    // 4. DRAWING
    //    One question for each thing on screen: is this pixel inside it?
    // ========================================================================
    // Bird's horizontal centre, in 16-pixel units.
    // Values 0-3 select the four columns; 4 is the initial centre.
    wire [5:0] bird_centre_x = (bird_x == 3'd4)
                             ? 6'd20
                             : bird_x * 6'd10 + 6'd5;

    // Absolute horizontal distance from the bird's centre.
    wire [5:0] bird_dx = (rpix_x >= bird_centre_x)
                       ? rpix_x - bird_centre_x
                       : bird_centre_x - rpix_x;

    wire [BOARD_SIZE-1:0] is_in_a_hole;
    wire [BOARD_SIZE-1:0] is_in_worm;
    genvar i;
    generate 
        for (i = 0; i < BOARD_SIZE; i = i + 1) begin : worm_box
            assign is_in_a_hole[i] = (rpix_x <= WORM_BOX_SIZE*(i+1) - WORM_BOX_BORDER) & (rpix_x >= WORM_BOX_SIZE*i + WORM_BOX_BORDER);
            assign is_in_worm[i] = (last_pressed1 == i) & (WORM_BOX_SIZE*(2*i+1)/2 - WORM_SIZE/2 <= rpix_x & rpix_x <= WORM_BOX_SIZE*(2*i+1)/2 + WORM_SIZE/2);
        end
    endgenerate
    wire in_worm_box = ((30 - WORM_BOX_SIZE + WORM_BOX_BORDER<= rpix_y) & (30 - WORM_BOX_BORDER >= rpix_y)) & (|is_in_a_hole); // no adder
    wire in_worm = (30 - WORM_BOX_Y_CENTRE >= rpix_y) & (rpix_y >= 30 - WORM_BOX_Y_CENTRE - WORM_LENGTH)  & (|is_in_worm); // no adder
    wire in_worm_neck = 0;//(30 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE + WORM_NECK_SIZE >= rpix_y) & (rpix_y >= 30 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE)  & (|is_in_worm); // no adder

    wire in_bird_head = (rpix_y <= actual_bird_y + BIRD_HEAD_SIZE/2)
                      & (bird_dx <= BIRD_HEAD_SIZE/2);

    wire in_bird_white_eye = 0;
    wire in_bird_black_eye = 0;

    wire in_bird_beak = (rpix_y <= actual_bird_y + BIRD_HEAD_SIZE/2 + BIRD_BEAK_LENGTH)
                      & (bird_dx <= BIRD_BEAK_SIZE/2);


    wire in_grass = rpix_x[0]^rpix_y[0];
    //wire in_bird_beak = 
    // The road, its striped kerbs and its dashed centre line. Adding scroll to
    // pix_y is what makes the stripes move down the screen.

    // The car, with a window and four wheels.

    // The two vehicles, each with a darker strip six pixels deep along the top.


    // The score bar: one pixel longer for every two frames survived.


    // The first line that matches wins, so anything higher up is drawn on top
    // of anything lower down. Move a line to change what covers what.
    reg [5:0] colour;
    always @(*) begin
        if (~video_active)       colour = 6'b000000;
        //colour = 6'b000000;
        else if (in_bird_white_eye) colour = 6'b111111;
        else if (in_bird_black_eye) colour = 6'b000000;
        else if (in_bird_head)   colour = BIRD_COLOUR;
        else if (in_bird_beak)   colour = BIRD_BEAK_COLOUR;
        else if (in_worm_neck & |crash_timer)   colour = WORM_NECK_COLOUR;
        else if (in_worm & |crash_timer)        colour = WORM_COLOUR;
        else if (in_worm_box)    colour = HOLE_COLOUR;
        //else if (in_score)       colour = SCORE_COLOUR;
        //else if (in_wheel)       colour = WHEEL_COLOUR;
        //else if (in_window)      colour = WINDOW_COLOUR;
        //else if (in_car)         colour = CAR_COLOUR;
        //else if (in_traffic)     colour = in_shade ? TRAFFIC_SHADE : TRAFFIC_COLOUR;
        //else if (in_kerb)        colour = kerb_stripe ? KERB_COLOUR_A : KERB_COLOUR_B;
        //else if (in_centre_line) colour = LINE_COLOUR;
        //else if (in_road)        colour = ROAD_COLOUR;
        else                     colour = (in_grass)? {2'b00, life, 2'b00} : GRASS_COLOUR_A;
    end

    // The crash flash: for four frames in every eight, full red with green and blue halved.
    wire       flash  = (crash_timer != 6'b000001) & crash_timer[3] & (bird_choice == last_pressed1);
    wire [5:0] shown  = flash ? {2'b11, colour[3:2] >> 1, colour[1:0] >> 1} : colour;

    // ---- to the pins, in the order the TinyVGA adapter expects. Leave as it is.
    wire [1:0] R = shown[5:4];
    wire [1:0] G = shown[3:2];
    wire [1:0] B = shown[1:0];

    assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused_ok = &{ena, uio_in, ui_in[7:3]};

endmodule
