// T02/T03：整帧渲染。帧先拼进静态缓冲，最后一次 write(1, ...)。
// T03 起棋盘行叠加当前块：board 值优先，ny<0 的格不画。
// T04 起状态行在 game_over_f=1 时输出 GAME OVER 行。
// T06 起 NEXT 两行画 pieces[(next_type,0)]；paused_f=1 时状态行输出 PAUSED（GAME OVER 优先）。

	.text
	.balign 4

// EMS <name>：追加字符串 S_<name>（字节长度取自 SL_<name> 的 word）
	.macro EMS name
	adrp	x0, S_\name@PAGE
	add	x0, x0, S_\name@PAGEOFF
	adrp	x1, SL_\name@PAGE
	add	x1, x1, SL_\name@PAGEOFF
	ldr	w1, [x1]
	bl	emit
	.endm

// emit(x0=src, x1=len)：追加 len 字节到帧缓冲，sb_ptr 为相对 sb 的偏移
	.globl emit
emit:
	adrp	x7, sb@PAGE
	add	x7, x7, sb@PAGEOFF
	adrp	x8, sb_ptr@PAGE
	add	x8, x8, sb_ptr@PAGEOFF
	ldr	x3, [x8]
.Lemit_copy:
	cbz	w1, .Lemit_out
	ldrb	w5, [x0], #1
	strb	w5, [x7, x3]
	add	x3, x3, #1
	sub	w1, w1, #1
	b	.Lemit_copy
.Lemit_out:
	str	x3, [x8]
	ret

// emit_dec(w0)：无符号十进制追加到帧缓冲（除 10 取余，逆序输出）
	.globl emit_dec
emit_dec:
	stp	x29, x30, [sp, #-32]!
	mov	x29, sp
	mov	w8, w0
	mov	x9, sp			// 数字缓冲，低位在前（最多 10 位）
	mov	w10, #0
.Led_div:
	mov	w11, #10
	udiv	w12, w8, w11
	msub	w11, w12, w11, w8
	add	w11, w11, #'0'
	strb	w11, [x9, x10]
	add	w10, w10, #1
	mov	w8, w12
	cbnz	w8, .Led_div
.Led_rev:
	subs	w10, w10, #1
	b.lt	.Led_done
	add	x0, x9, x10
	mov	x1, #1
	bl	emit
	b	.Led_rev
.Led_done:
	ldp	x29, x30, [sp], #32
	ret

// curmap_fill：curmap 清零，把 cur 4 格（nx/ny 在棋盘内、ny>=0）标为 cur_type+1
curmap_fill:
	stp	x19, x20, [sp, #-32]!
	stp	x21, x22, [sp, #16]
	adrp	x8, curmap@PAGE
	add	x8, x8, curmap@PAGEOFF
	mov	x9, #0
.Lcf_clear:
	strb	wzr, [x8, x9]
	add	x9, x9, #1
	cmp	x9, #200
	b.lt	.Lcf_clear
	adrp	x19, pieces@PAGE
	add	x19, x19, pieces@PAGEOFF
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w9, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w10, [x8]
	add	w9, w10, w9, lsl #2		// rot + type*4（type-major，与 game.s 一致）
	add	x19, x19, w9, sxtw #3		// *8 表内偏移
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w20, [x8]
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w21, [x8]
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w22, [x8]
	add	w22, w22, #1
	mov	x23, #0
.Lcf_loop:
	add	x12, x19, x23, lsl #1
	ldrsb	w13, [x12]
	ldrsb	w14, [x12, #1]
	add	w13, w13, w20			// nx
	add	w14, w14, w21			// ny
	cmp	w13, #0
	b.lt	.Lcf_skip
	cmp	w13, #9
	b.gt	.Lcf_skip
	cmp	w14, #0
	b.lt	.Lcf_skip
	cmp	w14, #19
	b.gt	.Lcf_skip
	add	w15, w14, w14, lsl #3
	add	w15, w15, w14
	add	w15, w15, w13
	adrp	x8, curmap@PAGE
	add	x8, x8, curmap@PAGEOFF
	strb	w22, [x8, w15, sxtw]
.Lcf_skip:
	add	x23, x23, #1
	cmp	x23, #4
	b.lt	.Lcf_loop
	ldp	x21, x22, [sp, #16]
	ldp	x19, x20, [sp], #32
	ret

// render_frame：拼一帧并 write(1, sb, sb_ptr)
	.globl render_frame
render_frame:
	stp	x29, x30, [sp, #-64]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	stp	x23, x24, [sp, #48]

	// sb_ptr 清零
	adrp	x8, sb_ptr@PAGE
	add	x8, x8, sb_ptr@PAGEOFF
	str	xzr, [x8]

	EMS	frame_init		// 1. 清屏回原点
	EMS	title			// 2. 标题

	bl	curmap_fill

	// 3. 20 行棋盘（w19=y 自上而下，w20=x）
	mov	w19, #0
.Lrf_row:
	EMS	pipe
	mov	w20, #0
.Lrf_cell:
	add	w14, w19, w19, lsl #3	// y*9
	add	w14, w14, w19		// y*10
	add	w14, w14, w20		// idx
	adrp	x15, board@PAGE
	add	x15, x15, board@PAGEOFF
	ldrb	w15, [x15, w14, sxtw]
	cbnz	w15, .Lrf_solid
	adrp	x15, curmap@PAGE
	add	x15, x15, curmap@PAGEOFF
	ldrb	w15, [x15, w14, sxtw]
	cbz	w15, .Lrf_empty
.Lrf_solid:
	sub	w14, w15, #1
	add	w14, w14, w14, lsl #2	// (v-1)*5
	adrp	x15, colors@PAGE
	add	x15, x15, colors@PAGEOFF
	add	x0, x15, w14, sxtw
	mov	x1, #5
	bl	emit
	EMS	br
	adrp	x0, color_reset@PAGE
	add	x0, x0, color_reset@PAGEOFF
	mov	x1, #4
	bl	emit
	b	.Lrf_cell_next
.Lrf_empty:
	EMS	dot
.Lrf_cell_next:
	add	w20, w20, #1
	cmp	w20, #10
	b.lt	.Lrf_cell
	EMS	pipe
	EMS	nl
	add	w19, w19, #1
	cmp	w19, #20
	b.lt	.Lrf_row

	EMS	border_bot		// 4. 底边框

	// 5. HUD
	EMS	score
	adrp	x0, score@PAGE
	ldr	w0, [x0, score@PAGEOFF]
	bl	emit_dec
	EMS	nl
	EMS	level
	adrp	x0, level@PAGE
	ldr	w0, [x0, level@PAGEOFF]
	bl	emit_dec
	EMS	nl
	EMS	lines
	adrp	x0, lines_total@PAGE
	ldr	w0, [x0, lines_total@PAGEOFF]
	bl	emit_dec
	EMS	nl

	// 6. NEXT 预览两行：画 pieces[(next_type,0)]，第 1 行 dy=0 格、第 2 行 dy=1 格；
	//    窗口 4 列 c=0..3 对应 dx=c-1，实心同棋盘着色，空列两空格
	EMS	next
	adrp	x19, pieces@PAGE
	add	x19, x19, pieces@PAGEOFF
	adrp	x8, next_type@PAGE
	add	x8, x8, next_type@PAGEOFF
	ldr	w9, [x8]			// next_type（0-6，ldr w9 零扩展）
	add	x19, x19, x9, lsl #5		// type*32 = (type*4+0) 表项（rot0）
	mov	w22, w9				// w22 = next_type（着色用）
	mov	w20, #0				// w20 = 行 dy（0，然后 1）
	b	.Lrf_next_cols
.Lrf_next_line2:
	EMS	blank5
	add	w20, w20, #1
.Lrf_next_cols:
	mov	w23, #0				// w23 = 列 c
.Lrf_next_c:
	mov	w24, #0				// w24 = 格下标 k
.Lrf_next_k:
	add	x9, x19, x24, lsl #1
	ldrsb	w10, [x9]			// dx
	ldrsb	w11, [x9, #1]			// dy
	sub	w12, w23, #1			// 目标 dx = c-1
	cmp	w10, w12
	b.ne	.Lrf_next_knext
	cmp	w11, w20
	b.eq	.Lrf_next_solid
.Lrf_next_knext:
	add	w24, w24, #1
	cmp	w24, #4
	b.lt	.Lrf_next_k
	EMS	sp2				// 空列：两空格
	b	.Lrf_next_cnext
.Lrf_next_solid:
	add	w14, w22, w22, lsl #2		// type*5
	adrp	x15, colors@PAGE
	add	x15, x15, colors@PAGEOFF
	add	x0, x15, w14, sxtw
	mov	x1, #5
	bl	emit
	EMS	br
	adrp	x0, color_reset@PAGE
	add	x0, x0, color_reset@PAGEOFF
	mov	x1, #4
	bl	emit
.Lrf_next_cnext:
	add	w23, w23, #1
	cmp	w23, #4
	b.lt	.Lrf_next_c
	EMS	nl
	cmp	w20, #0
	b.eq	.Lrf_next_line2

	// 7. 状态行：game_over_f=1 -> GAME OVER（优先）；否则 paused_f=1 -> PAUSED
	adrp	x8, game_over_f@PAGE
	add	x8, x8, game_over_f@PAGEOFF
	ldr	w9, [x8]
	cbz	w9, .Lrf_chk_pause
	EMS	gameover
	b	.Lrf_status_done
.Lrf_chk_pause:
	adrp	x8, paused_f@PAGE
	add	x8, x8, paused_f@PAGEOFF
	ldr	w9, [x8]
	cbz	w9, .Lrf_status_done
	EMS	paused
.Lrf_status_done:

	// 8. 帮助行
	EMS	help

	// write(1, sb, sb_ptr)
	adrp	x1, sb@PAGE
	add	x1, x1, sb@PAGEOFF
	adrp	x2, sb_ptr@PAGE
	add	x2, x2, sb_ptr@PAGEOFF
	ldr	x2, [x2]
	mov	x0, #1
	mov	x16, #4
	svc	#0x80

	ldp	x23, x24, [sp, #48]
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #64
	ret

	.section __DATA,__bss
	.balign 4
	.globl sb
sb:
	.space 4096
	.globl sb_ptr
sb_ptr:
	.space 8
curmap:
	.space 200

// T04：GAME OVER 状态行字符串（数据不进 data.s，本文件私有）
	.data
	.balign 4
S_gameover:
	.ascii "GAME OVER  R=restart\n"
S_gameover_end:

	.balign 4
SL_gameover:
	.word S_gameover_end - S_gameover

// T06：PAUSED 状态行与预览空列两空格（数据不进 data.s，本文件私有）
	.balign 4
S_paused:
	.ascii "PAUSED\n"
S_paused_end:

	.balign 4
SL_paused:
	.word S_paused_end - S_paused
S_sp2:
	.ascii "  "
S_sp2_end:

	.balign 4
SL_sp2:
	.word S_sp2_end - S_sp2
