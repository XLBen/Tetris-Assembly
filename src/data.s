// T02：游戏状态标签（共享接口定义处）与渲染字符串/颜色表
// 状态全零初始化；term_raw_ok / term_saved 在 term.s，这里不得重复定义

	.section __DATA,__bss
	.balign 4
	.globl board
board:
	.space 200			// 10x20，每格 1 字节：0 空，1-7=方块类型+1
	.globl cur_type
cur_type:
	.space 4
	.globl cur_rot
cur_rot:
	.space 4
	.globl cur_x
cur_x:
	.space 4
	.globl cur_y
cur_y:
	.space 4
	.globl next_type
next_type:
	.space 4
	.globl score
score:
	.space 4
	.globl lines_total
lines_total:
	.space 4
	.globl level
level:
	.space 4
	.globl tick_ctr
tick_ctr:
	.space 4
	.globl game_over_f
game_over_f:
	.space 4
	.globl paused_f
paused_f:
	.space 4
	.globl prng_state
prng_state:
	.space 4
	.globl init_seed
init_seed:
	.space 4

	.data
	.balign 4
	.globl colors			// 7 组各 5 字节，类型 t 用 colors + (t-1)*5
colors:
	.ascii "\x1b[31m"
	.ascii "\x1b[32m"
	.ascii "\x1b[33m"
	.ascii "\x1b[34m"
	.ascii "\x1b[35m"
	.ascii "\x1b[36m"
	.ascii "\x1b[37m"
	.globl color_reset
color_reset:
	.ascii "\x1b[0m"

// 渲染字符串；SL_* = 对应字符串的字节长度（相邻标签差，自动维护）
	.globl S_frame_init
S_frame_init:
	.ascii "\x1b[2J\x1b[H"
	.globl S_title
S_title:
	.ascii "TETRIS (ARM64)\n"
	.globl S_pipe
S_pipe:
	.ascii "|"
	.globl S_dot
S_dot:
	.ascii ". "
	.globl S_border_bot
S_border_bot:
	.ascii "+--------------------+\n"
	.globl S_score
S_score:
	.ascii "SCORE "
	.globl S_level
S_level:
	.ascii "LEVEL "
	.globl S_lines
S_lines:
	.ascii "LINES "
	.globl S_next
S_next:
	.ascii "NEXT "
	.globl S_blank8
S_blank8:
	.ascii "        "
	.globl S_blank5
S_blank5:
	.ascii "     "
	.globl S_nl
S_nl:
	.ascii "\n"
	.globl S_br
S_br:
	.ascii "[]"
	.globl S_help
S_help:
	.ascii "←→ move · ↓ soft · ↑ rotate · space drop · p pause · r restart · q quit\n"
S_end:

	.balign 4
	.globl SL_frame_init
SL_frame_init:
	.word S_title - S_frame_init
	.globl SL_title
SL_title:
	.word S_pipe - S_title
	.globl SL_pipe
SL_pipe:
	.word S_dot - S_pipe
	.globl SL_dot
SL_dot:
	.word S_border_bot - S_dot
	.globl SL_border_bot
SL_border_bot:
	.word S_score - S_border_bot
	.globl SL_score
SL_score:
	.word S_level - S_score
	.globl SL_level
SL_level:
	.word S_lines - S_level
	.globl SL_lines
SL_lines:
	.word S_next - S_lines
	.globl SL_next
SL_next:
	.word S_blank8 - S_next
	.globl SL_blank8
SL_blank8:
	.word S_blank5 - S_blank8
	.globl SL_blank5
SL_blank5:
	.word S_nl - S_blank5
	.globl SL_nl
SL_nl:
	.word S_br - S_nl
	.globl SL_br
SL_br:
	.word S_help - S_br
	.globl SL_help
SL_help:
	.word S_end - S_help

// 方块表：7 型 × 4 旋转 × 4 格 × (dx,dy)，y 向下为正
	.balign 4
	.globl pieces
pieces:
// I(0)
	.byte -1,0, 0,0, 1,0, 2,0
	.byte 0,-1, 0,0, 0,1, 0,2
	.byte 1,0, 0,0, -1,0, -2,0
	.byte 0,1, 0,0, 0,-1, 0,-2
// O(1)：四态同形
	.byte 0,0, 1,0, 0,1, 1,1
	.byte 0,0, 1,0, 0,1, 1,1
	.byte 0,0, 1,0, 0,1, 1,1
	.byte 0,0, 1,0, 0,1, 1,1
// T(2)
	.byte -1,0, 0,0, 1,0, 0,1
	.byte 0,-1, 0,0, 0,1, -1,0
	.byte 1,0, 0,0, -1,0, 0,-1
	.byte 0,1, 0,0, 0,-1, 1,0
// S(3)
	.byte 0,0, 1,0, -1,1, 0,1
	.byte 0,0, 0,1, -1,-1, -1,0
	.byte 0,0, -1,0, 1,-1, 0,-1
	.byte 0,0, 0,-1, 1,1, 1,0
// Z(4)
	.byte -1,0, 0,0, 0,1, 1,1
	.byte 0,-1, 0,0, -1,0, -1,1
	.byte 1,0, 0,0, 0,-1, -1,-1
	.byte 0,1, 0,0, 1,0, 1,-1
// J(5)
	.byte -1,0, 0,0, 1,0, -1,1
	.byte 0,-1, 0,0, 0,1, -1,-1
	.byte 1,0, 0,0, -1,0, 1,-1
	.byte 0,1, 0,0, 0,-1, 1,1
// L(6)
	.byte -1,0, 0,0, 1,0, 1,1
	.byte 0,-1, 0,0, 0,1, -1,1
	.byte 1,0, 0,0, -1,0, -1,-1
	.byte 0,1, 0,0, 0,-1, 1,-1

	.balign 4
	.globl speed_tbl
speed_tbl:
	.word 10, 8, 7, 6, 5, 4, 3, 2, 2, 1

// 一次消 n 行的得分基数（下标 0-4）
	.balign 4
	.globl score_tbl
score_tbl:
	.word 0, 100, 300, 500, 800

