// 入口与主循环：term_enter_raw → 解析 SEED → game_reset
// 主循环：render_frame → key_read → 键码交 game_handle_key（T06 起 6 暂停/8 重开也在内）；
//         K_QUIT 退出；只有 K_NONE 推进 tick_ctr（达到 speed_tbl[level] 触发 game_tick）
	.text
	.balign 4
	.globl _main
_main:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp

	bl	term_enter_raw

	// SEED= 解析（裁定 T03-1）：本机 macOS 26 直链接入口栈无标准 argc/argv/envp 布局
	// （实测 argc 在原始 sp+0x88，envp 指针数组不可用）。改为在入口栈参数页内
	// 直接字节扫描 "SEED="：无指针解引用，天然兼容布局变化。
	add	x22, sp, #16			// 原始 sp
	bic	x25, x22, #0x3fff		// 当前 16K 页基址
	add	x25, x25, #0x4000		// 页尾 = 第一不可读字节
	sub	x25, x25, x22			// 剩余可扫长度
.Lseed_env:
	cmp	x25, #8
	b.lo	.Lseed_random			// 剩余不足一次双读 -> 扫完没找到 -> 随机
	ldr	w23, [x22]
	mov	w20, #0x4553			// "SE"
	movk	w20, #0x4445, lsl #16		// "ED" -> "SEED"
	cmp	w23, w20
	b.ne	.Lseed_adv
	// 低 4 字节是 "SEED" 后，检查 [x22,#4] 低字节是否 '='
	ldrb	w24, [x22, #4]
	cmp	w24, #0x3d
	b.ne	.Lseed_adv
	add	x21, x22, #5
	mov	x15, #0
.Lseed_digit:
	ldrb	w12, [x21], #1
	cbz	w12, .Lseed_have
	sub	w12, w12, #0x30
	cmp	w12, #9
	b.hi	.Lseed_adv			// 非数字：此处不是合法 SEED=<n>，继续扫
	movz	w14, #0xCCCC			// 214748364 = 0x0CCCCCCC
	movk	w14, #0x0ccc, lsl #16
	cmp	x15, x14
	b.hi	.Lseed_next			// 越界：放弃候选，跳过前缀继续扫
	b.lo	.Lseed_mul
	cmp	w12, #7				// x15==214748364 时末位只能 0-7
	b.hi	.Lseed_next
.Lseed_mul:
	mov	x14, #10
	mul	x15, x15, x14
	add	x15, x15, x12
	b	.Lseed_digit
.Lseed_have:
	cbz	x15, .Lseed_random		// SEED=0 视为未设置
	adrp	x12, init_seed@PAGE
	add	x12, x12, init_seed@PAGEOFF
	str	w15, [x12]
	b	.Lseed_done
.Lseed_next:
	add	x22, x22, #5			// "SEED" 匹配但值非法：跳过前缀继续
	sub	x25, x25, #5
	b	.Lseed_env
.Lseed_adv:
	add	x22, x22, #1
	sub	x25, x25, #1
	b	.Lseed_env
.Lseed_random:
	sub	sp, sp, #16
	mov	x0, sp
	mov	x16, #116			// gettimeofday
	svc	#0x80
	ldr	w15, [sp, #8]			// tv_usec 低 32 位
	orr	w15, w15, #1
	adrp	x12, init_seed@PAGE
	add	x12, x12, init_seed@PAGEOFF
	str	w15, [x12]
	add	sp, sp, #16
.Lseed_done:
	bl	game_reset

.Lmain_loop:
	bl	render_frame
	bl	key_read
	cmp	w0, #7				// K_QUIT
	b.eq	.Lmain_quit
	cmp	w0, #1
	b.lo	.Ltick				// K_NONE
	bl	game_handle_key			// 1-5 游戏键与 6/8（暂停/重开）
	b	.Lmain_loop
.Ltick:
	adrp	x8, tick_ctr@PAGE
	add	x8, x8, tick_ctr@PAGEOFF
	ldr	w9, [x8]
	add	w9, w9, #1
	adrp	x10, level@PAGE
	add	x10, x10, level@PAGEOFF
	ldr	w10, [x10]
	adrp	x11, speed_tbl@PAGE
	add	x11, x11, speed_tbl@PAGEOFF
	ldr	w11, [x11, x10, lsl #2]
	cmp	w9, w11
	b.lt	.Ltick_store
	str	wzr, [x8]
	bl	game_tick
	b	.Lmain_loop
.Ltick_store:
	str	w9, [x8]
	b	.Lmain_loop

.Lmain_quit:
	adrp	x8, term_raw_ok@PAGE
	add	x8, x8, term_raw_ok@PAGEOFF
	ldr	w9, [x8]
	cbz	w9, .Lquit_out
	bl	term_restore
.Lquit_out:
	mov	x0, #1
	adrp	x1, msg_nl@PAGE
	add	x1, x1, msg_nl@PAGEOFF
	mov	x2, #1
	mov	x16, #4
	svc	#0x80
	mov	x0, #0
	mov	x16, #1
	svc	#0x80

	.data
	.balign 4
msg_nl:
	.ascii "\n"
