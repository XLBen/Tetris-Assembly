// 终端 raw mode 与按键读取（T01）
// 键码：0=无/超时 1=左 2=右 3=下 4=旋转 5=硬降 6=暂停 7=退出 8=重开

	.text
	.balign 4

// term_enter_raw：stdin 切 raw；ioctl TIOCGETA 失败（非 tty）时 term_raw_ok=0 直接返回
	.globl term_enter_raw
term_enter_raw:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	sub	sp, sp, #160		// [sp]=工作 termios(72)，[sp+80]=保存副本(72)

	// ioctl(0, TIOCGETA, sp)
	mov	x0, #0
	movz	w1, #0x7413
	movk	w1, #0x4048, lsl #16	// TIOCGETA = 0x40487413
	mov	x2, sp
	mov	x16, #54
	svc	#0x80
	cbz	x0, .Lraw_got
	// 非 tty：term_raw_ok = 0
	adrp	x8, term_raw_ok@PAGE
	add	x8, x8, term_raw_ok@PAGEOFF
	str	wzr, [x8]
	b	.Lraw_done

.Lraw_got:
	// 原始 termios 存入 term_saved（term_restore 用）
	adrp	x10, term_saved@PAGE
	add	x10, x10, term_saved@PAGEOFF
	ldp	x8, x9, [sp]
	stp	x8, x9, [x10]
	ldp	x8, x9, [sp, #16]
	stp	x8, x9, [x10, #16]
	ldp	x8, x9, [sp, #32]
	stp	x8, x9, [x10, #32]
	ldp	x8, x9, [sp, #48]
	stp	x8, x9, [x10, #48]
	ldr	x8, [sp, #64]
	str	x8, [x10, #64]

	// c_lflag@24 &= ~0x588（ECHO|ICANON|ISIG|IEXTEN）
	ldr	x8, [sp, #24]
	mov	w9, #0x588
	bic	x8, x8, x9
	str	x8, [sp, #24]
	// c_iflag@0 &= ~0x300（IXON|ICRNL）
	ldr	x8, [sp]
	mov	w9, #0x300
	bic	x8, x8, x9
	str	x8, [sp]
	// c_cc[VMIN=16]=0（偏移48），c_cc[VTIME=17]=1（read 最多等 0.1s）
	mov	w8, #1
	strb	wzr, [sp, #48]
	strb	w8, [sp, #49]

	// ioctl(0, TIOCSETA, sp)
	mov	x0, #0
	movz	w1, #0x7414
	movk	w1, #0x8048, lsl #16	// TIOCSETA = 0x80487414
	mov	x2, sp
	mov	x16, #54
	svc	#0x80
	// term_raw_ok = 1
	mov	w8, #1
	adrp	x9, term_raw_ok@PAGE
	add	x9, x9, term_raw_ok@PAGEOFF
	str	w8, [x9]

.Lraw_done:
	add	sp, sp, #160
	ldp	x29, x30, [sp], #16
	ret

// term_restore：写回保存的 termios；恢复失败不管
	.globl term_restore
term_restore:
	mov	x0, #0
	movz	w1, #0x7414
	movk	w1, #0x8048, lsl #16
	adrp	x2, term_saved@PAGE
	add	x2, x2, term_saved@PAGEOFF
	mov	x16, #54
	svc	#0x80
	ret

// key_read -> w0：从 8 字节缓冲解析一个键，缓冲不足时 read(0, .., 8-len) 补充。
// read 返回 0：raw 模式下是 0.1s 超时 -> K_NONE（tick 源）；
// 非 raw（管道）下是 EOF -> K_QUIT（错误策略表）。
	.globl key_read
key_read:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp

.Lkr_top:
	adrp	x9, kbuf_len@PAGE
	add	x9, x9, kbuf_len@PAGEOFF
	ldr	w10, [x9]
	cbz	w10, .Lkr_read
	adrp	x8, kbuf@PAGE
	add	x8, x8, kbuf@PAGEOFF
	ldrb	w11, [x8]
	cmp	w11, #0x1b
	b.eq	.Lkr_esc
	b	.Lkr_one

// ESC [ X 三字节序列
.Lkr_esc:
	cmp	w10, #3
	b.lo	.Lkr_read		// 序列未收全，补读
	ldrb	w11, [x8, #1]
	cmp	w11, #0x5b		// '['
	b.ne	.Lkr_one		// ESC 后不是 [：单字节丢弃
	ldrb	w11, [x8, #2]
	sub	w0, w11, #0x40		// A B C D -> 1 2 3 4
	cmp	w11, #0x41
	b.lo	.Lkr_seq_bad
	cmp	w11, #0x44
	b.hi	.Lkr_seq_bad
	mov	w13, #5
	sub	w0, w13, w0		// A=4(旋转) B=3(下) C=2(右) D=1(左)
	mov	w12, #3
	b	.Lkr_consume
.Lkr_seq_bad:				// 未知序列：K_NONE，整段丢弃
	mov	w0, #0
	mov	w12, #3
	b	.Lkr_consume

// 单字节命令
.Lkr_one:
	ldrb	w11, [x8]
	mov	w0, #0
	mov	w12, #1
	cmp	w11, #0x20		// 空格 -> 硬降
	b.eq	.Lkr_c5
	cmp	w11, #0x6a		// j -> 软降
	b.eq	.Lkr_c3
	cmp	w11, #0x6b		// k -> 旋转
	b.eq	.Lkr_c4
	cmp	w11, #0x70		// p -> 暂停
	b.eq	.Lkr_c6
	cmp	w11, #0x71		// q -> 退出
	b.eq	.Lkr_c7
	cmp	w11, #0x72		// r -> 重开
	b.eq	.Lkr_c8
	b	.Lkr_consume
.Lkr_c3:
	mov	w0, #3
	b	.Lkr_consume
.Lkr_c4:
	mov	w0, #4
	b	.Lkr_consume
.Lkr_c5:
	mov	w0, #5
	b	.Lkr_consume
.Lkr_c6:
	mov	w0, #6
	b	.Lkr_consume
.Lkr_c7:
	mov	w0, #7
	b	.Lkr_consume
.Lkr_c8:
	mov	w0, #8
					// 落入 .Lkr_consume

// 消费 w12 字节（前移剩余字节），返回 w0
.Lkr_consume:
	ldr	w10, [x9]
	sub	w10, w10, w12
	str	w10, [x9]
	cbz	w10, .Lkr_ret
	add	x15, x8, x12
	mov	w13, #0
.Lkr_shift:
	ldrb	w14, [x15, x13]
	strb	w14, [x8, x13]
	add	x13, x13, #1
	cmp	w13, w10
	b.lo	.Lkr_shift
.Lkr_ret:
	ldp	x29, x30, [sp], #16
	ret

// 缓冲空：read(0, kbuf+len, 8-len)，成功则回到解析
.Lkr_read:
	adrp	x8, kbuf@PAGE
	add	x8, x8, kbuf@PAGEOFF
	ldr	w10, [x9]
	mov	w2, #8
	sub	w2, w2, w10
	add	x1, x8, x10
	mov	x0, #0
	mov	x16, #3
	svc	#0x80
	cbz	x0, .Lkr_eof
	ldr	w10, [x9]
	add	w10, w10, w0
	str	w10, [x9]
	b	.Lkr_top

.Lkr_eof:
	adrp	x10, term_raw_ok@PAGE
	add	x10, x10, term_raw_ok@PAGEOFF
	ldr	w11, [x10]
	cbz	w11, .Lkr_quit
	mov	w0, #0			// 超时 -> K_NONE
	b	.Lkr_ret
.Lkr_quit:
	mov	w0, #7			// EOF -> K_QUIT
	b	.Lkr_ret

	.section __DATA,__bss
	.balign 4
	.globl term_raw_ok
term_raw_ok:
	.space 4
	.globl term_saved
term_saved:
	.space 80
kbuf:
	.space 8
kbuf_len:
	.space 4
