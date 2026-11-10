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
 *   1. SETTINGS   Colours, sizes and speeds. Change anything here and press Run.
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
    localparam [9:0] WORM_BOX_SIZE = 10'((640/BOARD_SIZE));
    localparam [9:0] WORM_BOX_BORDER = 10'(16);
    localparam [9:0] WORM_BOX_Y_CENTRE = 10'(WORM_BOX_SIZE/2 + WORM_BOX_BORDER);
    localparam BOARD_BITS = $clog2(BOARD_SIZE);
    localparam [5:0] HOLE_COLOUR = 6'b100100;
    localparam [9:0] BIRD_HEAD_SIZE = 10'd150;
    localparam [9:0] BIRD_BEAK_SIZE = 10'd64;
    localparam [9:0] BIRD_BEAK_LENGTH = 10'd70;
    localparam [5:0] BIRD_COLOUR = 6'b111000;
    localparam [5:0] BIRD_BEAK_COLOUR = 6'b110100;
    localparam [5:0] WORM_COLOUR = 6'b110101;
    localparam [5:0] WORM_NECK_COLOUR = 6'b110000; 
    localparam [9:0] WORM_SIZE = 10'(WORM_BOX_SIZE/6);
    localparam [9:0] WORM_LENGTH = 10'(WORM_BOX_SIZE/2 + BIRD_BEAK_LENGTH + 48);
    localparam [9:0] WORM_HEAD_SIZE = 10'(48);
    localparam [9:0] WORM_NECK_SIZE = 10'(32);


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
    localparam [6:0] CRASH_FRAMES = 7'd70;

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
    wire [9:0] pix_y;          // and 0 to 479 down
    reg  [$bits(ui_in) - 1:0] last_input;
    reg [BOARD_BITS:0] decoded_press;
    reg first_press;

    reg [BOARD_BITS-1:0] last_pressed [1:0];
    reg [BOARD_BITS-1:0] bird_choice;


    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    wire steer_left  = ui_in[0] & ~ui_in[1];
    wire steer_right = ui_in[1] & ~ui_in[0];
    wire boost       = ui_in[2] & ~ui_in[3];
    wire back        = ui_in[3] & ~ui_in[2];
    reg select;

    always @(posedge clk) begin
        select <= ui_in[4] & ~ select;
    end

    // High for one clock as each frame ends. The game moves on once per frame.
    reg  vsync_q;
    wire new_frame = vsync & ~vsync_q;

    // ========================================================================
    // 3. THE GAME
    //    A few registers hold where everything is. They change once per frame.
    // ========================================================================

    reg [BOARD_BITS-1:0] q_markov [(BOARD_SIZE*BOARD_SIZE)-1:0];

    //wire [9:0] bird_x = 320;
    reg [9:0] bird_x = 320;
    reg [9:0] bird_y = 0;

    reg [9:0] car_x;               // left edge of the car
    reg [9:0] car_y;               // left edge of the car
    reg [9:0] traffic0_x;          // top left corner of each of the two vehicles
    reg [9:0] traffic0_y;
    reg [9:0] traffic1_x;
    reg [9:0] traffic1_y;
    reg [9:0] score;               // frames survived this run, up to 1023
    reg [9:0] scroll;              // how far the road has moved, for the stripes
    reg [6:0] crash_timer;         // frames of flash left after a crash, 0 when driving
    reg [15:0] random;             // shifts every clock, so its value looks random

    // The level goes up by one every 64 frames, and each level is one pixel faster.
    wire [3:0] level = score[9:6];
    wire [4:0] speed = BASE_SPEED + {1'b0, level} + (boost ? BOOST_SPEED : 5'd0);

    // The furthest left and right the car can go and still be on the road.
    localparam [9:0] CAR_MIN = LANE_L;
    localparam [9:0] CAR_MAX = LANE_R - CAR_W;

    // Where a vehicle joins the road: somewhere across the lane, 256 places.
    wire [9:0] random_x0 = LANE_L + {2'b00, random[7:0]};
    wire [9:0] random_x1 = LANE_L + {2'b00, random[15:8]};

    // A crash is the car's rectangle overlapping a vehicle's rectangle.
    wire hit0 = (car_x < traffic0_x + TRAFFIC_W) & (traffic0_x < car_x + CAR_W) &
                (CAR_Y < traffic0_y + TRAFFIC_H) & (traffic0_y < CAR_Y + CAR_H);
    wire hit1 = (car_x < traffic1_x + TRAFFIC_W) & (traffic1_x < car_x + CAR_W) &
                (CAR_Y < traffic1_y + TRAFFIC_H) & (traffic1_y < CAR_Y + CAR_H);
    wire crash = hit0 | hit1;

    // How far each vehicle moves this frame. The second is one pixel faster,
    // so the two do not stay in step.
    wire [9:0] step0 = {5'd0, speed};
    wire [9:0] step1 = {5'd0, speed} + 10'd1;

    reg [$clog2(BOARD_SIZE*BOARD_SIZE)-1:0] counter;

    always @(posedge clk) begin
        random  <= {random[14:0], random[15] ^ random[13] ^ random[12] ^ random[10]};
        counter <= (counter >= (BOARD_SIZE*BOARD_SIZE))? 0 : counter + 1;
        vsync_q <= vsync;

        if (~rst_n) begin
            car_x       <= CAR_START;
            car_y       <= CAR_Y;
            traffic0_x  <= 10'd240;
            traffic0_y  <= 10'd0;
            traffic1_x  <= 10'd360;
            traffic1_y  <= 10'd240;
            score       <= 10'd0;
            scroll      <= 10'd0;
            crash_timer <= 6'd0;
            first_press <= 0;
            counter <= 0;
            random      <= 16'hACE1;
        end else begin
            if (~ first_press) begin
                q_markov[counter] <= random[BOARD_BITS-1:0];
            end
            if (new_frame) begin
                last_input <= ui_in;
                if((last_input != ui_in) & ((last_input | ui_in) == ui_in))begin // different from last and no buttons turned off => at least one turned on
                    first_press <= 1;
                    if     ((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(1)) &   (BOARD_SIZE >= 1)) decoded_press <= {1'b1, BOARD_BITS'(0)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(2)) &   (BOARD_SIZE >= 2)) decoded_press <= {1'b1, BOARD_BITS'(1)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(4)) &   (BOARD_SIZE >= 3)) decoded_press <= {1'b1, BOARD_BITS'(2)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(8)) &   (BOARD_SIZE >= 4)) decoded_press <= {1'b1, BOARD_BITS'(3)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(16)) &  (BOARD_SIZE >= 5)) decoded_press <= {1'b1, BOARD_BITS'(4)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(32)) &  (BOARD_SIZE >= 6)) decoded_press <= {1'b1, BOARD_BITS'(5)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(64)) &  (BOARD_SIZE >= 7)) decoded_press <= {1'b1, BOARD_BITS'(6)};
                    else if((ui_in[BOARD_SIZE-1:0] == BOARD_SIZE'(128)) & (BOARD_SIZE >= 8)) decoded_press <= {1'b1, BOARD_BITS'(7)};
                    
                end else decoded_press <= {1'b0, decoded_press[BOARD_BITS-1:0]};
                
                if (crash_timer != 7'd0) begin
                    // ---- after a crash: count the flash down, then start again
                    crash_timer <= crash_timer - 6'd1;
                    if (crash_timer == 7'd1) begin
                        score       <= 10'd0;
                        bird_y <= 0;
                        bird_x <= 320;
                    end
                end else if (decoded_press[BOARD_BITS]) begin
                    last_pressed[1] <= decoded_press[BOARD_BITS-1:0];
                    last_pressed[0] <= last_pressed[1];
                    q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]] <= decoded_press[BOARD_BITS-1:0];
                    bird_choice <= q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]];
                    if(q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]] == decoded_press[BOARD_BITS-1:0]) begin
                        crash_timer <= CRASH_FRAMES+20;
                    end else begin
                        crash_timer <= CRASH_FRAMES;
                    end
                    bird_y <= 480 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE - BIRD_HEAD_SIZE/2;
                    bird_x <= WORM_BOX_SIZE*(2*q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]]+1)/2;
                end else begin
                    last_pressed[1] <= last_pressed[1];
                    last_pressed[0] <= last_pressed[0];
                    q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]] <= q_markov[last_pressed[0] + BOARD_SIZE*last_pressed[1]];
                    bird_choice <= bird_choice;
                end
            end
        end
    end

    // ========================================================================
    // 4. DRAWING
    //    One question for each thing on screen: is this pixel inside it?
    // ========================================================================

    wire [BOARD_SIZE-1:0] is_in_a_hole;
    wire [BOARD_SIZE-1:0] is_in_worm;
    genvar i;
    generate 
        for (i = 0; i < BOARD_SIZE; i = i + 1) begin : worm_box
            assign is_in_a_hole[i] = (pix_x <= WORM_BOX_SIZE*(i+1) - WORM_BOX_BORDER) & (pix_x >= WORM_BOX_SIZE*i + WORM_BOX_BORDER);
            assign is_in_worm[i] = (last_pressed[1] == i) & (WORM_BOX_SIZE*(2*i+1)/2 - WORM_SIZE/2 <= pix_x & pix_x <= WORM_BOX_SIZE*(2*i+1)/2 + WORM_SIZE/2);
        end
    endgenerate
    wire in_worm_box = ((480 - WORM_BOX_SIZE + WORM_BOX_BORDER<= pix_y) & (480 - WORM_BOX_BORDER >= pix_y)) & (|is_in_a_hole);
    wire in_worm = (480 - WORM_BOX_Y_CENTRE >= pix_y) & (pix_y >= 480 - WORM_BOX_Y_CENTRE - WORM_LENGTH)  & (|is_in_worm);
    wire in_worm_neck = (480 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE + WORM_NECK_SIZE >= pix_y) & (pix_y >= 480 - WORM_BOX_Y_CENTRE - WORM_LENGTH + WORM_HEAD_SIZE)  & (|is_in_worm);

    wire in_bird_head = ((pix_y <= BIRD_HEAD_SIZE/2 + bird_y & pix_y + BIRD_HEAD_SIZE/2 >= bird_y) & (bird_x <= pix_x + BIRD_HEAD_SIZE/2 & pix_x <= bird_x + BIRD_HEAD_SIZE/2)) | ((pix_y <= bird_y) & (bird_x <= pix_x + BIRD_HEAD_SIZE/2 + 32 & pix_x <= bird_x + BIRD_HEAD_SIZE/2 + 32));

    wire in_bird_white_eye = ((pix_y <= BIRD_HEAD_SIZE/2 + bird_y & pix_y >= bird_y + BIRD_HEAD_SIZE/2 - 16) & (bird_x <= pix_x + BIRD_HEAD_SIZE/2 & pix_x <= bird_x + BIRD_HEAD_SIZE/2)) & (bird_x + 48 <= pix_x | pix_x <= bird_x - 48);

    wire in_bird_black_eye = ((pix_y <= BIRD_HEAD_SIZE/2 + bird_y & pix_y >= bird_y + BIRD_HEAD_SIZE/2 - 16) & (bird_x <= pix_x + BIRD_HEAD_SIZE/2 & pix_x <= bird_x + BIRD_HEAD_SIZE/2)) & (bird_x + 24 <= pix_x | pix_x <= bird_x - 24);

    wire in_bird_beak = (pix_y >= bird_y + BIRD_HEAD_SIZE/2 & pix_y <= bird_y + BIRD_HEAD_SIZE/2 + BIRD_BEAK_LENGTH) &
                        (pix_x >= bird_x - BIRD_BEAK_SIZE/2 & pix_x <= bird_x + BIRD_BEAK_SIZE/2);

    //wire in_bird_beak = 
    // The road, its striped kerbs and its dashed centre line. Adding scroll to
    // pix_y is what makes the stripes move down the screen.
    wire [9:0] moving_y = pix_y + scroll;
    wire in_road        = (pix_x >= ROAD_L) & (pix_x < ROAD_R);
    wire in_kerb        = in_road & ((pix_x < LANE_L) | (pix_x >= LANE_R));
    wire kerb_stripe    = moving_y[4];
    wire in_centre_line = (pix_x >= 10'd318) & (pix_x < 10'd322) & moving_y[5];
    wire grass_square   = pix_x[GRASS_BIT] ^ pix_y[GRASS_BIT];

    // The car, with a window and four wheels.
    wire in_car    = (pix_x >= car_x) & (pix_x < car_x + CAR_W) &
                     (pix_y >= car_y) & (pix_y < car_y + CAR_H);
    wire in_window = 0;
    wire in_wheel  = 0;

    // The two vehicles, each with a darker strip six pixels deep along the top.
    wire in_traffic0 = (pix_x >= traffic0_x) & (pix_x < traffic0_x + TRAFFIC_W) &
                       (pix_y >= traffic0_y) & (pix_y < traffic0_y + TRAFFIC_H);
    wire in_traffic1 = (pix_x >= traffic1_x) & (pix_x < traffic1_x + TRAFFIC_W) &
                       (pix_y >= traffic1_y) & (pix_y < traffic1_y + TRAFFIC_H);
    wire in_traffic  = in_traffic0 | in_traffic1;
    wire in_shade    = (in_traffic0 & (pix_y - traffic0_y < 10'd6)) |
                       (in_traffic1 & (pix_y - traffic1_y < 10'd6));

    // The score bar: one pixel longer for every two frames survived.
    wire in_score = (pix_y >= 10'd8) & (pix_y < 10'd18) &
                    (pix_x >= 10'd8) & (pix_x < 10'd8 + {1'b0, score[9:1]});

    // The first line that matches wins, so anything higher up is drawn on top
    // of anything lower down. Move a line to change what covers what.
    reg [5:0] colour;
    always @(*) begin
        if (~video_active)       colour = 6'b000000;
        else if (in_bird_white_eye) colour = 6'b111111;
        else if (in_bird_black_eye) colour = 6'b000000;
        else if (in_bird_head)   colour = BIRD_COLOUR;
        else if (in_bird_beak)   colour = BIRD_BEAK_COLOUR;
        else if (in_worm_neck & (|crash_timer))   colour = WORM_NECK_COLOUR;
        else if (in_worm & (|crash_timer))        colour = WORM_COLOUR;
        else if (in_worm_box)    colour = HOLE_COLOUR;
        //else if (in_score)       colour = SCORE_COLOUR;
        //else if (in_wheel)       colour = WHEEL_COLOUR;
        //else if (in_window)      colour = WINDOW_COLOUR;
        //else if (in_car)         colour = CAR_COLOUR;
        //else if (in_traffic)     colour = in_shade ? TRAFFIC_SHADE : TRAFFIC_COLOUR;
        //else if (in_kerb)        colour = kerb_stripe ? KERB_COLOUR_A : KERB_COLOUR_B;
        //else if (in_centre_line) colour = LINE_COLOUR;
        //else if (in_road)        colour = ROAD_COLOUR;
        else                     colour = grass_square ? GRASS_COLOUR_A : GRASS_COLOUR_B;
    end

    // The crash flash: for four frames in every eight, full red with green and blue halved.
    wire       flash  = (crash_timer != 6'd0) & crash_timer[3] & (bird_choice == last_pressed[1]);
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
