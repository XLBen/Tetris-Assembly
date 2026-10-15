import os, re, subprocess, sys

BIN = "./tetris"

def run(keys: bytes, seed=None, env=None):
    e = dict(os.environ); e.pop("SEED", None)
    if seed is not None: e["SEED"] = str(seed)
    if env: e.update(env)
    p = subprocess.run([BIN], input=keys, capture_output=True, env=e, timeout=30)
    return p.returncode, p.stdout

def frames(out): return out.split(b"\x1b[2J")[1:]      # 每帧含 ESC[H 起

def board_rows(frame): return [l for l in frame.split(b"\n") if l.startswith(b"|")]

CASES = {}

def t02():
    rc, out = run(b"xq")                     # 未知键 'x' 也产生一帧，'q' 退出
    assert rc == 0, rc
    for token in (b"TETRIS (ARM64)", b"SCORE 0", b"LEVEL 0", b"LINES 0", b"NEXT"):
        assert token in out, token
    fs = frames(out)
    assert len(fs) == 2, len(fs)
    rows = board_rows(fs[-1])
    assert len(rows) == 20, len(rows)
    for r in rows:
        # 剥掉 ANSI 颜色码后每行应为 | + 20 字符 + |（T03 起实心格带颜色码）
        plain = re.sub(b"\x1b\\[[0-9]+m", b"", r)
        assert plain.startswith(b"|") and plain.endswith(b"|") and len(plain) == 22, r

    # 确定性：T03 起画面含 PRNG 决定的当前块，须固定 SEED 才能对比两次运行
    _, out1 = run(b"xq", seed=1)
    _, out2 = run(b"xq", seed=1)
    assert out1 == out2, "两次运行 stdout 不相等"

CASES["t02"] = t02


def t03():
    # a) SEED 固定 -> 输出确定
    a = run(b"q", seed=7)[1]
    b = run(b"q", seed=7)[1]
    assert a == b, "两次运行 stdout 不相等"

    # b) 左移三次改变画面；两帧实心格 = 当前块 4 + NEXT 预览 4（T06 起预览生效）
    c = run(b"\x1b[D\x1b[D\x1b[Dq", seed=7)[1]
    assert c != a, "左移三次应改变画面"
    assert frames(a)[-1].count(b"[]") == 8, frames(a)[-1]  # T06 起当前块 4 + NEXT 预览 4
    assert frames(c)[-1].count(b"[]") == 8, frames(c)[-1]

    # c) 250 个未知键 = 25 个 tick：首块已锁定（4 格）+ 当前块
    d = run(b"x" * 250 + b"q", seed=7)[1]
    last = frames(d)[-1]
    assert last.count(b"[]") > 4, last.count(b"[]")
    assert b"SCORE 0" in last, last
    assert b"LINES 0" in last, last

CASES["t03"] = t03


def t04():
    # a) 旋转改变画面（SEED=7 首块 I，出生位旋转无碰撞）
    a = run(b"q", seed=7)[1]
    r = run(b"\x1b[Aq", seed=7)[1]
    assert r != a, "旋转应改变画面"

    # b) 硬降 70 次 -> GAME OVER；终局 SCORE 0 / LINES 0
    rc, out = run(b" " * 70 + b"q", seed=7)
    assert rc == 0, rc
    assert b"GAME OVER" in out, "输出缺 GAME OVER"
    last = frames(out)[-1]
    assert b"SCORE 0" in last, last
    assert b"LINES 0" in last, last

    # c) 同一命令再跑一次，stdout 逐字节一致
    rc2, out2 = run(b" " * 70 + b"q", seed=7)
    assert rc2 == 0, rc2
    assert out2 == out, "两次运行 stdout 不相等"

CASES["t04"] = t04


# T05 golden 脚本：规划期钉死（269 键 685 字节，SEED=2，60 块锁定，无死局）
GOLDEN = b'\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D \x1b[A\x1b[D \x1b[A\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D\x1b[D  \x1b[A\x1b[A \x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[D\x1b[D \x1b[C\x1b[C \x1b[A\x1b[A\x1b[A\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[C\x1b[C \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[C\x1b[C  \x1b[C\x1b[C \x1b[A\x1b[A\x1b[D\x1b[D\x1b[D \x1b[A\x1b[A\x1b[D\x1b[D \x1b[A\x1b[D\x1b[D\x1b[D\x1b[D \x1b[A\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D \x1b[C \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[A\x1b[D \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[D\x1b[D \x1b[A\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D\x1b[D \x1b[A\x1b[D\x1b[D\x1b[D  \x1b[C\x1b[C \x1b[C\x1b[C\x1b[C\x1b[C \x1b[D \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[D \x1b[C\x1b[C \x1b[A\x1b[A\x1b[A\x1b[C \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[D \x1b[A\x1b[A\x1b[D\x1b[D\x1b[D \x1b[A\x1b[C\x1b[C\x1b[C \x1b[D\x1b[D\x1b[D \x1b[A\x1b[C \x1b[D \x1b[D\x1b[D \x1b[A\x1b[C\x1b[C \x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D\x1b[D  \x1b[D \x1b[A\x1b[A\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[D\x1b[D\x1b[D \x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[D\x1b[D \x1b[A \x1b[A\x1b[C\x1b[C \x1b[C\x1b[C\x1b[C \x1b[D\x1b[D\x1b[D \x1b[C\x1b[C \x1b[D\x1b[D \x1b[A \x1b[A\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C \x1b[A\x1b[A\x1b[A\x1b[D\x1b[D\x1b[D\x1b[D q'

assert len(GOLDEN) == 685, len(GOLDEN)


def t05():
    # a) golden 重放：最后一帧 LINES 16 / SCORE 2600 / LEVEL 1，全程无 GAME OVER
    rc, out = run(GOLDEN, 2)
    assert rc == 0, rc
    assert b"GAME OVER" not in out, "输出含 GAME OVER"
    last = frames(out)[-1]
    assert b"LINES 16" in last, last
    assert b"SCORE 2600" in last, last
    assert b"LEVEL 1" in last, last

    # b) 同一脚本重跑，stdout 逐字节一致
    rc2, out2 = run(GOLDEN, 2)
    assert rc2 == 0, rc2
    assert out2 == out, "两次运行 stdout 不相等"

    # c) 逐帧 LINES 单调不减，最大值等于终值 16
    ls = [int(m) for m in re.findall(rb"LINES (\d+)", out)]
    assert all(a <= b for a, b in zip(ls, ls[1:])), ls
    assert max(ls) == ls[-1] == 16, ls[-1]

CASES["t05"] = t05


def t06():
    base_rows = board_rows(frames(run(b"q", 7)[1])[-1])

    # a) 首帧 [] 计数 == 8（当前块 4 + NEXT 预览 4）
    last = frames(run(b"q", 7)[1])[-1]
    assert last.count(b"[]") == 8, last.count(b"[]")

    # b) 暂停：输出含 PAUSED，30 tick 后棋盘与首帧一致（停表）
    pz = run(b"p" + b"x" * 30 + b"q", 7)[1]
    assert b"PAUSED" in pz, "输出缺 PAUSED"
    assert board_rows(frames(pz)[-1]) == base_rows, "暂停期间棋盘动了"

    # c) 不暂停：30 tick 掉 3 格，棋盘与首帧不同
    nb = run(b"x" * 30 + b"q", 7)[1]
    assert board_rows(frames(nb)[-1]) != base_rows, "30 tick 应改变棋盘"

    # d) 重开：game over 后按 r，画面回到开局局面
    rs = run(b" " * 70 + b"r" + b"q", 7)[1]
    assert board_rows(frames(rs)[-1]) == base_rows, "r 后应回到开局局面"


CASES["t06"] = t06

if __name__ == "__main__":
    names = sys.argv[1:]
    if names == ["all"]:
        names = list(CASES)
    for n in names:
        CASES[n](); print(n, "PASS")
