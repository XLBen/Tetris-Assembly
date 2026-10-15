// T03：游戏逻辑（PRNG/碰撞/spawn/reset/按键/下落锁定）
// 接口：rand_next()->w0  collision(w0=px,w1=py,w2=type,w3=rot)->w0
//       game_reset()  game_handle_key(w0)  game_tick()

	.text
	.balign 4

// rand_next：xorshift32 推进 prng_state，返回 state % 7
	.globl rand_next
rand_next:
	adrp	x8, prng_state@PAGE
	add	x8, x8, prng_state@PAGEOFF
	ldr	w9, [x8]
	eor	w9, w9, w9, lsl #13
	eor	w9, w9, w9, lsr #17
	eor	w9, w9, w9, lsl #5
	str	w9, [x8]
	mov	w10, #7
	udiv	w11, w9, w10
	msub	w0, w11, w10, w9
	ret

// collision：1=碰；nx<0||nx>9||ny>19 或（ny>=0 且 board 占用）为碰；ny<0 不查 board
	.globl collision
collision:
	adrp	x4, pieces@PAGE
	add	x4, x4, pieces@PAGEOFF
	add	x4, x4, x2, lsl #5		// type*32
	add	x4, x4, x3, lsl #3		// rot*8
	mov	x5, #0
.Lcol_loop:
	add	x12, x4, x5, lsl #1
	ldrsb	w6, [x12]			// dx
	ldrsb	w7, [x12, #1]			// dy
	add	w13, w0, w6			// nx
	add	w14, w1, w7			// ny
	cmp	w13, #0
	b.lt	.Lcol_hit
	cmp	w13, #9
	b.gt	.Lcol_hit
	cmp	w14, #19
	b.gt	.Lcol_hit
	cmp	w14, #0
	b.lt	.Lcol_next
	add	w15, w14, w14, lsl #3		// ny*9
	add	w15, w15, w14			// ny*10
	add	w15, w15, w13			// +nx
	adrp	x8, board@PAGE
	add	x8, x8, board@PAGEOFF
	ldrb	w9, [x8, w15, sxtw]
	cbnz	w9, .Lcol_hit
.Lcol_next:
	add	x5, x5, #1
	cmp	x5, #4
	b.lt	.Lcol_loop
	mov	w0, #0
	ret
.Lcol_hit:
	mov	w0, #1
	ret

// spawn：cur_type=next_type; next_type=rand_next(); cur_x=4; cur_y=0; cur_rot=0
//        出生位碰撞 -> game_over_f=1
spawn:
	stp	x29, x30, [sp, #-16]!
	adrp	x8, next_type@PAGE
	add	x8, x8, next_type@PAGEOFF
	ldr	w9, [x8]
	adrp	x10, cur_type@PAGE
	add	x10, x10, cur_type@PAGEOFF
	str	w9, [x10]
	bl	rand_next
	adrp	x10, next_type@PAGE
	add	x10, x10, next_type@PAGEOFF
	str	w0, [x10]
	mov	w9, #4
	adrp	x10, cur_x@PAGE
	add	x10, x10, cur_x@PAGEOFF
	str	w9, [x10]
	adrp	x10, cur_y@PAGE
	add	x10, x10, cur_y@PAGEOFF
	str	wzr, [x10]
	adrp	x10, cur_rot@PAGE
	add	x10, x10, cur_rot@PAGEOFF
	str	wzr, [x10]
	adrp	x10, cur_x@PAGE
	add	x10, x10, cur_x@PAGEOFF
	ldr	w0, [x10]
	adrp	x10, cur_y@PAGE
	add	x10, x10, cur_y@PAGEOFF
	ldr	w1, [x10]
	adrp	x10, cur_type@PAGE
	add	x10, x10, cur_type@PAGEOFF
	ldr	w2, [x10]
	adrp	x10, cur_rot@PAGE
	add	x10, x10, cur_rot@PAGEOFF
	ldr	w3, [x10]
	bl	collision
	cbz	w0, .Lspawn_ok
	adrp	x10, game_over_f@PAGE
	add	x10, x10, game_over_f@PAGEOFF
	mov	w9, #1
	str	w9, [x10]
.Lspawn_ok:
	ldp	x29, x30, [sp], #16
	ret

// game_reset：清全部状态，prng_state=init_seed，next_type=rand_next()，spawn
	.globl game_reset
game_reset:
	stp	x29, x30, [sp, #-16]!
	adrp	x8, board@PAGE
	add	x8, x8, board@PAGEOFF
	mov	x9, #0
.Lgr_clear:
	strb	wzr, [x8, x9]
	add	x9, x9, #1
	cmp	x9, #200
	b.lt	.Lgr_clear
	adrp	x10, score@PAGE
	add	x10, x10, score@PAGEOFF
	str	wzr, [x10]
	adrp	x10, lines_total@PAGE
	add	x10, x10, lines_total@PAGEOFF
	str	wzr, [x10]
	adrp	x10, level@PAGE
	add	x10, x10, level@PAGEOFF
	str	wzr, [x10]
	adrp	x10, tick_ctr@PAGE
	add	x10, x10, tick_ctr@PAGEOFF
	str	wzr, [x10]
	adrp	x10, game_over_f@PAGE
	add	x10, x10, game_over_f@PAGEOFF
	str	wzr, [x10]
	adrp	x10, paused_f@PAGE
	add	x10, x10, paused_f@PAGEOFF
	str	wzr, [x10]
	adrp	x10, init_seed@PAGE
	add	x10, x10, init_seed@PAGEOFF
	ldr	w11, [x10]
	adrp	x10, prng_state@PAGE
	add	x10, x10, prng_state@PAGEOFF
	str	w11, [x10]
	bl	rand_next
	adrp	x10, next_type@PAGE
	add	x10, x10, next_type@PAGEOFF
	str	w0, [x10]
	bl	spawn
	ldp	x29, x30, [sp], #16
	ret

// game_handle_key(w0)：game_over 只认 K_RESTART；p 翻转暂停（暂停时忽略 1-5）；
// r 任意时刻重开；左右移动、旋转、软降、硬降
	.globl game_handle_key
game_handle_key:
	stp	x29, x30, [sp, #-16]!
	adrp	x8, game_over_f@PAGE
	add	x8, x8, game_over_f@PAGEOFF
	ldr	w9, [x8]
	cbz	w9, .Lghk_active
	cmp	w0, #8				// K_RESTART
	b.ne	.Lghk_ret
	bl	game_reset
	b	.Lghk_ret
.Lghk_active:
	cmp	w0, #6
	b.eq	.Lghk_pause
	cmp	w0, #8
	b.eq	.Lghk_restart
	// paused_f=1：移动/旋转/软降/硬降全部忽略（只有 p/q/r 生效）
	adrp	x8, paused_f@PAGE
	add	x8, x8, paused_f@PAGEOFF
	ldr	w9, [x8]
	cbnz	w9, .Lghk_ret
	cmp	w0, #1
	b.eq	.Lghk_left
	cmp	w0, #2
	b.eq	.Lghk_right
	cmp	w0, #3
	b.eq	.Lghk_down
	cmp	w0, #4
	b.eq	.Lghk_rot
	cmp	w0, #5
	b.eq	.Lghk_hard
	b	.Lghk_ret
// K_PAUSE：翻转 paused_f
.Lghk_pause:
	adrp	x8, paused_f@PAGE
	add	x8, x8, paused_f@PAGEOFF
	ldr	w9, [x8]
	eor	w9, w9, #1
	str	w9, [x8]
	b	.Lghk_ret
// K_RESTART：任意时刻重开（game_reset 内重播种到 init_seed）
.Lghk_restart:
	bl	game_reset
	b	.Lghk_ret
.Lghk_left:
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w9, [x8]
	sub	w0, w9, #1
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w1, [x8]
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w2, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w3, [x8]
	bl	collision
	cbnz	w0, .Lghk_ret
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w9, [x8]
	sub	w9, w9, #1
	str	w9, [x8]
	b	.Lghk_ret
.Lghk_right:
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w9, [x8]
	add	w0, w9, #1
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w1, [x8]
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w2, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w3, [x8]
	bl	collision
	cbnz	w0, .Lghk_ret
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	str	w9, [x8]
	b	.Lghk_ret
.Lghk_down:
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w0, [x8]
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w1, [x8]
	add	w1, w1, #1
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w2, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w3, [x8]
	bl	collision
	cbnz	w0, .Lghk_ret
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	str	w9, [x8]
	b	.Lghk_ret
// K_ROT：new_rot=(cur_rot+1)&3，无碰撞才改
.Lghk_rot:
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w0, [x8]
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w1, [x8]
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w2, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	and	w3, w9, #3
	bl	collision
	cbnz	w0, .Lghk_ret
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	and	w9, w9, #3
	str	w9, [x8]
	b	.Lghk_ret
// K_HARD：落到不能再下，然后锁定+spawn
.Lghk_hard:
	adrp	x8, cur_x@PAGE
	add	x8, x8, cur_x@PAGEOFF
	ldr	w0, [x8]
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w1, [x8]
	add	w1, w1, #1
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w2, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w3, [x8]
	bl	collision
	cbnz	w0, .Lghk_hard_done
	adrp	x8, cur_y@PAGE
	add	x8, x8, cur_y@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	str	w9, [x8]
	b	.Lghk_hard
.Lghk_hard_done:
	bl	lock_and_spawn
	b	.Lghk_ret
.Lghk_ret:
	ldp	x29, x30, [sp], #16
	ret

// game_tick：paused 冻结；game_over 冻结；下方碰撞 -> lock_and_spawn；否则 cur_y++
	.globl game_tick
game_tick:
	stp	x29, x30, [sp, #-16]!
	adrp	x8, game_over_f@PAGE
	add	x8, x8, game_over_f@PAGEOFF
	ldr	w9, [x8]
	cbnz	w9, .Lgt_ret
	adrp	x8, paused_f@PAGE
	add	x8, x8, paused_f@PAGEOFF
	ldr	w9, [x8]
	cbnz	w9, .Lgt_ret
	adrp	x10, cur_x@PAGE
	add	x10, x10, cur_x@PAGEOFF
	ldr	w0, [x10]
	adrp	x10, cur_y@PAGE
	add	x10, x10, cur_y@PAGEOFF
	ldr	w1, [x10]
	add	w1, w1, #1
	adrp	x10, cur_type@PAGE
	add	x10, x10, cur_type@PAGEOFF
	ldr	w2, [x10]
	adrp	x10, cur_rot@PAGE
	add	x10, x10, cur_rot@PAGEOFF
	ldr	w3, [x10]
	bl	collision
	cbnz	w0, .Lgt_lock
	adrp	x10, cur_y@PAGE
	add	x10, x10, cur_y@PAGEOFF
	ldr	w9, [x10]
	add	w9, w9, #1
	str	w9, [x10]
	b	.Lgt_ret
.Lgt_lock:
	bl	lock_and_spawn
.Lgt_ret:
	ldp	x29, x30, [sp], #16
	ret

// lock_and_spawn（内部，供 game_tick 与 K_HARD 共用）：
// 当前块 4 格写入 board（ny>=0 才写，值=cur_type+1），然后消行，再 spawn
lock_and_spawn:
	stp	x29, x30, [sp, #-48]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	adrp	x19, pieces@PAGE
	add	x19, x19, pieces@PAGEOFF
	adrp	x8, cur_type@PAGE
	add	x8, x8, cur_type@PAGEOFF
	ldr	w9, [x8]
	adrp	x8, cur_rot@PAGE
	add	x8, x8, cur_rot@PAGEOFF
	ldr	w10, [x8]
	add	w9, w10, w9, lsl #2		// rot + type*4（type-major：表项 = type*4+rot）
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
.Llas_loop:
	add	x12, x19, x23, lsl #1
	ldrsb	w13, [x12]
	ldrsb	w14, [x12, #1]
	add	w13, w13, w20			// nx
	add	w14, w14, w21			// ny
	cmp	w14, #0
	b.lt	.Llas_skip
	add	w15, w14, w14, lsl #3
	add	w15, w15, w14
	add	w15, w15, w13
	adrp	x8, board@PAGE
	add	x8, x8, board@PAGEOFF
	strb	w22, [x8, w15, sxtw]
.Llas_skip:
	add	x23, x23, #1
	cmp	x23, #4
	b.lt	.Llas_loop
	bl	clear_lines
	bl	spawn
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #48
	ret

// clear_lines（内部，供 lock_and_spawn 调用）：
// y 从 19 往 0 扫，整行 10 格非 0 -> 删除该行并把上方整体下移一行
// （等价 memmove：i 从 y*10-1 倒序到 0 做 board[i+10]=board[i]，高地址先写不踩源），行 0 清零，
// 消行时 y 不动重查同位；累计 n 行后：
// score += score_tbl[n]*(level+1)（用消行前的 level），lines_total += n，
// level = min(9, lines_total/10)（udiv）
clear_lines:
	stp	x29, x30, [sp, #-32]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	mov	w19, #0			// n = 已消行数
	mov	w20, #19		// y
.Lcl_row:
	cmp	w20, #0
	b.lt	.Lcl_score
	// 行 y 是否整行非 0
	adrp	x8, board@PAGE
	add	x8, x8, board@PAGEOFF
	add	w9, w20, w20, lsl #3	// y*9
	add	w9, w9, w20		// y*10
	add	x8, x8, w9, sxtw	// 行首
	mov	w10, #0
.Lcl_check:
	ldrb	w11, [x8, x10]
	cbz	w11, .Lcl_notfull
	add	w10, w10, #1
	cmp	w10, #10
	b.lt	.Lcl_check
	// 整行满：上方整体下移一行，i = y*10-1 .. 0 倒序
	// （x8 在检查阶段已前进 y*10，先退回 board 基址再按全盘索引做）
	sub	x8, x8, w9, sxtw
	add	w9, w9, #-1		// y*10-1
.Lcl_shift:
	cmp	w9, #0
	b.lt	.Lcl_zero0
	ldrb	w10, [x8, w9, sxtw]
	add	w11, w9, #10
	strb	w10, [x8, w11, sxtw]
	sub	w9, w9, #1
	b	.Lcl_shift
.Lcl_zero0:
	mov	w9, #0
.Lcl_z0:
	strb	wzr, [x8, x9]
	add	w9, w9, #1
	cmp	w9, #10
	b.lt	.Lcl_z0
	add	w19, w19, #1		// n++
	b	.Lcl_row		// 上方已下移，同 y 重查
.Lcl_notfull:
	sub	w20, w20, #1
	b	.Lcl_row
.Lcl_score:
	// score += score_tbl[n] * (level+1)
	adrp	x8, score_tbl@PAGE
	add	x8, x8, score_tbl@PAGEOFF
	add	x8, x8, w19, sxtw #2	// &score_tbl[n]
	ldr	w9, [x8]
	adrp	x10, level@PAGE
	add	x10, x10, level@PAGEOFF
	ldr	w11, [x10]
	add	w11, w11, #1
	mul	w9, w9, w11
	adrp	x10, score@PAGE
	add	x10, x10, score@PAGEOFF
	ldr	w11, [x10]
	add	w11, w11, w9
	str	w11, [x10]
	// lines_total += n
	adrp	x10, lines_total@PAGE
	add	x10, x10, lines_total@PAGEOFF
	ldr	w11, [x10]
	add	w11, w11, w19
	str	w11, [x10]
	// level = min(9, lines_total/10)
	ldr	w11, [x10]
	mov	w12, #10
	udiv	w11, w11, w12
	cmp	w11, #9
	b.ls	.Lcl_lvl
	mov	w11, #9
.Lcl_lvl:
	adrp	x10, level@PAGE
	add	x10, x10, level@PAGEOFF
	str	w11, [x10]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
