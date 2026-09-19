/*
 * Copyright (c) 2025 Uri Shaked, Modified 2026
 * Playable Snake Apple Game (Yosys Syntax Safe & Edge Fixed)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in[7], uio_in};

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // Tiny VGA Pmod
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // Gamepad Pmod Driver
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r)
  );

  // Game Reset Logic (Hardware reset or pressing START/SELECT)
  wire game_reset = ~rst_n || inp_start || inp_select;

  // Colors
  localparam [5:0] BLACK = {2'b00, 2'b00, 2'b00};
  localparam [5:0] GREEN = {2'b00, 2'b11, 2'b00};
  localparam [5:0] WHITE = {2'b11, 2'b11, 2'b11};
  localparam [5:0] BLUE  = {2'b00, 2'b00, 2'b11};
  localparam [5:0] RED   = {2'b11, 2'b00, 2'b00};
  localparam [5:0] BEZEL = {2'b10, 2'b10, 2'b11};

  // ----------------- GAME PLAY AREA & MONITOR --------------------
  // Fixed vertical boundaries to exactly match 32 rows (256 pixels) and prevent edge duplication
  wire monitor_border = (pix_x >= 56 && pix_x < 584 && pix_y >= 32 && pix_y < 304);
  wire frame_active   = (pix_x >= 64 && pix_x < 576 && pix_y >= 40 && pix_y < 296); // 512x256 play area

  // Grid Mapping (64x32 board inside the frame)
  wire [5:0] grid_x = (pix_x - 64) >> 3; // 0 to 63
  wire [4:0] grid_y = (pix_y - 40) >> 3; // 0 to 31
  wire [10:0] cell_index = {grid_y, grid_x};

  // Title Text ROM ("SNAKE APPLE") placed above the monitor
  wire in_text_bounds = (pix_x >= 192 && pix_x < 192 + 256) && (pix_y >= 4 && pix_y < 4 + 24);
  wire [5:0] text_x = (pix_x - 192) >> 2; 
  wire [2:0] text_y = (pix_y - 4) >> 2;

  reg [63:0] title_rom [0:7];
  initial begin
    title_rom[0] = 64'b00_01110_0_10001_0_01110_0_10010_0_11111_000_01110_0_11110_0_11110_0_10000_0_11111_00;
    title_rom[1] = 64'b00_10000_0_11001_0_10001_0_10100_0_10000_000_10001_0_10001_0_10001_0_10000_0_10000_00;
    title_rom[2] = 64'b00_10000_0_10101_0_10001_0_11000_0_10000_000_10001_0_10001_0_10001_0_10000_0_10000_00;
    title_rom[3] = 64'b00_01110_0_10011_0_11111_0_10100_0_11110_000_11111_0_11110_0_11110_0_10000_0_11110_00;
    title_rom[4] = 64'b00_00001_0_10001_0_10001_0_10010_0_10000_000_10001_0_10000_0_10000_0_10000_0_10000_00;
    title_rom[5] = 64'b00_10001_0_10001_0_10001_0_10001_0_10000_000_10001_0_10000_0_10000_0_10000_0_10000_00;
    title_rom[6] = 64'b00_01110_0_10001_0_10001_0_10001_0_11111_000_10001_0_10000_0_10000_0_11111_0_11111_00;
    title_rom[7] = 64'b00_00000_0_00000_0_00000_0_00000_0_00000_000_00000_0_00000_0_00000_0_00000_0_00000_00;
  end
  wire [63:0] current_row = title_rom[text_y];
  wire title_pixel = in_text_bounds ? current_row[6'd63 - text_x] : 1'b0;

  // ----------------- SIMULATION & GAME ENGINE --------------------
  localparam CLOCK_FREQ = 24000000;
  localparam UPDATE_INTERVAL = CLOCK_FREQ / 20; // 20 Hz high-speed play

  localparam BOARD_SIZE = 2048; // 64x32
  reg board_state [0:BOARD_SIZE-1];
  reg [10:0] snake_body [0:1023];

  reg [9:0] head_ptr, tail_ptr;
  reg [10:0] head_pos, apple_pos;
  reg [3:0]  grow_queue;

  // Direction Controller (Edge-triggered for crisp gamepad response)
  localparam DIR_UP = 2'b00, DIR_DOWN = 2'b01, DIR_LEFT = 2'b10, DIR_RIGHT = 2'b11;
  reg [1:0] current_dir, buffered_dir;
  reg up_prev, down_prev, left_prev, right_prev;

  always @(posedge clk) begin
    if (game_reset) begin
      buffered_dir <= DIR_UP;
      up_prev <= 0; down_prev <= 0; left_prev <= 0; right_prev <= 0;
    end else begin
      up_prev <= inp_up; down_prev <= inp_down; left_prev <= inp_left; right_prev <= inp_right;

      if      ((inp_up    & ~up_prev)    && current_dir != DIR_DOWN)  buffered_dir <= DIR_UP;
      else if ((inp_down  & ~down_prev)  && current_dir != DIR_UP)    buffered_dir <= DIR_DOWN;
      else if ((inp_left  & ~left_prev)  && current_dir != DIR_RIGHT) buffered_dir <= DIR_LEFT;
      else if ((inp_right & ~right_prev) && current_dir != DIR_LEFT)  buffered_dir <= DIR_RIGHT;
    end
  end

  // Game States
  localparam ACTION_INIT = 0, ACTION_CLEAR = 1, ACTION_IDLE = 2, ACTION_UPDATE = 3, ACTION_CLEAR_TAIL = 4, ACTION_SPAWN = 5, ACTION_GAMEOVER = 6;
  reg [2:0] action;
  reg [31:0] timer;
  reg [10:0] init_index;

  wire [5:0] head_x = head_pos[5:0];
  wire [4:0] head_y = head_pos[10:6];
  reg [10:0] next_pos_reg;
  reg crashed_wall;

  always @(*) begin
    crashed_wall = 0;
    next_pos_reg = head_pos;
    case (current_dir)
      DIR_UP:    if (head_y == 0)  crashed_wall = 1; else next_pos_reg = {head_y - 5'd1, head_x};
      DIR_DOWN:  if (head_y == 31) crashed_wall = 1; else next_pos_reg = {head_y + 5'd1, head_x};
      DIR_LEFT:  if (head_x == 0)  crashed_wall = 1; else next_pos_reg = {head_y, head_x - 6'd1};
      DIR_RIGHT: if (head_x == 63) crashed_wall = 1; else next_pos_reg = {head_y, head_x + 6'd1};
    endcase
  end

  integer k;
  always @(posedge clk) begin
    if (game_reset) begin
      action <= ACTION_INIT;
      timer <= 0;
      init_index <= 0;
    end else begin
      case (action)
        ACTION_INIT: begin
          for (k = 0; k < 64; k = k + 1) begin
            board_state[init_index + k[10:0]] <= 0;
          end
          if (init_index >= BOARD_SIZE - 64) begin
            head_pos <= 11'd1056; // Center spawn
            apple_pos <= 11'd512;
            head_ptr <= 0;
            tail_ptr <= 0;
            grow_queue <= 0;
            current_dir <= DIR_UP;
            buffered_dir <= DIR_UP;
            board_state[1056] <= 1;
            snake_body[0] <= 1056;
            action <= ACTION_IDLE;
          end else begin
            init_index <= init_index + 64;
          end
        end

        ACTION_IDLE: begin
          if (timer < UPDATE_INTERVAL) begin
            timer <= timer + 1;
          end else begin
            timer <= 0;
            action <= ACTION_UPDATE;
          end
        end

        ACTION_UPDATE: begin
          current_dir <= buffered_dir;
          if (crashed_wall || board_state[next_pos_reg]) begin
            action <= ACTION_GAMEOVER;
          end else begin
            head_pos <= next_pos_reg;
            head_ptr <= head_ptr + 1;
            snake_body[head_ptr + 1] <= next_pos_reg;
            board_state[next_pos_reg] <= 1;

            if (next_pos_reg == apple_pos) begin
              grow_queue <= grow_queue + 2;
              action <= ACTION_SPAWN;
            end else begin
              if (grow_queue > 0) begin
                grow_queue <= grow_queue - 1;
                action <= ACTION_IDLE;
              end else begin
                action <= ACTION_CLEAR_TAIL;
              end
            end
          end
        end

        ACTION_CLEAR_TAIL: begin
          board_state[snake_body[tail_ptr]] <= 0;
          tail_ptr <= tail_ptr + 1;
          action <= ACTION_IDLE;
        end

        ACTION_SPAWN: begin
          apple_pos <= {lfsr_reg[10:6], lfsr_reg[5:0]};
          action <= ACTION_IDLE;
        end

        ACTION_GAMEOVER: begin
          // Freeze on crash. Press START or SELECT to restart!
        end

        default: action <= ACTION_IDLE;
      endcase
    end
  end

  // LFSR Random Number Generator
  reg [15:0] lfsr_reg;
  wire feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];
  always @(posedge clk) begin
    if (game_reset) lfsr_reg <= 16'b1010_1101_0011_0001;
    else            lfsr_reg <= {lfsr_reg[14:0], feedback};
  end

  // ----------------- SYNTHESIS-SAFE GLYPH LOOKUP FUNCTION --------------------
  function [7:0] get_glyph_row;
    input [3:0] g_type;
    input [2:0] row;
    begin
      case (g_type)
        4'd0: // LEFT
          case(row)
            3'd0: get_glyph_row = 8'b00010000;
            3'd1: get_glyph_row = 8'b00110000;
            3'd2: get_glyph_row = 8'b01110000;
            3'd3: get_glyph_row = 8'b11111111;
            3'd4: get_glyph_row = 8'b01110000;
            3'd5: get_glyph_row = 8'b00110000;
            3'd6: get_glyph_row = 8'b00010000;
            default: get_glyph_row = 8'b00000000;
          endcase
        4'd1: // RIGHT
          case(row)
            3'd0: get_glyph_row = 8'b00001000;
            3'd1: get_glyph_row = 8'b00001100;
            3'd2: get_glyph_row = 8'b00001110;
            3'd3: get_glyph_row = 8'b11111111;
            3'd4: get_glyph_row = 8'b00001110;
            3'd5: get_glyph_row = 8'b00001100;
            3'd6: get_glyph_row = 8'b00001000;
            default: get_glyph_row = 8'b00000000;
          endcase
        4'd2: // UP
          case(row)
            3'd0: get_glyph_row = 8'b00010000;
            3'd1: get_glyph_row = 8'b00111000;
            3'd2: get_glyph_row = 8'b01111100;
            3'd3: get_glyph_row = 8'b11111110;
            3'd4: get_glyph_row = 8'b00010000;
            3'd5: get_glyph_row = 8'b00010000;
            3'd6: get_glyph_row = 8'b00010000;
            default: get_glyph_row = 8'b00000000;
          endcase
        4'd3: // DOWN
          case(row)
            3'd0: get_glyph_row = 8'b00010000;
            3'd1: get_glyph_row = 8'b00010000;
            3'd2: get_glyph_row = 8'b00010000;
            3'd3: get_glyph_row = 8'b00010000;
            3'd4: get_glyph_row = 8'b11111110;
            3'd5: get_glyph_row = 8'b01111100;
            3'd6: get_glyph_row = 8'b00111000;
            default: get_glyph_row = 8'b00000000;
          endcase
        4'd4: // A
          case(row)
            3'd0: get_glyph_row = 8'h3c;
            3'd1: get_glyph_row = 8'h66;
            3'd2: get_glyph_row = 8'h66;
            3'd3: get_glyph_row = 8'h7e;
            3'd4: get_glyph_row = 8'h66;
            3'd5: get_glyph_row = 8'h66;
            3'd6: get_glyph_row = 8'h66;
            default: get_glyph_row = 8'h00;
          endcase
        4'd5: // B
          case(row)
            3'd0: get_glyph_row = 8'h7c;
            3'd1: get_glyph_row = 8'h66;
            3'd2: get_glyph_row = 8'h66;
            3'd3: get_glyph_row = 8'h7c;
            3'd4: get_glyph_row = 8'h66;
            3'd5: get_glyph_row = 8'h66;
            3'd6: get_glyph_row = 8'h7c;
            default: get_glyph_row = 8'h00;
          endcase
        4'd6: // X
          case(row)
            3'd0: get_glyph_row = 8'hc3;
            3'd1: get_glyph_row = 8'h66;
            3'd2: get_glyph_row = 8'h3c;
            3'd3: get_glyph_row = 8'h18;
            3'd4: get_glyph_row = 8'h18;
            3'd5: get_glyph_row = 8'h3c;
            3'd6: get_glyph_row = 8'h66;
            3'd7: get_glyph_row = 8'hc3;
            default: get_glyph_row = 8'h00;
          endcase
        4'd7: // Y
          case(row)
            3'd0: get_glyph_row = 8'hc3;
            3'd1: get_glyph_row = 8'h66;
            3'd2: get_glyph_row = 8'h3c;
            3'd3: get_glyph_row = 8'h18;
            3'd4: get_glyph_row = 8'h18;
            3'd5: get_glyph_row = 8'h18;
            3'd6: get_glyph_row = 8'h18;
            default: get_glyph_row = 8'h00;
          endcase
        4'd8: // L
          case(row)
            3'd0: get_glyph_row = 8'he0;
            3'd1: get_glyph_row = 8'he0;
            3'd2: get_glyph_row = 8'he0;
            3'd3: get_glyph_row = 8'he0;
            3'd4: get_glyph_row = 8'he0;
            3'd5: get_glyph_row = 8'hfe;
            3'd6: get_glyph_row = 8'hfe;
            default: get_glyph_row = 8'h00;
          endcase
        4'd9: // R
          case(row)
            3'd0: get_glyph_row = 8'hfc;
            3'd1: get_glyph_row = 8'h66;
            3'd2: get_glyph_row = 8'h66;
            3'd3: get_glyph_row = 8'hfc;
            3'd4: get_glyph_row = 8'hf8;
            3'd5: get_glyph_row = 8'hfc;
            3'd6: get_glyph_row = 8'hee;
            default: get_glyph_row = 8'h00;
          endcase
        4'd10: // SELECT
          case(row)
            3'd0: get_glyph_row = 8'h18;
            3'd1: get_glyph_row = 8'h24;
            3'd2: get_glyph_row = 8'h42;
            3'd3: get_glyph_row = 8'h81;
            3'd4: get_glyph_row = 8'h81;
            3'd5: get_glyph_row = 8'h42;
            3'd6: get_glyph_row = 8'h24;
            3'd7: get_glyph_row = 8'h18;
            default: get_glyph_row = 8'h00;
          endcase
        4'd11: // START
          case(row)
            3'd0: get_glyph_row = 8'h18;
            3'd1: get_glyph_row = 8'h5a;
            3'd2: get_glyph_row = 8'h99;
            3'd3: get_glyph_row = 8'h99;
            3'd4: get_glyph_row = 8'h99;
            3'd5: get_glyph_row = 8'h81;
            3'd6: get_glyph_row = 8'h42;
            3'd7: get_glyph_row = 8'h3c;
            default: get_glyph_row = 8'h00;
          endcase
        default: get_glyph_row = 8'h00;
      endcase
    end
  endfunction

  // HUD Glyph Coordinates
  localparam LEFT_X = 48, LEFT_Y = 380;
  localparam RIGHT_X = 144, RIGHT_Y = 380;
  localparam UP_X = 96, UP_Y = 356;
  localparam DOWN_X = 96, DOWN_Y = 412;
  localparam A_X = 560, A_Y = 380;
  localparam B_X = 512, B_Y = 424;
  localparam X_X = 512, X_Y = 336;
  localparam Y_X = 464, Y_Y = 380;
  localparam L_X = 32, L_Y = 360;
  localparam R_X = 592, R_Y = 360;
  localparam SEL_X = 264, SEL_Y = 380;
  localparam STRT_X = 328, STRT_Y = 380;

  wire left_act  = glyph_active(LEFT_X, LEFT_Y, 4'd0);
  wire right_act = glyph_active(RIGHT_X, RIGHT_Y, 4'd1);
  wire up_act    = glyph_active(UP_X, UP_Y, 4'd2);
  wire down_act  = glyph_active(DOWN_X, DOWN_Y, 4'd3);
  wire a_act     = glyph_active(A_X, A_Y, 4'd4);
  wire b_act     = glyph_active(B_X, B_Y, 4'd5);
  wire x_act     = glyph_active(X_X, X_Y, 4'd6);
  wire y_act     = glyph_active(Y_X, Y_Y, 4'd7);
  wire l_act     = glyph_active(L_X, L_Y, 4'd8);
  wire r_act     = glyph_active(R_X, R_Y, 4'd9);
  wire sel_act   = glyph_active(SEL_X, SEL_Y, 4'd10);
  wire strt_act  = glyph_active(STRT_X, STRT_Y, 4'd11);

  wire hud_glyph_lit = (left_act & inp_left) | (right_act & inp_right) | 
                       (up_act & inp_up) | (down_act & inp_down) |
                       (a_act & inp_a) | (b_act & inp_b) |
                       (x_act & inp_x) | (y_act & inp_y) |
                       (l_act & inp_l) | (r_act & inp_r) |
                       (sel_act & inp_select) | (strt_act & inp_start);
  wire hud_glyph_box = left_act | right_act | up_act | down_act | a_act | b_act |
                       x_act | y_act | l_act | r_act | sel_act | strt_act;

  // ----------------- FINAL RGB RENDERER --------------------
  always @(posedge clk) begin
    if (~rst_n) begin
      {R, G, B} <= 0;
    end else begin
      if (video_active) begin
        if (in_text_bounds && title_pixel) begin
          {R, G, B} <= WHITE;
        end else if (frame_active) begin
          if (cell_index == apple_pos) begin
            {R, G, B} <= RED;
          end else if (board_state[cell_index]) begin
            {R, G, B} <= GREEN;
          end else begin
            {R, G, B} <= BLUE;
          end
        end else if (monitor_border) begin
          {R, G, B} <= BEZEL;
        end else if (hud_glyph_lit) begin
          {R, G, B} <= GREEN;
        end else if (hud_glyph_box) begin
          {R, G, B} <= WHITE;
        end else begin
          {R, G, B} <= BLACK;
        end
      end else begin
        {R, G, B} <= 0;
      end
    end
  end

  // Scaled glyph helper function
  function glyph_active;
    input [9:0] x0, y0;
    input [3:0] g_type;
    reg [9:0] x_rel, y_rel;
    reg [7:0] row_bits;
    begin
      if ((pix_x >= x0) && (pix_x < x0 + 16) && (pix_y >= y0) && (pix_y < y0 + 16)) begin
        x_rel = (pix_x - x0) >> 1;
        y_rel = (pix_y - y0) >> 1;
        row_bits = get_glyph_row(g_type, y_rel[2:0]);
        glyph_active = row_bits[7-x_rel];
      end else begin
        glyph_active = 0;
      end
    end
  endfunction

endmodule
