# tetris-arm64

macOS（Apple Silicon）上用纯 ARM64 汇编实现的终端俄罗斯方块：零 libc、只用系统调用、`ld` 直接链接，经典完整版玩法。

## 构建与运行

前提：Xcode Command Line Tools（`as` / `ld` / `xcrun`）。

```sh
make
./tetris
```

## 键位

| 键 | 功能 |
|---|---|
| `←` / `→` | 左移 / 右移 |
| `↓` 或 `j` | 软降一格 |
| `↑` 或 `k` | 顺时针旋转 |
| 空格 | 硬降 |
| `p` | 暂停 / 继续 |
| `r` | 重新开始 |
| `q` | 退出（恢复终端设置） |

## 固定序列

`SEED=<1..2^31-1> ./tetris` 用给定种子驱动方块序列（xorshift32），同一种子每局完全相同；不设 `SEED` 时用时钟初始化。自动化测试依赖它。

画面（`SEED=7` 开局首帧，实心格带颜色）：

```
TETRIS (ARM64)
|. . . [][][][]. . . |
|. . . . . . . . . . |
...（共 20 行棋盘）
+--------------------+
SCORE 0
LEVEL 0
LINES 0
NEXT [][][][]
←→ move · ↓ soft · ↑ rotate · space drop · p pause · r restart · q quit
```

## 架构

| 文件 | 职责 |
|---|---|
| `src/term.s` | 终端 raw mode（ioctl TIOCGETA/TIOCSETA）与按键读取 `key_read` |
| `src/main.s` | 入口 `_main`、`SEED=` 解析、主循环（渲染 → 读键 → 分发 → 重力 tick） |
| `src/game.s` | 游戏逻辑：PRNG、碰撞、出生/重置、按键处理、重力锁定、消行计分 |
| `src/render.s` | 整帧渲染：棋盘 + 当前块叠加、HUD、NEXT 预览、状态行 |
| `src/data.s` | 游戏状态标签、7×4 方块表、速度/计分表、渲染字符串 |

## 测试

```sh
python3 tests/play.py all
```

管道驱动端到端用例（固定 SEED 下断言画面、计分、消行、暂停、重开、GAME OVER）。
