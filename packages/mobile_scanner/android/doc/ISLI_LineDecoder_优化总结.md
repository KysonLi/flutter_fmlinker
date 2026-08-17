# ISLI 行码（linecode）解码性能优化总结

> 日期：2026-07-30 | 分支：main | 基准日志：`run.log` → `run2.log`

## 解码率优化 - BCH(127) 接受错误上限 5→6（2026-08-06）- DR-1

> 方向：解码率（accuracy），区别于下方已收敛的 bit-exact 性能循环 | 平台：x86_64 PC bench（/O2 /DNDEBUG），cache/cache1/cache2/cache3 共 1798 图 | `_none_`=真机解码失败帧（用户澄清：非盾牌缺失）

**背景与失败桶分解**：单帧解码率仅 **13.1%（235/1798）**。临时仪表（BchHelper.cpp 跨 sync 组合的最小 BCH err_num + 是否到达 BCH；ISLILineDecoder.cpp 帧入口 reset + 失败出口 ILD_LOGI）分解 1563 失败帧：

| 失败桶 | 数 | % | 含义 | 杠杆 |
|---|---|---|---|---|
| 定位拒（从未到 BCH） | 988 | 63% | vertical_locating 找点<7 / bar_locating 失败 | 定位/二值化/多尺度（最大头，后续 DR-2） |
| BCH 位太噪（syndrome 全不可纠） | 293 | 19% | 位乱 / 错 sync | 软判决 Chase / 扩展 sync |
| 安全帽可救（min err=6/7） | 237 | 15% | 理论 t=7 可纠，安全帽 ≤5 拒 | **抬帽（本轮 DR-1）** |
| 后置拒（min≤5 仍 0） | 45 | 3% | zero-bit 区/ECC 重算不符/退化 | 逐帧边缘 |

**改动（单点）**：`BchHelper.cpp::ild_bits_decode2` 接受条件 `err_num <= 5` → `<= 6`。一行。BCH(127,80,d=15) 理论纠错半径 t=7；≤6 纠错唯一无误纠（误纠需真实错误>7 且 syndrome 凑成 ≤6 可纠模式再骗过 ECC 重算守卫，概率低）。抬到 7 会引入误纠（见下）。

**A/B（PC bench_release /O2 /DNDEBUG, 4 目录 1798 图, dir-tagged join 防 4 目录文件重名）**：

| 改动 | 拯救 | 回归 | FP | 解码率 |
|---|---|---|---|---|
| cap 5→**6**（本轮 ship） | **+54~55** | 0 | **0**（拯救码全匹配 4 个 GT 码 2701/2702/00104/0110） | 13.1%→16.1% |
| cap 5→7（测后否决） | +87 | 0 | **1**（误纠 `6917547428424972546` ∉ GT，却过 ECC 重算守卫） | →17.9% |

cap=7 多救 32 帧不值 1 FP，否决；保留 cap=6。±1 帧抖动系已知 borderline 非确定性（syncRow 未初始化读，见下方收敛报告遗留），非本改动回归。

**FP 判定方法（_none_ 帧无逐帧 GT）**：以"解码码 ∈ 4 个真机 GT 码集 + ECC 重算守卫通过"为正确性证据，不完美但强（cap=7 的 1 个误纠正是不属 GT 集而被捕）。生产环境无 GT 集，靠 BCH 唯一纠错性 + ECC 守卫。

**遗留**：临时仪表已移除（仅留 cap 一行 diff）。下一轮 DR-2 原计划攻定位桶，但被数据推翻（见下 DR-2，重定为 bit 提取/BCH）。

---

## 解码率优化 - decode_waves(112) pos-retry 同步抖动兜底（2026-08-06）- DR-2

> 方向：解码率（accuracy） | 平台：x86_64 PC bench（/O2 /DNDEBUG），4 目录 1798 图 | 承接 DR-1（cap=6，解码率 16.1%）

**DR-1 遗留的"攻定位桶"被数据推翻 → 重定向到 bit 提取/BCH**：DR-1 末计划攻 locating 拒桶(988,63%)。但 reject_stage × 锐度(maxgrad)交叉表显示：锐盾(maxgrad≥12)失败 199 帧中 **132(66%) 败在 wave/BCH(stage2) 而非 locate**；locate 拒桶里 504 是弱条(模糊/低对比度,非逻辑缺陷)，仅 67 锐盾被 locate 漏检。故最高价值 tractable 桶 = **锐盾 stage2(132)**，非 locating(67)。方向重定为 bit 提取/BCH。

**进一步定位（min-err 仪表）**：stage2 BCH-ran-fail(bits 产出但 >6 错)的最小 err_num **双峰**——7(刚过 cap)或 999(syndrome 全不可纠=garbage)，无中间值(BM 算法特性)。锐盾 114：**min-err=7 共 50 帧**(retry-tractable) + 56 garbage(位太错，retry 无用) + 8 min<7(后置拒)；弱条 407：min-err=7 共 129 + 236 garbage。**pos-retry 目标 = 179 帧 min-err=7**(50 锐盾高置信 + 129 弱条)。

**改动（单点，纯增量）**：`ISLILineDecoder.cpp::decode_waves` 在 112-bit 主路径(Δ=0 sync 组合 ×2 极性)未解码时，追加 **pos-retry 兜底**——对每个 sync 组合作整体 ±1/±2 平移后再采样(`ild_wave2bits112`)，救援"真实同步中心相对整数中点 (v1+v2)/2 偏移 ~1 sample 致采样点漂移到 bit-cell 边缘、少量 bit 翻转"的 min-err=7 边缘帧。主路径逐字节不变(cap `return 0`→`break` 仅让失败帧落入兜底)；FP 由 BCH cap≤6 + 再编码守卫兜底(均不变)。

**A/B（PC bench_release /O2 /DNDEBUG, 4 目录 1798 图, dir-tagged join）**：

| 指标 | BEFORE(无 pos-retry) | AFTER(pos-retry) |
|---|---|---|
| 解码 | 289 (16.07%) | 305~306 (16.9%+) |
| 拯救 | — | **+17**（全 ∈ 4 GT 码 → **0 FP**）|
| 回归 | — | −1（见下，非确定性）|
| 净 | — | **+16** |
| 经 jitter 成功(profile 日志证实) | — | 15 帧(pos-retry delta=±1/±2) |

**非确定性附注（重要）**：唯一"回归"帧 `cache2/00063_55ms`(BEFORE=2702, AFTER=NONE)经隔离测试证实为**预存跨帧非确定性**，非 pos-retry 逻辑缺陷——**同一 AFTER 二进制**在 2 帧批解码为 2702、458 帧批为 NONE。根因 linecode 已知 syncRow `tl::buffer` 未初始化读(堆残留耦合)，任何代码/分配模式变化都会重排堆布局、翻转 borderline 帧，使**严格 0-回归对任意改动均不可达**。pos-retry 本身纯增量、逻辑正确(隔离下解码该帧)。

**FP 判定**：同 DR-1（解码码 ∈ 4 GT 码集 + ECC 守卫）。17 拯救码 = 10×2701 + 6×2702 + 1×00104，全 GT，0 FP。

**遗留**：临时仪表(stage/min-err)已全部移除(仅留 decode_waves pos-retry 一处 diff)。

## 解码率优化 - sub-bit 分数相位重采样（2026-08-06）- DR-3【否决】

> 方向：解码率（accuracy） | 承接 DR-2（pos-retry +16，解码率 16.9%+） | DR-2 遗留候选 (b)，pos-retry 增益不足时升级

**思路**：DR-2 pos-retry 仅沿整数采样栅格 ±1/±2 平移。DR-3 在 `ild_wave2bits112` 增加 `double phase=0.5` 参数（采样点 `0.5*det`→`phase*det`），对失败帧额外跑 phase∈{0.35,0.4,0.45,0.55,0.6,0.65} 的分数相位 tier，产不同 bit 假设救援边缘帧。

**改动（单点）**：`Wave2Bits.cpp/.h` 加 phase 参数；`ISLILineDecoder.cpp::decode_waves` 在 pos-retry 之后追加 phase-retry tier。

**A/B（1798 图，同 DR-2 bench）**：

| 指标 | DR-2(pos-retry) | DR-3(+phase-retry) |
|---|---|---|
| 总解码 | 305 | 305 |
| 净增 | — | **0** |
| phase-retry 实际救援(profile 日志) | — | 仅 1 帧(cache) |

**否决原因**：相位平移 ≈ pos-retry 采样点平移（**冗余**）；唯一差别（固定阈值斜坡 th[k]→th[k+1]）仅救 1 个边缘帧，又被跨帧非确定性吃掉（见 DR-2 非确定性附注）。不值 per-failed-frame 成本。**已 `git checkout HEAD` 全量回退**，代码回到 clean DR-2（293d0d4）。

**结论**：retry / extraction-retry 杠杆至此穷尽。剩余更难杠杆（均需用户定向）：(a) 修 syncRow 未初始化读→确定性；(b) 弱条预处理（对比度/自适应阈值/多尺度，~970 帧）；(c) 更好 wave2bits extraction 攻 garbage(999) 桶 292 帧（retry 无效，需改 extraction：更好 sync / 逐段自适应阈值 / 软判决）。

## 解码率优化 - mean 阈值重采兜底（2026-08-06）- DR-4

> 方向：解码率（accuracy） | 承接 DR-2（pos-retry +16，解码率 16.9%+） | DR-3 否决后承接其候选 (c)：更好 wave2bits extraction 攻 garbage 桶

**思路**：DR-1/DR-2 诊断显示 stage2 失败帧的 bit 提取阈值 `mean_of_peak2vally` 取「窗内 min/max 中点」——离群像素（噪点 / 条边缘溢出）会拉偏中点 → bit 翻转 → garbage。DR-4 给该函数加 `bool use_mean`：true 时改用窗内**均值**（抗离群），作为主路径(midpoint) + pos-retry 全部失败后的**兜底 tier** 重采所有 sync 组合。先做 ceiling A/B（把主路径阈值也换成 mean）= **+38 GT 0 FP**，证明均值阈值确能救帧；落地为兜底（midpoint 先跑，已解码帧逐字节不变）以保 0 回归。

**改动（单点，纯增量）**：
- `Wave2Bits.cpp/.h`：`mean_of_peak2vally` + `ild_wave2bits112` 加 `use_mean` 参数（默认 false = midpoint，主路径逐字节不变）。
- `ISLILineDecoder.cpp::decode_waves`：pos-retry 之后追加 mean-thr 兜底（2 极性 × 所有 sync 组合，cap `decode_count>3000`）。另把 pos-retry 的 `decode_count>450` 由 `return 0` 改 `cap_hit=true; break`，让触顶的高组合帧也能落入 mean-retry（否则被提前 return 跳过兜底）。

**A/B（PC bench_release /O2 /DNDEBUG, 4 目录 1798 图, dir-tagged join, 干净构建无仪表）**：

| 指标 | BEFORE(DR-2, 无 mean-retry) | AFTER(+mean-retry) |
|---|---|---|
| 解码 | 304 (16.9%) | **333 (18.5%)** |
| 拯救(NONE→GT) | — | **+29**（全 ∈ 4 GT 码 → **0 FP**）|
| 回归(GT→NONE) | — | **0** |
| 回归(changed) | — | **0** |

**为何兜底(+29) < 全局 ceiling(+38)**：兜底只对「主路径 + pos-retry 都失败」的帧跑 mean；ceiling 对每次 wave2bits（含 64-bit 主路径）都用 mean。两者救援高度重叠——decode_waves mean-retry 已救的帧不会再进 decode_waves2，故 64-bit mean-retry 实测 **+0（已移除，单点收敛）**。剩余 ~+9 差距系跨帧非确定性噪声地板（见 DR-2 附注，±1~2 borderline 帧）+ ceiling 计数口径差异，非可稳定追回的真实增益。

**性能权衡**：mean-retry 仅在主路径 + pos-retry 全失败的帧上执行（已解码帧提前 return，逐字节不变 → 0 回归 0 FP）。失败帧多跑 ≤ 2×|sync 组合| 次 wave2bits + BCH（cap 3000），增加这些（原本就失败）帧的耗时；解码成功帧不受影响。属精度优化，可接受。

**遗留**：临时诊断仪表（garbage 桶 `elp->deg` 度量 / peak-valley 快照 / bench `diag` 模式）已全部移除，仅留 decode_waves mean-retry + Wave2Bits `use_mean` 两处 diff。

## 解码率优化 - 锐盾 locate 漏检 ±1 桶回退（2026-08-07）- DR-5【否决】

> 方向：解码率（accuracy） | 承接 DR-4（mean-retry +29，解码率 18.5%, 333/1798） | 攻 DR-1 失败桶分解里 locating 拒(988)中锐盾(maxgrad≥12)被 locate 漏检的 67 帧（DR-2 已攻 132 锐盾 stage2，此 67 锐盾 locate-fail 是 DR-2 遗留的 tractable 桶）

**诊断（per-frame reject-stage + RLE 仪表）**：67 锐盾全败 `vertical_locating`（pt_vec<7，66）/ span<64（1）。两子群根因不同：

| 子群 | 数 | 症状 | 瓶颈 |
|---|---|---|---|
| **A** | 47 | raw≤6（match_pattern_rle 几乎不命中） | 列非周期——PAT(6-8 run)列存在(11.6/帧)但相等性约束拒绝；疑轻度旋转未被上游 deskew 纠正，或低对比短曝光 cache1 帧二值化塌缩 |
| **B** | 20 | raw 13~71 但 pt_vec 2~6 | `rotate_and_detect` 严格单桶(8px)共线性过滤把散点砍到 <7 |

**RLE 诊断（关键，反直觉）**：失败帧二值化列更"干净"（均值 8 run/列，clean-frac 0.573）vs 解码帧（16 run/列，clean-frac 0.243）——**非斑点噪声**，是列结构本身不足（解码帧列周期性丰富 → 匹配；失败帧列稀疏/非周期 → 不匹配）。`SKEW_SCAN_DIS=5` 是**死常量**，无斜向扫描；旋转仅靠上游 deskew（`|tiltD|`≥阈值才触发），轻度旋转漏纠致垂直列被涂抹。

**改动（单点，DR-4 式回退）**：`BarLocator.cpp::rotate_and_detect` 在严格单桶 `filter_dot_in_line` 后，若 `filtered_vec.size() < LOCATE_MIN(7)` 则回退保留峰桶 **±1**（24px 线宽容 vs 严格 8px）。已能定位的帧（≥7）走严格路径，逐字节不变（0 回归 by construction），FP 由 BCH cap≤6 + 再编码守卫兜底。

**A/B（PC bench_release /O2 /DNDEBUG, 4 目录 1798 图, dir-tagged join, `ILD_DR5B` 宏切换）**：

| 指标 | BEFORE(无 DR-5b) | AFTER(+DR-5b) |
|---|---|---|
| 解码 | 332 | **332** |
| 拯救(NONE→GT) | — | **0** |
| 回归/错码 | — | **0 / 0** |

**但 stage 分布有变化**：DR-5b 把 ~6 帧推过 locate 门（stage 3=1 / stage 5=5，即进到 bar/wave/BCH），却**全在下游失败**——宽桶给的中心估计更差，`locate_single_bar`/wave 提取用不了。

**否决原因**：B 子群的 raw 匹配是**噪声**（非"抖动的真实中心"）——放宽过滤只纳入噪声、劣化中心，下游拒绝。locate 侧松绑对 A 子群（raw≤6，无点可留）亦无效。**根因在上游**：二值化/deskew 的列质量，非 locate 逻辑缺陷。locate 侧杠杆至此穷尽。

**结论/遗留**：临时仪表（rej 模式 / RLE-len 桶 / g_reject_stage / g_raw_vloc_pts）已全部移除，`BarLocator.cpp`/`BSPatternMatch.cpp`/`ISLILineDecoder.cpp/.h`/`bench/main.cpp` 全量回退至 clean DR-4（2f970e5），0 diff。剩余 67 锐盾 + ~970 弱条为上游质量约束（二值化自适应阈值 / deskew 阈值 / 多尺度），非低风险单点可救，需用户定向。

## 解码率优化 - 自适应二值化阈值偏置重阈值兜底（2026-08-07）- DR-6【已 ship】

> 方向：解码率（accuracy） | 承接 DR-5 否决（locate 侧杠杆穷尽，根因在上游二值化/deskew 列质量）| 用户定向「2 = 攻上游二值化」，目标 ~970 弱条帧 + 67 锐盾（DR-1 失败桶 locating 拒 988 的主体）。改动每帧阈值 → 真实回归风险，故采用**兜底**架构规避。

**核心洞察**：高斯二值化 `out[i] = img[i] >= blur[i] ? 255 : 0` 中，**blur 与阈值偏置无关**——偏置只改比较右端 `blur[i]+bias`，blur 本身不变。故对同一 `enlarged` 用不同 bias 重阈值时，可**复用主路径刚算好的 `g_blur`**（持久 scratch），跳过占二值化 ~75% 的高斯模糊，兜底仅多一个阈值比较循环。

**bias 扫描（ceiling A/B，主路径阈值直接加 bias）找全局峰**：

| bias | -8 | -6 | -5 | -4 | -3 | -2 | 0 | +4 | +8 |
|---|---|---|---|---|---|---|---|---|---|
| 净增(rescue−regress) | -32 | +6 | **+12** | +10 | +5 | +2 | — | +1 | -7 |

`bias=-5` 为全局峰（rescue 44 / regress 32 / mismatch 0）。bias<0 → 阈值更低 → 更多白/更细条，救援高斯阈值下塌缩成实心块的弱对比条。

**改动（单点，DR-4 式兜底）**：
1. `GaussianBinarization.cpp/.h`：新增 `ild_gaussian_rethreshold(img, out, bias)`——复用 `g_blur`，仅跑 `out[i] = img[i] >= blur[i]+bias ? 255 : 0`。前提：`ild_gaussian_binarization` 已对同一 img 调用过（`g_blur` 有效），bit-exact 于「对该 img 做完整 bias 二值化」。
2. `ISLILineDecoder.cpp::decode_landscape`：主路径 `decode_from_binary`（bias=0）失败后，`ild_gaussian_rethreshold(enlarged, bin_img, -5)` 重阈值并重跑 `decode_from_binary`。**主路径逐字节不变**（已解码帧提前 return，0 回归 by construction）。

**A/B（PC bench_release /O2 /DNDEBUG, 4 目录 1798 图, dir-tagged join, `ILD_DR6` 宏切换）**：

| 指标 | BEFORE（DR-4, bias=0 only） | AFTER（+ bias=-5 兜底） |
|---|---|---|
| 解码 | 333 (18.5%) | **377 (21.0%)** |
| 拯救(NONE→GT) | — | **+44**（全 ∈ 4 GT 码 → **0 FP**）|
| 回归(GT→NONE) | — | **0** |
| 回归(changed) | — | **0**（0 mismatch）|

兜底 +44 ≈ ceiling +12 的 rescue 子集（ceiling 的 regress 帧已由主路径解码，兜底不触发）；0 回归 by construction。`cache1/..._...0104_34ms` 帧解码与其文件名 GT 一致（before.tsv 缺索引 0 帧未计入）。宏切换的 macro-AFTER 测得 +45，always-on 落地 +44，±1 系 [[linecode-syncrow-uninit-read]] 噪声地板。

**性能权衡**：兜底仅对 bias=0 失败帧执行（成功帧提前 return，逐字节不变）。失败帧多付一个阈值比较循环（~1.1M 像素，廉价）+ 一次完整 `decode_from_binary`（locate+wave+BCH，主成本）。复用 blur 跳过冗余高斯模糊（占二值化 ~75%）。cache1（304 帧，失败帧密集——最坏情形）计时（3 warmup + 7 runs）：

| 指标 | BEFORE | AFTER(rethreshold) | Δ |
|---|---|---|---|
| per-image mean-of-means | 3.382 ms | 4.111 ms | **+21.6%** |
| per-image median | 3.254 ms | 3.527 ms | **+8.3%** |

中位数仅 +8.3%（中位帧走主路径成功，不触发兜底）；均值 +21.6%（cache1 失败率高，多数帧付兜底成本）。完整再二值化版本（含冗余 blur）失败帧 +78%，rethreshold 复用 blur 将其压到 +22%。属精度优化，可接受。

**遗留**：无临时仪表；diff = `GaussianBinarization.cpp/.h`（`ild_gaussian_rethreshold`）+ `ISLILineDecoder.cpp`（decode_landscape 兜底）三处。retry(DR-2/4) + locate(DR-5) + 二值化偏置(DR-6) 三杠杆已用；累计解码率 13.1%(235)→21.0%(377)。

## 解码率优化循环 - 收敛停止（2026-08-07）

**决定：停止 linecode 解码率优化。** 用户拍板收敛。DR-1..DR-6 六轮单点迭代穷尽三类低风险杠杆（兜底架构，主路径逐字节不变，0 回归 0 FP），累计单帧解码率 **13.1%(235/1798) → 21.0%(377/1798)，+142 帧（+60.4%）**。

**累计成果（全 0 FP 0 回归，主路径不变 by construction）**：

| 轮次 | 杠杆 | 改动 | 增益 | 结果 | commit |
|---|---|---|---|---|---|
| DR-1 | BCH 帽 | cap 5→6 | +55 | ship | b0bf669 |
| DR-2 | retry | decode_waves pos-retry 兜底 | +16 | ship | 293d0d4 |
| DR-3 | retry | sub-bit 分数相位重采样 | 0 | **否决**（≈pos-retry 冗余） | (回退) |
| DR-4 | retry | decode_waves mean-阈值重采兜底 | +29 | ship | 2f970e5 |
| DR-5 | locate | rotate_and_detect 锐盾 ±1 桶回退 | 0 | **否决**（根因在上游 bin/deskew 列质量） | (回退) |
| DR-6 | 二值化 | bias=-5 rethreshold 兜底(复用 g_blur) | +44 | ship | 17fea21 |

**三杠杆穷尽**：retry（DR-2/4 采样栅格平移）、locate（DR-5 定位松绑）、二值化偏置（DR-6 阈值）。失败桶分解：locating 拒 988(63%) / BCH 位太噪 293(19%) / BCH 安全帽可救 237(15%, DR-1 已抬 cap 回收大部分) / 后置拒 45(3%)。

**未采方向（均需用户定向，风险高于已用兜底）**：
- (a) 修 `syncRow` 未初始化读 → A/B 确定性（可能回收被坏堆布局吞的帧，但干净修复需重做 median，高风险）—— 见 [[linecode-syncrow-uninit-read]]。
- (b) `deskew` 阈值 / `tiltD` 估计改进（救轻度旋转涂抹列，但影响全帧，回归风险高）。
- (c) DR-6 扩展为多偏置/多尺度兜底链（每加一层失败帧成本累加）。

**性能（per LC 收敛报告）**：解码主路径 bit-exact 优化亦收敛（gauss ~75% 瓶颈穷尽，vertical_locating/bar_locating 经 hoist 优化）。DR-6 兜底对成功帧 0 成本，失败帧 mean +22%。

---

## 收敛报告 - linecode 解码性能优化（2026-08-06）

**结论：bit-exact 优化循环收敛。** 经 LC-1..LC-6 六轮单点迭代，单帧解码主瓶颈(gauss ~75%)穷尽核查收敛，#2/#3 瓶颈(vertical_locating / bar_locating)经缓冲复用 hoist 显著优化，剩余阶段均计算/带宽受限且 bit-exact 天花板低。继续单点迭代 ROI 不足。

**累计成果（全 bit-exact，0 回归 0 FP）**：
| 轮次 | 优化 | 效果 | commit |
|---|---|---|---|
| LC-1..4 | gauss 二值化穷尽核查(box/N-box/核截断/融合阈值/wave滑动求和 共7候选) | 全否决，gauss 收敛(x86 计算受限 mullo_epi32 主导，SSE4.1/NEON 已最优) | 31d744a(回退) |
| LC-5 | vertical_locating: rotate_angle 直方图缓冲提出 ~381 次角度循环外复用 | rotate -10.3% bit-exact | 8e2c913 |
| LC-6 | bar_locating: detect_pattern_precisely 6 暂存缓冲(line/points/upward/downward/rle_up/rle_down) hoist | bar_locating -63.4%, total median -5.0% | 276579d |

**最终阶段分解（PC bench /O2 /DNDEBUG, cache 413 图, µs，profile 隔离）**：
gaussian_binarize 3122(75%) > vertical_locating ~415(10%) > wave_sampling 114(2.7%) > interpolation 104(2.5%) > pre_crop 97(2.3%) > bar_locating ~91(2.2%, LC-6 后) > sync_crop 12 > deskew 8 > clean_flat 7。

**收敛依据（LC-6 后快速扫描 interpolation/wave_sampling/pre_crop）**：
- **interpolation**：纯 `memcpy`+NEON `vrhaddq` 均值，0 堆分配，内存带宽受限，已 SIMD 化。
- **wave_sampling / pre_crop**：调用 1-2 次/解码，仅 ~3-6 alloc/解码（噪声级），计算受限（曲线采样 / 互相关+行投影）。
- **alloc-hoist 模式已耗尽**：该模式仅在"紧密循环内数百次/帧、每次 fresh buffer"时收益大（rotate 角度扫描、bar 采样）；剩余阶段无此结构。
- 剩余 bit-exact 头寸每阶段 <3%，计算/带宽受限，算术不可重组(bit-exact)。

**未触及/搁置（非 bit-exact，约束下不追）**：
- 角度扫描粗-精两阶段（vertical_locating 381→~113 次，rotate -70%/total ~-4%）：改角度选择→可能改解码，且 ~4% 非"大幅"，搁置。
- `detect_signle_bar` 冗余折叠、`detect_pattern_precisely` `SCAN_STEP` 倍增、wave 滑动求和、gauss 融合阈值：均非 bit-exact。
- **decode_waves（BCH 误差纠正 + sync 组合循环）**：无阶段计时器，位于 ~remainder，计算受限(BCH 代数)，bit-exact 天花板低；唯一未剖析的非平凡块，如需百分百确定可加临时计时器。

**遗留事项**：
- image 00148 syncRow 未初始化读致间歇假阴性：根因已定位(tl::buffer 不初始化+边缘行 continue)，zero-init 修复回归(73→72)已回退，干净修复需重做 median(仅含已测行)，deferred。
- `bch.cpp` 有 pre-existing 未提交 `memset(ptr,0,size)` 改动（非本会话，未触碰）。

**真机预期**：alloc-hoist 在移动端(分配器/cache 更贵)增益预期 > PC（LC-6 PC -5% median，真机应更显著）。gauss 在 ARM 真机已收敛。bench 在 `line_test_data/bench`（stage 分解须 `ILD_LOGLEVEL=3`，main.cpp 默认 OFF=0）。

---

## bar_locating 采样/RLE 暂存缓冲复用（2026-08-06）- LC-6

> 优化编号：LC-6 | 平台：x86_64 PC bench（/O2 /DNDEBUG），cache 413 图 | 前序：LC-5（vertical_locating 后转 #3 瓶颈）

**Profile（µs 阶段计时，ILD_LOGLEVEL=3 聚合 cache 413 图）**：gauss(3153µs,75% 收敛) + vertical_locating(415µs, LC-5 已优化) 之后，**bar_locating 249.9µs（~6%，#3）**。bar_locating = `ild_locate_single_bar` = `detect_pattern_precisely`（~数百次/帧）+ `detect_signle_bar`。

**瓶颈定位（代码审查）**：每次 `detect_pattern_precisely` 调用都新建 **6 个暂存缓冲**——`line`(tl::buffer reserve1024)、`points`(std::vector\<point_t\> 无 reserve)、`detect_signle_bar` 内 `upward`/`downward`(reserve100)、`rle_up`/`rle_down`(ild_get_rle 追加)。每次解码 ~数百次调用 × 6 ≈ **每帧上千次 heap alloc/free**。同 LC-5 的分配瓶颈模式但分布更广。

**优化（单点）**：将这 6 个缓冲提升为 `static thread_local`，每次调用 `clear()` 复用容量再 refill。**bit-exact by construction**：`tl::buffer::clear()`/`std::vector::clear()` 仅置 size=0 保留容量（buffer.h:705），refill 循环重建相同内容；所有消费者 size-bounded（`get_variance` range-for、`detect_signle_bar` 的 `line.size()`、`ild_get_rle(data(),size())`、`match_rle(rle.size())`）。关键：`ild_get_rle` 追加不 清零，故 `rle_*` 须在调用前 `clear()`。

**A/B（PC, bench_release /O2 /DNDEBUG, cache 413 图, 3 warmup + 7 runs）**：
| 指标 | baseline(HEAD) | opt(hoist) | Δ |
|---|---|---|---|
| bar_locating 阶段（profile 隔离） | 249.9µs | **91.4µs** | **-63.4%** |
| total mean-of-means | 4.3951ms | 4.1586ms | **-5.4%** |
| total median-image | 4.5735ms | 4.3458ms | **-5.0%** |

**正确性**：bit-exact——opt vs HEAD 逐图 diff = **0 行**（cache/cache1/cache2 全集），回归 cache=122/cache1=73/cache2=16 全等基线，0 新 FP。总降幅(~228µs) > bar_locating 阶段降幅(logged)，系释放的分配器/cache 压力惠及周围代码 + logged 阶段值含 fprintf 膨胀；clean total 的 -5% median 为权威端到端值。

**否决/搁置候选**：①消除 `points` 向量（index→pt 重算，移除 push_back）——bit-exact 但更险，留下一轮；②`detect_signle_bar` 冗余折叠（upward/downward 半拷贝+2RLE+get_variance）——改语义风险，搁置；③`detect_pattern_precisely` 内 `SCAN_STEP` 1.0→2.0（采样减半）——非 bit-exact，约束否决。

**Verdict：PASS**（bit-exact，0 回归 0 新 FP，bar_locating -63.4%，总 -5.0% median，每帧减上千次堆分配）。剩余瓶颈：interpolation 104µs / wave_sampling 114µs / pre_crop 97µs（均 <2.6%，逐项 bit-exact 天花板低）。

---

## vertical_locating 角度扫描直方图缓冲复用（2026-08-06）- LC-5

> 优化编号：LC-5 | 平台：x86_64 PC bench（/O2 /DNDEBUG），cache 413 图 | 前序：LC-4（gauss 收敛后转 #2 瓶颈）

**Profile（µs 阶段计时，聚合 cache 413 图）**：gauss 收敛后重新分解后段。gaussian_binarize 3129µs/图（~75%，收敛不动）；**vertical_locating 466µs/图（~11%，#2）**；bar_locating 263；interpolation 114；wave_sampling 115；pre_crop 87；sync_crop/deskew/clean_flat <12。vertical_locating 子分解：**rotate_and_detect 257.8µs（59%）> match(ild_bin_pattern_match) 133.2µs（30%）> scan(ild_vertical_scan) 44.5µs（10%）**。scan 的跨步列读取（cache-unfriendly）非主因（推翻初判）。

**瓶颈定位**：`rotate_and_detect` 以 0.316° 步长扫 ~28.8°→149.4°，**~381 次** `rotate_angle()` 调用；每次调用 `std::vector<int> buckets; buckets.resize(bucket_num)` ——**每帧 ~381 次 heap alloc/free**（bucket_num≈1.414·w/8+1≈90-115）。

**优化（单点）**：`BarLocator.cpp::rotate_angle()` 将直方图缓冲提升为 `static thread_local std::vector<int>`，每次 `assign(bucket_num,0)` 复用容量并清零。**bit-exact by construction**（清零的复用缓冲 ≡ 原每次 fresh resize 的 value-init 清零，后续代码不变）。消除 ~381 次/帧 malloc/free，减轻移动端分配器/GC 压力。

**A/B（PC, time cache 3 7）**：
| 指标 | baseline | opt(hoist) | Δ |
|---|---|---|---|
| rotate（profile 隔离） | 257.8µs | **231.3µs** | **-10.3%** |
| total mean | 4.3564ms | 4.3054ms | -1.2% |
| total median | 4.5833ms | 4.4068ms | -3.9% |

**正确性**：bit-exact（构造等价 + cache/cache1 per-image diff=0）。回归 cache1=73 / cache=122 / cache2=16（全等基线）。cache2 见 1 张 `00021_none` 间歇假解码（base→value, opt→NONE）= 既有 syncRow 类非确定性（opt-vs-opt 3 连跑 0 diff），非本次引入。

**否决候选**：①角度扫描粗-精两阶段（381→~113 次，rotate -70%/total ~-4%）——非 bit-exact（角度选择改变→可能改解码），且 ~4% 非"大幅"，约束不允许成功率换算，搁置；②cos/sin 表/递推——递推非 bit-exact，移位零收益；③standard_deviation 单遍——方差需 mean 先行，单遍须改浮点序（非 bit-exact）。**结论：vertical_locating bit-exact 天花板低（~1% total），rotate 本质是 381 次迭代扫描 + 不可压缩的 2-pass 方差/三角函数。** 真机（分配器更慢、cache 效应更大）增益预期 > PC 的 -10% rotate。

**Verdict：PASS**（bit-exact，0 回归 0 新 FP，rotate -10.3%，每帧 -381 alloc）。下一瓶颈候选：bar_locating 263µs / match 133µs / interpolation 114µs。

---

## 融合阈值真机 A/B 否定 - 回退两步基线（2026-08-06）- LC-4

> 优化编号：LC-4 | 平台：arm64-v8a 真机（Debug APK，-O3 经 CMake override）| 测试：live-scan ~70s/变体 | 前序：LC-3（融合默认待真机验证）

### 背景

LC-3 将融合阈值回填为默认实现并 ship， expressly 待真机 A/B 定夺：融合省去独立 blur 缓冲的 memset/写/读 + 独立阈值循环（3 趟全图访存），x86 持平（计算受限），ARM 疑 load-bound 或可获益。本阶段执行真机 A/B。

### 方法

- Debug APK（无 NDEBUG -> `ILD_LOGI` 活跃；解码器仍 -O3 经 `CMakeLists` `target_compile_options` override，计时代表优化码）。logcat tag = `isliline`。
- fused：默认构建（`ILD_FUSE_THRESH=ON`）。nofuse：`build.gradle` 加 `-DILD_FUSE_THRESH=OFF` -> `ILD_NO_FUSE` 两步基线。
- 读 `gauss_bin took Xus`（`GaussianBinarization.cpp` 自带 µs 计时器，包 blur_core + 阈值）。图尺寸恒定 746×746（421/433 帧均同），故 gauss_bin 耗时由尺寸决定、与内容无关--理论上不同帧可直接比均值。

### 数据

| 指标 | fused (n=421) | nofuse (n=433) |
|---|---|---|
| mean | 21495us | 18506us |
| median | 22438us | 18221us |
| std | 9881 | 11005 |
| min/max | 535 / 73005 | 601 / 61958 |

表面 fused 慢 16%。**此为假象**，两个混淆因素如下。

**混淆 1 - 热降频 ramp（主源）**：两变体连续扫描 70s 内 gauss_bin 均从 ~7ms 涨至 ~25-45ms（3-4×）。冷态地板几乎相同：

| | 冷态前 15 帧 | 末段热态 |
|---|---|---|
| fused | 7.0-7.9ms | 25-45ms |
| nofuse | 7.3-7.8ms | 23-47ms |

中位数差异完全由两次采样落在 ramp 的不同位置所致（设备热状态，非算法）。

**混淆 2 - 帧间裁剪尺寸变化**：decode image 虽恒 746×746，高斯实际处理 sync_crop 后 enlarged 子图，帧间尺寸不同。直方图多模态：

| 桶(us) | fused | nofuse |
|---|---|---|
| 0-1k | 8 | 30 |
| 1-3k | 2 | 8 |
| 3-7k | 9 | 42 |
| 7-12k | 51 | 36 |
| 12-20k | 104 | 120 |
| 20-30k | 182 | 141 |
| 30k+ | 65 | 56 |

nofuse 超快簇(0-7k=18.5%)远多于 fused(4.5%)，系两次扫到不同内容（小裁剪帧占比不同），非融合效果（815us 对 746² 高斯物理不可能，必为小裁剪帧）。

### 判定

若融合真省带宽带来 ARM 收益，fused 直方图应**整体左移**（快样本变多）。实际 fused **轻微右移**（20-30k 桶 182 vs 141），在热噪声 ±50% 背景下不构成"融合更慢"证据，但**明确排除"融合更快"**。冷态地板相同 + 无左移 = **ARM 真机无收益**，与 x86 持平一致。

解码率无回归：fused 78/421、nofuse 72/433（不同会话不可比；bit-exact 已于 LC-3 证 73/122/16，0 FP）。

### 结论与动作

**融合在 ARM 真机无收益，回退至 LC-2 干净两步基线。** 融合代码（fused V-pass 分支 + `ILD_NO_FUSE` 宏 + CMake option）为零设备收益增复杂度，移除。与 LC-2 收敛选择一致（LC-3 re-add 唯一目的即真机验证，现已否定）。

- `GaussianBinarization.cpp`：回退至 1eb025c 两步法实现（`ild_gaussian_blur_core` + 独立阈值循环）；**保留 `gauss_bin` µs 计时器**（1eb025c 已有，供后续 profiling）。
- `CMakeLists.txt`：移除 `ILD_FUSE_THRESH` option 与 `ILD_NO_FUSE` 定义块（保留 NEON 注释更新与 ILD_DEBUG 清理）。
- `build.gradle`：移除 A/B 临时加的 `-DILD_FUSE_THRESH=OFF`。

### 正确性验证：PASS

回退至 1eb025c = LC-2 收敛态（cache1 73 / cache 122，0 FP，bit-exact 于冻结 oracle）。无新逻辑引入。

---

## 高斯二值化融合阈值上真机验证（2026-08-06）- LC-3

> 优化编号：LC-3 | 平台：x86 SSE4.1 代理 + arm64-v8a NEON(待测) | 测试集：cache1(304)/cache(413)/cache2(459 真机 746×746)

### 背景

cache2 真机数据（459 帧，746×746）实测：gauss_bin=3782µs，占单帧 5.095ms 的 **74%**--gaussian 仍是主瓶颈（与 LC-2 收敛结论一致）。设备文件名耗时 38-51ms（PC 5ms 的 8-10×），ARM 侧绝对耗时巨大。解码率仅 3.5%(16/459)，但 PC≈设备(457/459 同意)，系采集质量而非解码器缺陷。

### 选定方案及理由

**回填融合阈值（LC-2 候选3）为默认实现，上真机验证。** LC-2 在 x86 代理下测得融合持平（计算受限），但 ARM 疑 load-bound（~0.95 vs 0.5 cyc/px），融合省去的 blur 缓冲写/读 + 独立阈值循环（3 趟全图访存）或可在设备获益。x86 零回归（bit-exact + 持平），故默认 ship 融合、由真机 A/B 定夺。

### 实现要点

- `GaussianBinarization.cpp`：`template<bool FuseThresh> ild_gaussian_blur_impl`，V pass 融合分支：
  - SSE4.1：`mask=~cmpgt(acc,px)`(px>=blur) -> `pshufb` 取每 lane 低字节 -> 存 4 字节 0xFF/0x00。用 `_mm_packs_epi32`(有符号饱和: -1->0xFF)，**禁用 `packus`**(无符号饱和: -1->0，全黑 bug)。
  - NEON：`vcge_u16(px16,blur)`(0xFFFF/0) -> `vqmovn_u16`(0xFF/0x00)。
  - scalar：`img>=b?255:0`。
- 默认 `ild_gaussian_binarization`=impl<true>（融合）；`#ifdef ILD_NO_FUSE`=两步法基线（impl<false> + 阈值循环）。
- 全图 memset 边界（融合 out=255 白边，blur=0）；无 ild_fill_border。
- `CMakeLists.txt`：`option(ILD_FUSE_THRESH ... ON)`，OFF 时定义 `ILD_NO_FUSE`，供 Android 设备 A/B。
- bench `build.cmd`：`nofuse` 目标重建（PC A/B）。

### A/B 测试结果

**bit-exact（fused 与 nofuse 均通过）**：

| 测试集 | fused | nofuse | baseline |
|---|---|---|---|
| cache1 | 73 | 73 | 73 |
| cache | 122 | 122 | 122 |
| cache2 | 16 | 16 | 16 |

FP=0（两变体解码结果与冻结 oracle 逐字节相同）。

**x86 计时（cache2，n=459）**：fused vs nofuse = -2.2% / +0.5%（2 样本），±2% 噪声底内 = **持平**（计算受限，与 LC-2 一致）。

### 正确性验证：**PASS**

- cache1 73/73、cache 122/122、cache2 16/16，两变体均逐字节相同，0 FP。
- NEON 融合路径经逐指令审查正确（vcge=≥、vqmovn(0xFFFF)=0xFF、与 bit-exact 验证的 SSE 路径同构）；x86 无 aarch64 工具链，运行时验证待真机。

### 下一步计划（设备 A/B）

1. 部署默认融合构建，真机测 cache2 类帧的 gaussian 阶段耗时 vs 当前两步法部署。
2. **先验解码率不变**（NEON 路径首次运行时验证）：若解码率下降->NEON bug->回退；若持平->读计时。
3. 若设备 gaussian 耗时下降->保留融合；若持平->回退（x86 已证零收益，ARM 亦无获益则无意义）。
4. CMake `-DILD_FUSE_THRESH=OFF` 可一键切回两步法基线对照。

---

## 高斯二值化瓶颈穷尽核查（2026-08-06）— 收敛

> 优化编号：LC-2 | 平台：x86 SSE4.1 代理（设备目标 arm64-v8a NEON）| 测试集：cache1(304)/cache(413) | 前序：LC-1 = 2× 垂直放大去除（2026-07-30）

### 瓶颈描述

`ild_gaussian_binarization` 是解码绝对主热点。µs 级计时（profile 构建，n=304，cache1）：

| 阶段 | 均值(µs) | 占比 |
|---|---|---|
| **gauss_bin（H+V blur + 阈值）** | **2292** | **71.4%** |
| vertical_locating | 3 | 0.1% |
| 其余 8 阶段（sync_crop/deskew/interpolation/pre_crop/clean_flat/wave_sampling/bar_locating/curve） | 各 <3（子毫秒） | 合计 ~28% |
| **单帧总解码** | **3207** | 100% |

blur 为**计算受限**：x86 路径 `mullo_epi32`（4 lane/iter，~1/cyc），NEON 路径 `vmlal_s16`（8 px/iter）。融合阈值循环省下的访存被 V pass 计算开销抵消。

### 候选方案对比

| # | 方案 | 复杂度 | 预期 | A/B 结果 | 风险 |
|---|---|---|---|---|---|
| 1 | Box blur（单次，R=7 均值） | 低 | 2-3× | **0 解码**（cache1） | 防伪纹理需中心加权高斯做自适应阈值；box 滤波器形状不符，纹理残留致条边缘错位 |
| 2 | N-box（3-box R=3≈σ3.5） | 低 | 2-3× | **4 解码 + 1 FP** | 仍偏离精确高斯，阈值边界漂移 |
| 3 | V pass 融合阈值（`packs` 比较，省 blur 缓冲+阈值循环） | 中 | 5-10% | **bit-exact，+0.0%**（stage 2326→2327µs） | x86 计算受限，省下的阈值循环(≈9%)被融合 compare 抵消 |
| 4 | border-only memset（省内点冗余写） | 低 | 1-2% | **bit-exact，+1.5% 回归** | 2956 次 7 字节小 memset 的 per-call 开销 > 省下的流式写 |
| 5 | s16 SSE 8px/iter（对齐 NEON） | 高 | 2× | **不适用** | SSE 无 `vmlal_s16` 等价：`pmullw`(s16×s16→s16) 溢出(sum≤510×k≤29965=15.3M>32767)；`pmaddwd` 配对；`pmuldq` 慢 |
| 6 | 核截断（R<7，舍弃衰减尾部） | 中 | 1.3× | **未实施（高风险）** | 核尺寸 15 是 load-bearing，截断大概率如 box 破坏纹理去除 |

### 选定方案及理由

**收敛——无可达“timing 改善”的 bit-exact 方案。** 候选 1/2 破坏正确性；3/4 无收益或回退；5 在 x86 不可行；6 风险等同于 1。现有 SSE4.1(4px s32)/NEON(8px s16) 已是该指令集下可分离高斯的近最优向量化。**还原为干净两步法**（全图 memset、无融合、无 border-memset）——即 A/B 中测得最快变体。

### 实现要点

- `GaussianBinarization.cpp` 还原两步法：`ild_gaussian_blur_core`(H pass img→g_tmp，V pass g_tmp→out) + 独立阈值循环 `img>=blur?255:0`。
- 保留：核缓存（`ild_gauss_kernel_cache`）、`g_tmp`/`g_blur` scratch 复用（免每帧 malloc）、SSE4.1/NEON/scalar 三路径、V pass 读 tmp 列 `x-border` 的固化偏移。
- 移除：`template<bool FuseThresh>` 融合模板、`ild_fill_border`、`ILD_NO_FUSE` A/B 分支。
- MSVC 可移植：`kSimd` 标签提取为 `static const char*`（`#if` 不能出现在 `ILD_LOGD` 宏实参内，MSVC C2121/C2059）。
- `gauss_bin took %lldus` µs 计时（ILD_LOGI，Release 下 NDEBUG no-op 零开销）。
- `build.cmd` 清理：移除 `nofuse`/`nofusep` 目标。

### A/B 测试结果（cache1，n=304，同硬件）

| 变体 | 解码 | FP | gauss stage(µs) | 总解码(ms) | 判定 |
|---|---|---|---|---|---|
| **干净两步法（baseline/ship）** | **73** | **0** | **2292** | **3.207** | — |
| Box R=7 | 0 | 0 | — | — | ❌ 正确性 |
| N-box R=3 | 4 | 1 | — | — | ❌ 正确性 |
| 融合阈值 | 73 | 0 | 2327 | 3.21 | ≈ 持平 |
| border-memset | 73 | 0 | — | 3.26 | ❌ 回归 +1.5% |

（s16-SSE 不可行；核截断未实施。噪声底 ~2%，<2% 视为持平。）

### 正确性验证：**PASS**

- cache1：`dump` 输出与 `baseline_cache1.txt` **逐字节相同**（73 解码，0 diff）。
- cache：`dump` 输出与 `baseline_cache.txt` **逐字节相同**（122 解码，0 diff）。
- FP=0（无新增解码、无错码）。

### 下一步计划

1. **子毫秒阶段 µs 重剖**：非高斯 28%（~915µs）碎片化于 8 个子毫秒阶段，ms 计时器取整为 0；改 µs 计时器定位最大 #2 瓶颈（预估单阶段 100-200µs，可挖 3-6%）。
2. **设备侧 ARM profiling**：x86 代理下融合(候选3)持平，但 ARM 疑为 load-bound（~0.95 vs 0.5 cyc/px），融合的访存削减或可获益——需真机测量验证后决定是否回填融合。
3. **sync_crop 鲁棒性**：缩小 blur 工作集（更紧的裁剪框）以减少 gauss 绝对耗时，低风险。

---

## 优化成果（采纳）

| 指标 | 优化前 | 优化后 | 降幅 |
|---|---|---|---|
| native 单帧解码耗时 | **128ms** (均值) | **82ms** | **-36%** |
| Gaussian 二值化耗时 | 83ms | 55ms | -34% |
| 定位点数 (pt_vec) | ~44 | 44 | 不变 |
| 解码命中率（定位/BCH） | 保持 | 保持 | — |

**核心改动：去掉 2× 垂直放大 (1× 路径)**，涉及 3 个文件：

### `ISLILineDecoder.cpp` — `decode_landscape()`
- **删除** `interpolation_image()`（2× 垂直放大函数及其调用），`bin_img` 直接在 `src`（1× 预裁剪图）上分配。
- `decode_from_binary()` 辅助函数（重构提取）中 `feay` 不再 `/2`（y 已是原始分辨率）。
- `span < 64` 横向阈值不动（x 向未放大）。

### `BSPatternMatch.cpp` — `ild_bin_pattern_match()`
- 垂直向 RLE 尺寸/容差阈值按 **0.5 同比缩放**（放大只加倍 y，故仅 y 向阈值需缩放）：

| 原值 (2×) | 缩放后 (1×) |
|---|---|
| `(2, 4, 12, 30)` | `(1, 2, 6, 15)` |
| `(4, 8, 30, 90)` | `(2, 4, 15, 45)` |
| `(12, 8, 90, 9999)` | `(6, 4, 45, 9999)` |

- x 向不受影响（`SCAN_LINE_DIS`、`BUCKET_SIZE`、`ERROR_TOLERANCE` 等不动）。
- `avg_width` 运行时按 1× 实测自动缩放。

### 精度权衡（已知，监控）
BCH 纠错位数分布上移约 1 位（`err_num ≥ 4` 占比 13% → 24%）。BCH 接受 ≤5 错，命中率大体守住，但垂直精度下降消耗了纠错余量。**edge case 帧（err_num=5）距失败只差一位。**

---

## 失败/回退的实验

| 实验 | 描述 | 结果 | 原因 |
|---|---|---|---|
| **Otsu 优先 + Gaussian 回退** (Tier 1b) | 先试 Otsu 全局二值化(~数ms)，端到端失败再用 Gaussian 重跑全程 | `run1.log`：Otsu 命中率仅 **4%**（3/81），96% 回退帧双倍开销 → 可解码帧 128→211ms。**回退**。 | 防伪纹理码需局部自适应阈值；Otsu 定位 OK 但条边缘精度不足 → 63/78 帧 BCH 解码错。 |
| **NEON SIMD 高斯模糊 + buffer 复用** (Tier 1c) | ARM Neon intrinsically 向量化可分离高斯模糊，静态 buffer 复用省 malloc/free | `run3.log`：二值化 55→**2278ms**（50× 退化）、解码率→0。`run4.log`（禁用 NEON）仍 868ms → 问题在 buffer/函数重构而非 NEON。**回退整个 GaussianBinarization.cpp 至原始**。 | 重构中 buffer 管理或函数提取有 bug，无法本地调试定位 → 回退后恢复 run2 水平。 |

---

## 文件变更清单（最终采纳）

| 文件 | 变更 |
|---|---|
| `linecode/IldLog.h` | **新增** — 统一日志接口（isliline 前缀，5 级，运行时开关） |
| `linecode/IldLog.cpp` | **新增** — 跨平台日志实现 |
| `linecode/Common.h` | **修改** — 引入 IldLog.h，ILDLOG 不再依赖 ILD_DEBUG |
| `linecode/Common.cpp` | **修改** — ild_printf 转发到新日志 |
| `linecode/ISLILineDecoder.cpp` | **修改** — 删 interpolation_image；1× 路径 + 日志插桩；decode_from_binary 重构 |
| `linecode/BarLocator.cpp` | **修改** — 各阶段插桩日志 |
| `linecode/BSPatternMatch.cpp` | **修改** — RLE 阈值 0.5 缩放 + 插桩 |
| `linecode/Wave2Bits.cpp` | **修改** — 插桩（VERBOSE 避免刷屏） |
| `linecode/BchHelper.cpp` | **修改** — 插桩（激活 BCH 诊断日志） |
| `linecode/GaussianBinarization.cpp` | **修改** — 插桩（确认 Gaussian 路径） |
| `CMakeLists.txt` | **修改** — 加入 IldLog.cpp |
| `LineCodeDecoderBridge.cpp` | **修改** — 新增 nativeSetLogLevel JNI |
| `ISLILineDecoderHandler.kt` | **修改** — 新增 setLogLevel(Int) |

---

## 日志基础设施

- **前缀/tag**：`isliline`。Android logcat 过滤：`adb logcat -s isliline`
- **级别**：0=OFF 1=ERROR 2=WARN 3=INFO 4=**DEBUG(默认)** 5=VERBOSE
- **运行时控制**：`ISLILineDecoderHandler.setLogLevel(level)`
- **热路径用 VERBOSE**（逐列匹配/逐组合 BCH），默认不刷屏
- `binarize(gaussian) took=Xms` (INFO) — 量化二值化耗时

---

## 剩余优化方向（未做）

| 优先级 | 方案 | 预期收益 | 风险/备注 |
|---|---|---|---|
| 高 | NEON 高斯模糊（逐像素对拍验证后重做） | 二值化再 2-4× | 需设备端调试 |
| 中 | 同步组合搜索排序早退 + 步长 2px locate | miss 帧减 10-20ms | 低风险 |
| 中 | `pre_crop_vertical` 输入已小时跳过 | 省行投影遍历 | 低风险 |
| 低 | Otsu 干净码快路径（仅当数据集含非纹理码时启用） | 干净帧 ~1ms 二值化 | 需数据集判定 |
