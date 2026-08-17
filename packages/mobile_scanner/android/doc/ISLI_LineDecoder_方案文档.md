# ISLI 行码（LineCode）解码方案文档

> 版本：2026-07-31 | 目标平台：Android arm64-v8a | 单帧 native 解码 ~45ms

## 1. 概述

### 1.1 什么是 ISLI 行码

ISLI 行码是一种 **水平一维条形码**，包含两条平行的数据行（每行 71 bit），共携带 **112 bit 有效数据**。数据经过 BCH(127, 80, t=7) 纠错编码后，交织排列到 **142 bit 的 raw 流**中——

- 8 个数据块 × 14 bit = **112 数据位**
- 10 个同步码 × 3 bit = **30 同步位**
- 合计 142 bit，分成两行各 71 bit

同步码位模式：前 4 个同步码为 NORMAL（101），第 5/6 为 INVERTED（010），7-9 为 NORMAL，第 10 为 INVERTED。解码端通过定位这 10 个同步标记来恢复数据帧编排。

### 1.2 解码流水线概览

```
相机帧（灰度图，单通道 8bpp）
  │
  ├─ 亮度门控（avg < 20 拒绝）
  ├─ decode_clean_flat 快路径（门控：连续 8 次 miss 跳过，每 30 帧重试）
  ├─ pre_crop_vertical（倾斜估计 + 行投影 + 双暗带检测）
  ├─ deskew（|tiltD| ≥ 6 时全图双线性剪切去倾斜）
  ├─ zero-copy view crop（免拷贝的 TImage 视图裁剪）
  ├─ sync-template crop（S1=101 模板匹配两数据行，5 重校验紧裁剪）
  ├─ interpolation_image 2× 垂直放大（NEON: vrhaddq_u8）
  ├─ gaussian_binarization 自适应二值化（NEON: vmlal_s16 + kernel_s16）
  └─ decode_from_binary
       ├─ vertical_locating（逐列扫描 + RLE 模式匹配 + 旋转角检测）
       ├─ 曲线拟合 + 特征点提取
       ├─ bar_locating（单条定位，沿曲线垂向扫描找两条数据行）
       ├─ 曲线采样 + 低通滤波 = 波形
       ├─ decode_waves（112 bit 路径：峰值/谷值找同步位 → 波形转 bit → BCH 纠错）
       ├─ decode_waves2（64 bit 路径：备用）
       └─ 反色兜底（亮度 > 240 时触发）
```

---

## 2. 各阶段详解

### 2.1 亮度门控

**文件**: `ISLILineDecoder.cpp::isli_line_decoder_do_image_decode`

- 对整幅输入灰度图计算**像素均值**（按每 4 像素累加，避免 int 溢出）。
- 若 `avg < ILD_MIN_BRIGHTNESS（20）`，判定为过暗/模糊图，直接返回失败（`is_blur=1`）。

### 2.2 decode_clean_flat（干净码快路径）

**文件**: `ISLILineDecoder.cpp::decode_clean_flat`

- **原理**：对**无防伪纹理**的干净渲染码，不需要反防伪定位和二值化，直接按几何坐标均匀采样。
- **实现**：假设两条数据行分别位于图像高度 `H/6` 和 `5H/6` 处，每行均匀取 71 个采样点。对每个采样点取其 ±1 行邻域的 3 像素，按多数投票定 0/1。
- **门控**（`decode_landscape`）：因防伪纹理码命中率 0%，连续 miss ≥ 8 帧后**跳过**该路径；每 30 帧重试一次，防止漏掉偶然出现的干净码。静态 streak 计数。
- **常量**: `H/6`, `5H/6`（默认采样行位置）；阈值 128（灰度中值）。

### 2.3 pre_crop_vertical（倾斜自适应预裁剪）

**文件**: `ISLILineDecoder.cpp::pre_crop_vertical`

- **倾斜估计**（新增）：取图像顶部/底部各 10 行（`nTop`）做水平投影压缩为剖面（`topProfile`, `botProfile`，各 W/4 点），互相关滑窗 `±W/20` 找最佳偏移 `tiltD`（单位：像素 × 4）。
- **倾斜补偿行投影**：若 `|tiltD| < 2`，直接按行取均值；否则对每行按 `ox = y × tiltD / H` 水平偏移后双线性采样再取均值。
- **双暗带检测**：行投影中找到最低均值点 `ya`（最深暗带），以 `accept = bg - 0.15×(bg-rmin)` 为界向上/下扩展得到第一条带 `[b0, b1]`；排除该带后在剩余区域找第二暗带 `[d0, d1]`。两带合并 + margin 得到 `cropY0, cropH`。
- **输出**: `cropY0`, `cropH`（裁剪区域）, `tiltD`（倾斜量，像素 × 4）。

### 2.4 deskew（去倾斜）

**文件**: `ISLILineDecoder.cpp::decode_landscape`

- **触发条件**: `|tiltD| ≥ 6`。
- **算法**: 分配与原图同尺寸的 `deskewed` 临时图，对每行 `y` 按 `ox = -y × tiltD / H` 做水平偏移，以浮点双线性插值（`v×(1-frac) + next_v×frac`）填充。边界外像素填 255（白色背景）。
- **重裁剪**: 对 deskewed 结果重新调用 `pre_crop_vertical` 更新 `cropY0, cropH`。
- **开销**: 仅在倾斜帧触发（典型会话 <5%），O(W×H) 双线性。当前约 0.5ms（倾斜帧）或 0.1ms（无倾斜时仅检查条件）。

### 2.5 zero-copy view crop

**文件**: `ISLILineDecoder.cpp::decode_landscape`

- **免拷贝裁剪**: 不分配新 buffer、不 memcpy。直接用 `TImage(pixel + cropY0*bpl, w, cropH, bpl)` 创建**视图**——将裁剪后的 ROI 映射到原图 buffer 中的对应区域。
- **优势**: 零内存分配、零拷贝，`src` 指针指向 workImg 内部。

### 2.6 sync-template crop（同步模板紧裁剪）

**文件**: `ISLILineDecoder.cpp::decode_landscape`

- **触发**: `src` 是视图（上一阶段裁剪成功）且 `src->h > 50`。
- **前置条件**: `bw2 = w/71` 在 `[8.0, 30.0]` 范围内（条码单元宽度合理）。
- **算法**:
  1. 对每一行 `y`，在列 `0, bw, 2bw` 三个位置各取 `2hw+1` 像素的均值（模拟 S1=101 模板的深-浅-深响应），计算同步得分 `sc = (128 - v0) + (v1 - 128) + (128 - v2)`。记录全局最大值 `syncMax`。
  2. **校验 1**: `syncMax ≥ 100`（绝对阈值）。
  3. **校验 2**: `syncMax ≥ 3 × median`（中位数外异常值）。
  4. **校验 3**: 在所有 `sc ≥ 0.75×syncMax` 的行中，找最佳行对 `(bA, bB)`，要求行间距 `1.3-2.8×bw2`（两条数据行的合理间距）。
  5. **校验 4**: 行对存在且间距合理。
  6. **校验 5**: 裁剪后高度 ≥ `0.2×ch`（有意义缩减），≥ 60px。
- **输出**: 新的 `src` 视图（紧贴两数据行的窄裁剪区域）。
- **开销**: O(H × 3 × (2hw+1)) ≈ O(H×18)。排序 O(H log H)、行对搜索 O(H×maxSep)。合计 ~1ms（触发时，round-trip 包含条件判断计入 `stage(sync_crop)` 约 0ms——大多数帧不触发该路径的内部逻辑）。

### 2.7 interpolation_image（2× 垂直放大）

**文件**: `ISLILineDecoder.cpp::interpolation_image`

- **目的**: 为后续二值化/定位/采样提供更高的垂直分辨率（2× 高度），提升条码边缘精度。
- **算法**: **行主序** + **NEON 加速**（arm64-v8a）。
  - 第 y 行输入 → 偶行（2y）= 拷贝（`memcpy`）
  - 奇行（2y+1）= 第 y 行与第 y+1 行的均值（`vrhaddq_u8` = (a+b+1)>>1，16 像素/迭代）
  - 最后一行输入 → 最后两行输出均 = 拷贝
- **非 arm64 回退**: 标量循环 `(r0+r1+1)>>1` + `memcpy`。
- **开销**: ~0.4ms（NEON）。

### 2.8 gaussian_binarization（自适应二值化）

**文件**: `GaussianBinarization.cpp`

- **算法**: 
  1. **高斯模糊**（`ild_gaussian_blur`）：对输入灰度图做 2-pass 可分离高斯模糊（核 15，对称优化为 8 次乘法/像素），得到局部均值图 `blur`。
  2. **自适应阈值**：逐像素比较 `img[x] >= blur[x] ? 255 : 0`，输出二值图。
- **SIMD 加速**（自动选择）:
  - **arm64-v8a（NEON）**: 8 像素/迭代，`vmovl_u8`（u8→u16）+ `vmlal_s16`（s16×s16→s32 累加）+ `vshrq_n_s32`（shr18）+ `vqmovun_s32`/`vqmovn_u16`（饱和缩窄）。内核值 ~2^20 溢出 s16，故 `kernel>>5` 压缩，移位补偿 `23-5=18`，精度损失 <0.02 LSB。
  - **x86_64（SSE4.1）**: 4 像素/迭代，`_mm_cvtepu8_epi32` + `_mm_mullo_epi32` + `_mm_packus`。
  - **其他平台**: 标量回退（`long long` 累加）。
- **static scratch buffer**: `tmp`（高斯模糊内部中转）和 `blur`（局部阈值均值图）使用 static grow-only buffer 复用，避免每帧 `malloc/free`。
- **阈值比较**: 平坦索引 `pixel[i]`（非 `at(x,y)`，去每像素 assert + 乘法）。
- **常量**: `ILD_GAUSSIAN_KERNEL = 15`（核尺寸），`border = 7`。
- **开销**: ~21ms（NEON，2× 放大图像）。

### 2.9 vertical_locating（垂直定位）

**文件**: `BarLocator.cpp::ild_do_vertical_locating`

- **目的**: 在二值图中逐列扫描，找到条形码图案的**垂直位置**特征点，用于后续多项式曲线拟合。
- **逐列扫描**:
  - 从中心列 `w/2` 向两侧交替扫描，步长 `SCAN_LINE_DIS = 8`。
  - 每列: `ild_vertical_scan`（拷贝该列像素）→ `ild_bin_pattern_match`（RLE 编码 + 3 档模式匹配）。
  - **早期退出**: 采集到 `LOCATING_ENOUGH = 64` 个模式点后停止扫描。
- **RLE 模式匹配** (`ild_bin_pattern_match`):
  - 对垂直列做游程编码（RLE），得到黑白交替段长。
  - 3 档尺寸阈值匹配（匹配 "黑白白黑黑……" 等反防伪纹理图案）:

    | 档 | th1 | th2 | min | max | 用途 |
    |---|---|---|---|---|---|
    | 小 | 2 | 4 | 12 | 30 | 近距离（大尺寸）条码 |
    | 中 | 4 | 8 | 30 | 90 | 中距离条码 |
    | 大 | 12 | 8 | 90 | 9999 | 远距离（小尺寸）条码 |

  - 每个匹配输出一个 `point_t {x, y, width, type}`（x=列坐标，y=垂直位置，width=模式段长和）。
- **旋转角检测** (`rotate_and_detect`):
  - 对采集到的所有模式点做角度扫掠 `0.16π` ~ `0.83π`（步长 ~0.316°），对每个角度将点投影到桶中，计算标准差——**标准差最大**的角度对应条码的倾斜角。
  - 过滤出该角度的主桶点，求质心作为定位中心 `center`。
- **常量**: `SCAN_LINE_DIS = 8`，`LOCATING_ENOUGH = 64`，`BUCKET_SIZE = 8`。
- **开销**: ~8ms（2× 放大图，扫描 300+ 列 × 700+ 像素）。

### 2.10 曲线拟合 + 特征点

**文件**: `ISLILineDecoder.cpp::decode_from_binary`

- `convert_coord_and_sort`: 将定位点按 x 排序，提取 `px[], py[]` 数组。
- `point_distance`: 计算首末点距离 `span`。若 `span < 64` 拒绝（条码太短）。
- `get_avg_width`: 计算所有模式点的平均宽度 `avg_width`（后续 `bar_locating` 参数）。
- `ild_fit_curve`: 三次多项式拟合 y = c₃x³ + c₂x² + c₁x + c₀，得到条码数据行的**曲线方程**。
- 特征点: `feax[0,1] = px[first,last]`, `feay[0,1] = py[first,last]`（在 2× 放大坐标中，因此无 `/2` 修正——放大图坐标直接作为特征点输出）。

### 2.11 bar_locating（单条定位）

**文件**: `BarLocator.cpp::ild_locate_single_bar`

- **目的**: 沿拟合曲线在**垂直方向**（曲线的法线）上精确定位两条数据行的条边缘。
- **算法**:
  1. **方差基准**: 在 `center.x` 附近取 `VARIANCE_SAMPLE = 10` 个采样点，沿曲线法线扫 `[-width, +width]`（`width = avg_width × 0.8`），计算亮度方差均值 `avg_bar_var`（作为后续条检测的亮度变化门控）。
  2. **左/右扫描**: 从 `center.x` 向两侧步进 `SCAN_SINGLE_STEP = 2`，每步先 `trace_curve`（求曲线坐标 + 法线方向），再 `detect_pattern_precisely`（沿法线扫 `[-width, +width]` 得到一条灰度线，RLE 编码后检测两条数据行的条边缘位置）。若连续 `ERROR_TOLERANCE = 10` 步未找到条边缘，停止该方向扫描。
- **输出**: `bar1_vec`, `bar2_vec`（两条数据行的条边缘点集合，各数百个点）。若任一行点数 < 10 则拒绝。
- **常量**: `SCAN_SINGLE_STEP = 2`, `ERROR_TOLERANCE = 10`, `VARIANCE_SAMPLE = 10`, `SCAN_STEP = 1.0`（法线方向扫 step）。
- **开销**: ~3ms。

### 2.12 曲线采样 + 波形提取

**文件**: `ISLILineDecoder.cpp::fit_and_sample_one_curve / _curve2`, `CurveSampler.cpp`

- **1112 路径**: 将曲线均匀分割为 71 个 span（`SPAN_NUM = 71`），每 span 均匀取 9 个采样点（`SAPMLES_PER_SPAN = 9`），沿 span 端点做双线性采样（含十字邻域去空心图案），得到 639 点灰度波形。
- **低通滤波**: FIR 17 抽头低通（0-1Hz 通带，>2Hz 截止），滤除高频噪声。
- **64 路径**（`fit_and_sample_one_curve2`）: 根据条码宽度动态决定 span 数量 `span_num = x_len × 6 / width`，采样和滤波同上。用于 64 bit 短链解码。
- **开销**: ~1ms（两行各一遍 639 点采样 + FIR）。

### 2.13 decode_waves（波形解码）

**文件**: `ISLILineDecoder.cpp::decode_waves / decode_waves2`, `Wave2Bits.cpp`

**112 bit 路径**:
1. **峰值/谷值检测** (`ild_find_peak_valley`): 滑动窗口（d=5, t=2）找局部极值，对齐中心。
2. **同步位组合搜索** (`get_sync_combinations`): 两行波形各找峰值和谷值，两两配对（距离<9），筛选出不在头尾（距两端>27）的候选同步位。从候选中选 3 个同步位，排列组合得到所有可能的同步位三元组（上限约 300 组）。
3. **首尾裁剪** (`ild_trim_head_tail`): 根据同步位在首/末的极性（peak=同步在左，valley=同步在右）裁剪波形头尾。
4. **波形→bit** (`ild_wave2bits112`): 对于每组候选同步位三元组，以同步位为界分段，每段均匀采样 14 bit（阈值线性插值），得到 112 bit。
5. **BCH 纠错** (`ild_bits_decode2`): compact→decode_bch（t=7，接受 ≤5 错）→再编码校验→bits→十进制串。若为全零串则拒绝。最大尝试 300 组。

**64 bit 路径** (`decode_waves2`): 同理，同步位二元组，每段 16 bit，共 64 bit。BCH(63,39,t=4) 接受 ≤1 错。最大尝试 150 组。

### 2.14 反色兜底

**文件**: `ISLILineDecoder.cpp::isli_line_decoder_do_image_decode`

- 若首次解码失败且 `brightness > 240`（极亮图，可能是白底黑码的反色场景），对整图逐像素取反（`255 - pixel`）后重跑完整 `decode_landscape`。

---

## 3. 性能特征

### 3.1 单帧耗时分解（arm64, 1306×374 典型输入）

| 阶段 | 耗时 | 占比 | 加速 |
|---|---|---|---|
| clean_flat | 0ms | 0% | 门控（仅 3% 帧执行） |
| pre_crop_vertical | 0.5ms | 1% | |
| deskew | 0.1ms | <1% | 仅倾斜帧触发 |
| sync_crop | 0ms | 0% | |
| interpolation_image | 0.4ms | 1% | NEON vrhaddq_u8 |
| gaussian_binarization | 21ms | 47% | NEON vmlal_s16（~7× vs 标量） |
| vertical_locating | 8ms | 18% | SCAN_LINE_DIS=8 + 早退 |
| bar_locating | 3ms | 7% | SCAN_SINGLE_STEP=2 |
| wave_sampling | 0.6ms | 1% | |
| residual（JNI/alloc/brightness） | ~11ms | 25% | 固定开销 |
| **合计** | **~45ms** | 100% | |

### 3.2 优化历程

| 里程碑 | native | 关键变更 |
|---|---|---|
| 原始 | 128ms | 2× 标量二值化（bch NULL 告警） |
| +NEON 二值化 | 74ms | GaussianBinarization NEON 8px/iter（~7×） |
| +门控+计时 | 55ms | clean_flat 门控 + NEON 放大 + 编排层埋点 |
| +locate/bar | **45ms** | SCAN_LINE_DIS 8 + SCAN_SINGLE_STEP 2 + 早退 |

---

## 4. 日志系统

### 4.1 使用

- **过滤**: `adb logcat -s isliline`
- **格式**: `isliline: [L] <message>` （L=E/W/I/D，对应 ERROR/WARN/INFO/DEBUG）
- **级别**: 0=OFF, 1=ERROR, 2=WARN, 3=**INFO（默认）**, 4=DEBUG
- **运行时控制**: `ISLILineDecoderHandler.setLogLevel(level)`

### 4.2 默认 INFO 输出（每帧 ~8 行）

```
[I] decode image 1306x374 bpl=1306
[I] stage(clean_flat) took 0ms
[I] stage(pre_crop) took 0ms
[I] stage(gaussian_binarize) took 21ms
[I] stage(vertical_locating) took 8ms
[I] stage(bar_locating) took 3ms
[I] stage(wave_sampling) took 0ms
[I] decode OK via GAUSSIAN code=0000000026614400103
```

### 4.3 DEBUG（`setLogLevel(4)`）追加

- `pt_vec` 数量、`avg_width`、`span`、曲线系数
- `peak/valley` 计数、同步组合数
- BCH `err_num` 及错误位置
- 逐列匹配命中数（`bin_pattern_match`）

### 4.4 源码

- **头文件**: `linecode/IldLog.h`（header-only，Android `__android_log_print`，其他 `fprintf(stderr)`）
- **桥接**: `LineCodeDecoderBridge.cpp::nativeSetLogLevel`（JNI）
- **Kotlin**: `ISLILineDecoderHandler.setLogLevel(level)`

### 4.5 生产环境

默认 INFO 级别每帧 ~8 行日志。若需静默，`setLogLevel(0)` 或编译时修改 `ild_log_level_ref()` 的默认值。日志调用（包括不输出的 ILD_LOGD）仅做 cheap 整型比较（`level >= threshold`），不格式化、不调 logcat，开销 ~0。

---

## 5. 关键常量与调优

| 常量 | 值 | 位置 | 影响 |
|---|---|---|---|
| `SCAN_LINE_DIS` | 8 | `BarLocator.cpp` | 垂直定位列间距。减小→更多列→更多定位点但更慢；增大→更快但可能漏小图案。条码单元 ~20px，8px 已够。 |
| `SCAN_SINGLE_STEP` | 2 | `BarLocator.cpp` | 单条定位沿曲线步长。减小→更密 bar 点→更多数据但更慢；增大→更快但条边缘采样变稀。 |
| `LOCATING_ENOUGH` | 64 | `BarLocator.cpp` | 逐列扫描点采集阈值。达到后提前停止扫描。`rotate_and_detect` 实际只需 ~30 点，64 是安全余量。 |
| `ILD_GAUSSIAN_KERNEL` | 15 | `Common.h` | 高斯模糊核尺寸（=2×border+1）。减小→更快但局部阈值范围变小→二值化噪声增大。 |
| `ILD_GAUSSIAN_KERNEL / 2` | 7 (border) | `GaussianBinarization.cpp` | 图像边缘被忽略的列/行数。 |
| `ERROR_TOLERANCE` | 10 | `BarLocator.cpp` | `bar_locating` 连续未检测到条的步数上限。超过后停止该方向扫描。 |
| `clean_flat` streak | 8 | `ISLILineDecoder.cpp` | 连续 miss 多少次后跳过快路径。每 30 帧重试。 |
| RLE 小档 | (2,4,12,30) | `BSPatternMatch.cpp` | 垂直定位小尺寸模式匹配阈值（th1,th2,min,max） |
| RLE 中档 | (4,8,30,90) | `BSPatternMatch.cpp` | 中尺寸 |
| RLE 大档 | (12,8,90,9999) | `BSPatternMatch.cpp` | 大尺寸 |
| BCH t | 7 | `LineCodeSpec.h` | BCH 纠错能力。接受 ≤5 错（`ild_bits_decode2`），留 t=6,7 为余量。 |

---

## 6. SIMD 加速（arm64-v8a）

| 阶段 | 指令集 | 算法 |
|---|---|---|
| gaussian_binarization | NEON | 8px/iter 可分离高斯模糊（vmovl_u8 + vmlal_s16 + vshrq_n_s32 + vqmovun） |
| interpolation_image | NEON | 16px/iter 行均值（vrhaddq_u8） |
| deskew（预留） | — | 可 NEON 化双线性插值（未实现） |
| comparison loop | 编译器自动向量化 | 平坦索引 `pixel[i]` 利于 clang -O3 自动向量化 |

> **x86_64（PC 调试）**: GaussianBinarization 使用 SSE4.1 4px/iter（`_mm_mullo_epi32`），interpolation 使用标量。

---

## 7. 文件结构

| 文件 | 内容 |
|---|---|
| `linecode/ISLILineDecoder.h` | 公开 API: `IMAGE`, `TRect`, `isli_line_decoder_*` |
| `linecode/ISLILineDecoder.cpp` | 主解码流水线: `decode_landscape`, `decode_from_binary`, `decode_waves`, `pre_crop_vertical`, `interpolation_image`, 等 |
| `linecode/GaussianBinarization.cpp` | 高斯模糊 + 自适应二值化 + 大津法（NEON/SSE/标量） |
| `linecode/BarLocator.cpp` | 垂直定位（`ild_do_vertical_locating`）+ 单条定位（`ild_locate_single_bar`） |
| `linecode/BSPatternMatch.cpp` | RLE 模式匹配（`ild_bin_pattern_match`）+ 二叉树模式匹配 |
| `linecode/Wave2Bits.cpp` | 波形→bit（`ild_wave2bits112/64`）+ 峰值/谷值检测（`ild_find_peak_valley`） |
| `linecode/BchHelper.cpp` | BCH 紧凑/纠错/解码（`ild_bits_decode2`, `ild_bits_decode_short_chain`） |
| `linecode/CurveFit.cpp` | 三次多项式拟合 + 坐标归一化（`ild_fit_curve`） |
| `linecode/CurveSampler.cpp` | 曲线分割成 span + 沿曲线采样（`ild_sample_one_curve`） |
| `linecode/Filter.cpp` | FIR 低通滤波（17 抽头） |
| `linecode/LineCodeSpec.h` | 编解码共享常量 + 解交织 LUT |
| `linecode/bch.cpp/h` | BCH 编解码库 |
| `linecode/TImage.cpp/h` | 灰度图数据结构（pixel, w, h, bpl, allocate, view） |
| `linecode/Common.h` | 共享常量（`ILD_BIT_COUNT`, `ILD_GAUSSIAN_KERNEL` 等）+ IldLog.h 引入 |
| `linecode/IldLog.h` | 统一日志（isliline tag, 5 级, 运行时门控, Android logcat） |
| `LineCodeDecoderBridge.cpp` | JNI 桥接（`nativeInit/Uninit/Decode/SetLogLevel`） |
| `ISLILineDecoderHandler.kt` | Kotlin 封装（`decode`, `setLogLevel`） |
| `CMakeLists.txt` | NDK 构建配置（-O3, log-lib, 源文件列表） |

> **`linecode_20260730/`**, **`linecode_2026073001/`**: 历史备份目录，不参与编译。

---

## 8. 已知限制与改进方向

### 8.1 当前限制

- **防伪纹理码专用**: 本方案聚焦反防伪纹理条码（自适应二值化 + 反防伪模式匹配）。对于干净的渲染码，`decode_clean_flat`（门控后极少触发）即可高速解码，但主流水线对此场景有过度计算。
- **JNI 开销**: `buildResultMap` 每次解码都 `FindClass/GetMethodID`（HashMap, ArrayList, Integer, Boolean），未做静态缓存，约 1-2ms。
- **每帧内存分配**: `enlarged`（~1MB）和 `bin_img`（~1MB）仍为每帧 `allocate/free`，未复用。
- **SCAN_LINE_DIS=8 的准确率**: 少数边界帧因列间距增大可能丢失边缘模式点（run9 中 locate<7 拒绝 24 帧 vs run7 的 4 帧，虽不能排除会话难度差异，仍需同帧 A/B 确认无回归）。

### 8.2 已评估但未采用的方案

| 方案 | 原因 |
|---|---|
| Otsu 优先（Otsu 二值化 → Gaussian 回退） | 命中率 4%，远低于盈亏平衡 ~14%，96% 回退帧双倍开销拖慢质量 |
| 去掉 2× 放大（1× 路径） | 降 BCH 余量（err_num 上移 ~1），且 NEON 后 2× 二值化仅 21ms（可接受） |
| NEON 化 deskew | 仅倾斜帧触发（<5%），ROI 低 |
| 二值化核缩小（15→11） | 精度风险（改变自适应阈值局部性），当前 21ms 已在 NEON 近下限 |

### 8.3 如需继续优化

- **JNI 缓存**: `buildResultMap` 的 `jclass`/`jmethodID` 改为 `static` 一次查找，省 ~1ms/解码。
- **enlarged/bin_img 复用**: 静态 buffer 复用消除每帧 2 次 ~1MB 分配。
- **SCAN_LINE_DIS 回调**: 若同帧 A/B 确认 locate 拒绝增加，回调到 7 或 6（保守提速）。
