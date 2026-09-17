# sm64ex 欧版无声修复补丁

修复 **sm64ex 欧版**（`VERSION=eu`）在片头结束后、进入可操作状态时**彻底没有声音**的问题。

- 上游 issue：[sm64pc/sm64ex#507 — Sound stops a few seconds after start with eu version](https://github.com/sm64pc/sm64ex/issues/507)
- **不需要更换 ROM**：仍然是欧版 ROM（Super Mario 64 (Europe) (En,Fr,De)，SHA1 `4ac5721683d0e0b6bbb561b58a71740845dceea9`）
- 补丁文件：[`eu-audio-fix.patch`](eu-audio-fix.patch)（`git format-patch` 格式，`git apply` / `git am` 均可）

---

## 症状

- 片头（Nintendo logo、Lakitu 开场）**有**声音
- 进入可操作状态后，**音乐和音效一起消失**，且不会恢复
- 欧版在 Linux / macOS / Windows 上同样中招；美版正常

## 根因

问题的根源跟音频代码无关，在 `Makefile` 里。

上游 `Makefile:166` 设了版本宏：

```make
VERSION_CFLAGS := -D$(VERSION_DEF) -D_LANGUAGE_C
VERSION_ASFLAGS := --defsym $(VERSION_DEF)=1
```

但 `Makefile:225` 又**整个覆盖**掉它：

```make
VERSION_ASFLAGS := --defsym AVOID_UB=1
```

（`AVOID_UB` 在整个仓库里没有任何 `.ifdef` 检查它，是个空定义。）

于是汇编器**永远拿不到 `VERSION_EU`**，下面这些版本分支全部成了死代码：

| 文件 | 版本条件数 |
|---|---|
| `include/seq_macros.inc` | 2 处 `.ifdef VERSION_EU` |
| `sound/sequences/00_sound_player.s` | 23 处（14 `.ifdef VERSION_JP` / 5 `.ifndef VERSION_JP` / 4 `.ifdef VERSION_EU`） |

序列 0（`00_sound_player`）**只由这个 `.s` 提供** —— `assets.json` 里没有它的提取条目，`sound/sequences/eu/` 也只有 `01_` 往后的文件。所以它被按**美版 opcode 布局**拼了出来：

| 宏（`.s` 中出现次数） | 美版编码 | 欧版编码 | 实际产物 |
|---|---|---|---|
| `chan_setnotepriority 14`（30 次） | `0x60 + 14` = `0x6E` | `0xE9` | **`0x6E`** ✗ |
| `chan_unreservenotes`（4 次） | `0xF1` | `0xF0` | **`0xF1`** ✗ |
| `chan_reservenotes n`（4 次） | `0xF2 n` | `0xF1 n` | **`0xF2 n`** ✗ |

欧版引擎再按**欧版语义**去解这串美版字节，连锁反应就发生了：

1. `0x60 | n` 被读成「通道延迟 n」，执行后 `goto out`，**跳过本通道剩余脚本**
2. 紧跟其后的 `F1 FB` 被读成 `chan_reservenotes`，参数 `0xFB` = **251**
3. `note_pool_fill` 于是把**全局音符池一次性抽干**，全部搬进该通道的私有池
4. 全局池空了以后，**所有**序列（包括 BGM）的 `alloc_note` 全部失败 → **永久静音**

### 实测证据

坏掉的 `00_sound_player.m64` 里 `F1 FB` 恰好出现 **3 次**，运行时插桩抓到的原话：

```
f=165 player=2 seqId=0 chan=17 pcoff=290 count=251
```

对应现象：`alloc_note` 调用次数持续增长，但成功次数**冻结在 25**、失败次数无限增长；全局池 `disabled=0`，而 16 个音符全被停在 `chan` 私有池里。

另一个决定性验证 —— 手工汇编对拍：

| 汇编方式 | 产物大小 |
|---|---|
| `as` 不带任何版本宏 | 13452 字节，与构建产物 **逐字节相同** |
| `as --defsym VERSION_EU=1` | 13500 字节（正确） |

## 补丁内容

共两处改动（`2 files changed, 7 insertions(+), 1 deletion(-)`）：

**1. `Makefile` —— 把覆盖改成追加，让版本宏重新到达汇编器（真正的修复）**

```diff
-VERSION_ASFLAGS := --defsym AVOID_UB=1
+# NOTE: this used to be a plain assignment, which discarded the
+# "--defsym $(VERSION_DEF)=1" set above. ...
+VERSION_ASFLAGS := $(VERSION_ASFLAGS) --defsym AVOID_UB=1
```

由于全仓库只有 `include/seq_macros.inc` 和 `sound/sequences/00_sound_player.s` 在读这些符号，这个改动的影响范围是闭合的，不会波及 `asm/` 下任何其它文件。

**2. `src/audio/port_eu.c` —— 补 `#include "heap.h"`**

`audio_reset_session()` 声明在 `heap.h:69`，而 `port_eu.c` 没有包含它。GCC 14 把隐式函数声明从警告升级成了**错误**，不加这一行根本编不过。**这一处与音频 bug 无关，可以单独剔除。**

## 应用方法

```sh
git clone https://github.com/sm64pc/sm64ex.git
cd sm64ex
git checkout nightly

git apply /path/to/eu-audio-fix.patch
# 或者保留提交信息：git am < /path/to/eu-audio-fix.patch
```

然后按仓库自己的说明放好欧版 ROM 并编译（`VERSION=eu`）。

## 验证方法

**1. 检查序列编码（最快）**

```sh
make VERSION=eu WINDOWS_BUILD=1
od -An -tx1 -j 286 -N 8 build/eu_pc/sound/sequences/00_sound_player.m64
# 修复前：01 10 f1 fb ...   ← 0xF1 是美版 chan_unreservenotes，会被欧版读成 reserve 251
# 修复后：01 2c f0 fb ...   ← 0xF0 是欧版 chan_unreservenotes
```

**2. 进游戏听**

片头结束后进入可操作状态，音乐应当持续播放，不会再突然静音。

## English summary

The EU build assembles `sound/sequences/00_sound_player.s` with the **US**
opcode layout, and the EU engine then misreads that byte stream.

`Makefile:225` overwrites `VERSION_ASFLAGS` with `--defsym AVOID_UB=1`,
discarding the `--defsym $(VERSION_DEF)=1` set at line 166.
`AVOID_UB` is never checked anywhere, so the version define is simply lost —
the assembler never sees `VERSION_EU`, and every `.ifdef VERSION_*` block in
`include/seq_macros.inc` and `sound/sequences/00_sound_player.s` becomes dead
code.

`00_sound_player` is the only sequence without a ROM-extracted `.m64`, so it is
the one that actually gets assembled from source. With the US layout,
`chan_setnotepriority 14` becomes `0x6E` instead of the EU `0xE9`, and
`chan_unreservenotes` becomes `0xF1` instead of the EU `0xF0`.

The EU engine reads `0x60 | n` as a channel delay that skips the rest of the
channel script, and the following `F1 FB` as `chan_reservenotes 251` — which
makes `note_pool_fill` move the entire global note pool into a single channel.
With the global pool empty, every later `alloc_note` fails for every sequence,
so all music and sound effects stop a couple of seconds after boot.

Fix: append to `VERSION_ASFLAGS` instead of overwriting it.
