# ISLI 盾牌码解码算法分析与优化方案

## 一、解码流程概览

```
输入图像 (Y/灰度)
    │
    ▼
┌──────────────────────────┐
│ Stage 1: ISLIIconLocator │  图标定位
│  - 水平/垂直/45°/135°扫描线 │
│  - 每条线: Binarization → BSPatternMatch │
└──────────┬───────────────┘
           │ 输出: 外框两端点坐标 (x1,y1)(x2,y2) + frame_size
    ▼
┌──────────────────────────┐
│ Stage 2: FrameTracer     │  外框追踪
│  - amend_center: 圆形区域质心修正 (最多3次迭代)  │
│  - 沿边框步进追踪，直到闭合  │
└──────────┬───────────────┘
           │ 输出: 外框追踪点序列 px[], py[] (88~264点)
    ▼
┌──────────────────────────┐
│ Stage 3: CornerFinder    │  角点定位与精化
│  - deriv2angle: 逐点方向角 → 角度差 → 找4个局部最大 │
│  - normalize_corners_sequence: 排序+确定旋转方向 │
│  - CornerFinetuner: Harris角点检测精化 │
└──────────┬───────────────┘
           │ 输出: 4个角点坐标 (按序排列,顺时针/逆时针)
    ▼
┌──────────────────────────┐
│ Stage 4: CurveSampler    │  曲线拟合与采样
│  - 每边做坐标归一化 → 最小二乘3次曲线拟合 │
│  - 曲线分段求弧长 → 等弧长采样 │
│  - sample_line: 3×3均值滤波采样 │
│  - do_low_pass_filter: 27-tap FIR低通滤波 │
└──────────┬───────────────┘
           │ 输出: 4条曲线的滤波波形 pcurve[4][]
    ▼
┌──────────────────────────┐
│ Stage 5: Wave2Bits       │  波形解码为比特
│  - 找同步位(sync) → 局部阈值 → 二值化 → 采样 │
│  - 63bit模式: 短边1段/长边3段 │
│  - 112bit模式: 短边2段/长边4段 │
└──────────┬───────────────┘
           │ 输出: 63bit 或 112bit 原始位流
    ▼
┌──────────────────────────┐
│ Stage 6: BCH ECC解码     │  纠错并验证
│  - BCH(63,36,5) 或 BCH(127,64,7) │
│  - 纠错 → encode验证 → 位转十进制字符串 │
└──────────┬───────────────┘
           │ 输出: 11位或19位十进制ISLI编码
    ▼
```

---

## 二、性能瓶颈分析

基于代码分析，主要性能瓶颈按影响程度排列：

### 🔴 瓶颈1: FrameTracer — 圆形区域双重遍历 (预估影响: ~10-15%)

**位置**: `FrameTracer.cpp:15-63 calc_center_shift()`

**问题**: 对同一个圆形区域遍历两遍：
- 第1遍: 累加所有像素 → 算平均 → 算阈值
- 第2遍: 用阈值区分暗像素 → 算质心

每个追踪点(88~264个)都要执行此操作。圆半径 ~20-30px，面积 ~1200-2800像素，每帧总计要遍历 ~100K-750K 像素两次。

### 🔴 瓶颈2: CornerFinetuner — 高斯核重复生成 (预估影响: ~5-8%)

**位置**: `CornerFinetuner.cpp:158-170 create_guass_kernel()` + `corner_score()`

**问题**: 
- 4个角点各调用一次 `create_guass_kernel(r2)`，每次都计算 `(2r+1)²` 次 `exp()` 
- `corner_score()` 对圆形区域边界上每个像素都调用 `smooth()` 3次（计算Ix, Iy），产生大量冗余像素读取

### 🔴 瓶颈3: 频繁的堆内存分配 (预估影响: ~5-10%)

**位置**: 遍布各模块

**问题**: 每帧解码存在大量堆分配/释放：
- `double[] px, py` — FrameTracer
- `unsigned char[] curve_buffer` — CurveSampler  
- `SKEW_LINE[]` — ISLIIconLocator (最多400+对象)
- `unsigned short[] bs` — Binarization (每条扫描线)
- `unsigned char[] th` — Binarization (每条扫描线)
- `pair[] pv` — Binarization::threshold
- `int[] angle` — CornerFinder
- `double[] nx, ny, xx, yy` — CurveFit
- `int[] score` — Wave2Bits (多次)
- `unsigned char[] bin` — Wave2Bits

在实时相机预览场景(15-30fps)下，这些分配会频繁触发GC/内存碎片。

### 🟡 瓶颈4: Binarization — 三次扫描线遍历 (预估影响: ~5-8%)

**位置**: `Binarization.cpp:209-229 do_binarizaiton()`

**问题**: 每条扫描线都要经历：
1. `gray2bs()` — 全局均值二值化 → BS数组
2. `threshold()` — 逐段找峰谷 → 线性插值 → 自适应阈值数组
3. `gray2bs2()` — 用自适应阈值重新二值化 → BS数组

对于绝大多数成功定位的情况，第一次全局均值二值化就够了。

### 🟡 瓶颈5: CurveFit — 多项式幂次重复计算 (预估影响: ~2-3%)

**位置**: `CurveFit.cpp:9-39 calcA() + calcB()`

**问题**: 构建4×4正规方程矩阵时，每个点都要从 `x¹` 开始循环乘到 `x^(i+j)`。对于 ~100点×4条边，这是 O(N_points × degree²) = O(100 × 36) 次乘法操作。

### 🟡 瓶颈6: ISLIIconLocator — 扫描策略不够高效 (预估影响: ~3-5%)

**位置**: `ISLIIconLocator.cpp:315-347 do_isliicon_locating()`

**问题**:
- 预先生成所有45°/135°斜线(各~100-200条)，即使前几条就能找到
- 大部分场景是水平/垂直的，斜扫通常浪费

### 🟡 瓶颈7: Wave2Bits — 动态内存分配 (预估影响: ~2-3%)

**位置**: `Wave2Bits.cpp` 多个函数

**问题**: `match_sync_pos`、`wave2bits`、`rectify_sync_pos` 中频繁 `new int[]` / `delete[]`，每次调用分配 `sample_per_bit` 大小的数组。

### 🟢 瓶颈8: deriv2angle — 冗余象限判断 (预估影响: ~1%)

**位置**: `CornerFinder.cpp:13-61`

**问题**: 用手动8分支象限判断 + atan，可用单个 `atan2(dy, dx)` 替代。

---

## 三、优化方案

### 优化1: calc_center_shift 单次遍历 【高优先级】

```cpp
// 原代码: 两次完整遍历圆形区域
// 优化: 先快速估计阈值(使用圆形区域1/4子采样)，再单次遍历计算质心

static void calc_center_shift(IMAGE* img,
    double ini_cx, double ini_cy, CircleArea* ca,
    double* dx, double* dy)
{
    int ox = ROUND2INT(ini_cx);
    int oy = ROUND2INT(ini_cy);
    
    // 快速阈值估计: 仅采样圆形的十字线(中心行+中心列)
    long sum_sample = 0;
    int cnt_sample = 0;
    // 中心行采样
    {
        int i = ca->r; // 中心行索引
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + oy * img->bpl + (ox + x);
        for (int j = 0; j < len; j += 3) { // 每3像素采样1个
            sum_sample += ppixel[j];
            cnt_sample++;
        }
    }
    // 中心列采样
    for (int y = -ca->r; y <= ca->r; y += 3) {
        unsigned char* p = img->pixel + (oy + y) * img->bpl + ox;
        sum_sample += *p;
        cnt_sample++;
    }
    long th = (sum_sample / cnt_sample) * 1.2;
    
    // 单次遍历: 同时累加质心坐标
    long cx = 0, cy = 0, cnt = 0;
    for (int y = -ca->r, i = 0; y <= ca->r; y++, i++) {
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + (oy + y) * img->bpl + (ox + x);
        for (int j = 0; j < len; j++) {
            if (ppixel[j] <= th) {
                cx += (x + j);
                cy += y;
                cnt++;
            }
        }
    }
    
    *dx = (double)cx / cnt;
    *dy = (double)cy / cnt;
}
```

**预期收益**: FrameTracer 阶段耗时减少 ~30-40%

---

### 优化2: 高斯核缓存复用 【高优先级】

```cpp
// 原代码: 每个角点都创建一次高斯核
// 优化: 使用静态缓存，按半径缓存高斯核

// 在 CornerFinetuner.cpp 中添加:
#include <unordered_map>

static std::unordered_map<int, double*> g_gauss_kernel_cache;

static double* get_or_create_gauss_kernel(int r) {
    auto it = g_gauss_kernel_cache.find(r);
    if (it != g_gauss_kernel_cache.end()) {
        return it->second;
    }
    
    int e = 2 * r + 1;
    double* kernel = new double[(size_t)(e * e)];
    for (int y = -r; y <= r; y++) {
        for (int x = -r; x <= r; x++) {
            kernel[(r + y) * e + (r + x)] = exp(-(double)(x * x + y * y));
        }
    }
    g_gauss_kernel_cache[r] = kernel;
    return kernel;
}

// 在 isli_icon_decoder_uninit() 中清理:
static void clear_gauss_kernel_cache() {
    for (auto& kv : g_gauss_kernel_cache) {
        delete[] kv.second;
    }
    g_gauss_kernel_cache.clear();
}
```

**预期收益**: CornerFinetuner 阶段耗时减少 ~60-70%

---

### 优化3: 预分配内存池 【高优先级】

```cpp
// 新增 MemoryPool，在 isli_icon_decoder_init 时分配，uninit 时释放
struct DecoderMemoryPool {
    // FrameTracer
    static const int MAX_DOTS = 88 * 3;
    double px[MAX_DOTS];
    double py[MAX_DOTS];
    
    // CurveSampler - 4条曲线，每条最大 MAX_SPAN * SAMPLES_PER_SPAN
    static const int MAX_SPAN = 128;
    static const int SAMPLES_PER_SPAN = 9;
    static const int MAX_CURVE_LEN = MAX_SPAN * SAMPLES_PER_SPAN;
    unsigned char curve_buffer[MAX_CURVE_LEN * 4];
    unsigned char filtered_buffer[MAX_CURVE_LEN * 4];
    
    // Wave2Bits
    unsigned char bin_buffer[MAX_CURVE_LEN];
    int score_buffer[MAX_CURVE_LEN];
    
    // CurveFit
    static const int MAX_FIT_POINTS = 256;
    double fit_nx[MAX_FIT_POINTS];
    double fit_ny[MAX_FIT_POINTS];
    
    // Binarization
    static const int MAX_SCAN_LINE = 4096;
    unsigned short bs[MAX_SCAN_LINE / 4];
    unsigned char th[MAX_SCAN_LINE];
    
    // ISLIIconLocator
    static const int MAX_SKEW_LINES = 300;
    // SKEW_LINE skew_lines[MAX_SKEW_LINES];
    unsigned char skew_wave[MAX_SCAN_LINE];
    
    // CornerFinder
    int angle_buffer[MAX_DOTS];
    
    // CornerFinetuner
    static const int MAX_PATCH = 128;
    unsigned char bw_patch[MAX_PATCH * MAX_PATCH];
    long long score_patch[MAX_PATCH * MAX_PATCH];
};

static DecoderMemoryPool* g_pool = nullptr;

int isli_icon_decoder_init() {
    // ... 原有BCH初始化 ...
    if (!g_pool) {
        g_pool = new DecoderMemoryPool();
    }
    return 1;
}

int isli_icon_decoder_uninit() {
    // ... 原有BCH清理 ...
    delete g_pool;
    g_pool = nullptr;
    return 1;
}
```

**预期收益**: 消除所有堆分配开销，整体提升 ~5-10%

---

### 优化4: Binarization 快速路径 【中优先级】

```cpp
// 先用快速全局阈值二值化 → 尝试BSPatternMatch
// 匹配成功则跳过自适应阈值精化

int do_binarizaiton_fast(unsigned char* gray_line, int gray_len, 
                          unsigned short* bs, int bs_len) {
    int bs_num = bs_len;
    int avg = gray2bs(gray_line, gray_len, bs, &bs_num);
    // 不执行threshold + gray2bs2，直接返回
    return bs_num;
}

// 在 locate_in_line 中:
static int locate_in_line(unsigned char* gray_line, int line_len, 
                           int* pos1, int* pos2, double* frame_size) {
    unsigned short* bs = new unsigned short[(size_t)line_len / 4];
    int bs_num = do_binarizaiton_fast(gray_line, line_len, bs, line_len / 4);
    int r = do_bspatternmatch(bs, bs_num, pos1, pos2, frame_size);
    
    if (!r) {
        // 快速路径失败，走完整自适应阈值路径
        bs_num = line_len / 4;
        bs_num = do_binarizaiton(gray_line, line_len, bs, bs_num);
        r = do_bspatternmatch(bs, bs_num, pos1, pos2, frame_size);
    }
    
    delete[] bs;
    return r;
}
```

**预期收益**: 90%+ 场景下跳过冗余的threshold/gray2bs2，定位阶段耗时减少 ~40-50%

---

### 优化5: 斜线扫描延迟生成 【中优先级】

```cpp
// 原代码: create_45degree_lines() 一次性生成所有斜线
// 优化: 改为迭代器模式，逐条生成逐条扫描

class SkewLineIterator {
    int w_, h_;
    int i_, k_;
    int end0_, end1_;
    static const int SKEW_SCAN_DIS = 11;
    static const int MARGIN = 150;
    double dx_, dy_;
    
public:
    SkewLineIterator(int w, int h, bool is_135_degree);
    bool next(SKEW_LINE* line); // 返回false表示没有更多线
};

// do_skew_locating 改为:
int do_skew_locating_v2(IMAGE* image, bool is_135_degree,
    int* x1, int* y1, int* x2, int* y2, double* frame_size) {
    
    SkewLineIterator iter(image->w, image->h, is_135_degree);
    SKEW_LINE line;
    int max_wave_len = std::max(image->w, image->h) * 2;
    unsigned char* wave = new unsigned char[max_wave_len];
    int ret = 0;
    
    while (iter.next(&line)) {
        do_skew_scan(image, &line, wave);
        int a = 0, b = 0;
        if (locate_in_line(wave, line.len, &a, &b, frame_size)) {
            *x1 = int(line.sx + line.dx * a + 0.5);
            *y1 = int(line.sy + line.dy * a + 0.5);
            *x2 = int(line.sx + line.dx * b + 0.5);
            *y2 = int(line.sy + line.dy * b + 0.5);
            ret = 1;
            break;
        }
    }
    
    delete[] wave;
    return ret;
}
```

**预期收益**: 减少不必要的斜线生成，节省内存分配

---

### 优化6: CalcA/CalcB 预计算幂次 【中优先级】

```cpp
// 原代码: 对每个(i,j)组合重新计算 x^(i+j)
// 优化: 预计算每个点的 x^1 ~ x^6

static void calcA_fast(double* px, int len, double** A) {
    // 预计算每个点的幂次
    // 分配栈上小数组(MAX_FIT_POINTS * 7 个double)
    double* pow_cache = new double[(size_t)len * 7]; // x^0 ~ x^6
    for (int k = 0; k < len; k++) {
        double* pc = pow_cache + k * 7;
        pc[0] = 1.0;
        pc[1] = px[k];
        for (int p = 2; p <= 6; p++) {
            pc[p] = pc[p-1] * px[k];
        }
    }
    
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            int power = j + i;
            double tx = 0;
            double* pc = pow_cache + power;
            for (int k = 0; k < len; k++, pc += 7) {
                tx += *pc;
            }
            A[i][j] = tx;
        }
    }
    
    delete[] pow_cache;
}

// calcB 同理
```

**预期收益**: calcA+calcB 耗时减少 ~80%

---

### 优化7: deriv2angle 简化 【低优先级】

```cpp
// 原代码: ~50行手动象限判断 + atan
// 优化: 使用 atan2 + 度数转换

#include <cmath>

static int deriv2angle_fast(double x0, double y0, double x1, double y1) {
    double dx = x1 - x0;
    double dy = y1 - y0;
    // atan2 返回 [-π, π]，转换为 [0, 360)
    int alpha = (int)(atan2(dy, dx) * 180.0 / M_PI + 0.5);
    if (alpha < 0) alpha += 360;
    return alpha;
}
```

**预期收益**: 代码简化，少量性能提升

---

### 优化8: Wave2Bits 内存预分配 【低优先级】

将 `wave2bits`、`match_sync_pos`、`match_sync_010`、`rectify_sync_pos` 中的动态数组改为栈上固定大小或使用预分配缓冲区。

---

### 优化9: sample_line 边界检查移除 【低优先级】

`sample_line` 的3×3均值滤波没有边界检查，依赖调用方保证边界。在 `split_curve_into_span` 中确保采样线不会超出图像边界(加至少1像素margin)，就能安全使用无边界检查的快速路径。

---

## 四、优化优先级总结

| 优先级 | 优化项 | 预期收益 | 改动范围 | 风险 |
|--------|--------|----------|----------|------|
| 🔴 P0 | 优化3: 内存池预分配 | 5-10% | 多个文件 | 低 (最大尺寸已知) |
| 🔴 P0 | 优化1: calc_center_shift 单次遍历 | 10-15% | FrameTracer.cpp | 低 (子采样阈值需验证) |
| 🔴 P0 | 优化4: Binarization 快速路径 | 定位阶段 40-50% | Binarization.cpp | 中 (回退逻辑需测试) |
| 🟡 P1 | 优化2: 高斯核缓存 | Corner阶段 60-70% | CornerFinetuner.cpp | 低 |
| 🟡 P1 | 优化6: CurveFit 幂次预计算 | CurveFit阶段 80% | CurveFit.cpp | 低 |
| 🟡 P1 | 优化5: 斜线延迟生成 | 非水平场景 | ISLIIconLocator.cpp | 中 |
| 🟢 P2 | 优化7: atan2替换 | ~1% | CornerFinder.cpp | 低 |
| 🟢 P2 | 优化8: Wave2Bits 栈化 | ~2% | Wave2Bits.cpp | 低 |
| 🟢 P2 | 优化9: sample_line 去检查 | 微量 | CurveSampler.cpp | 低 |

---

## 五、更宏观的优化方向

### 5.1 多分辨率金字塔加速
当前算法直接在原始分辨率上工作。可以先对图像降采样(1/2或1/4)，快速定位ISLI图标区域，然后仅在感兴趣区域(ROI)上进行完整分辨率解码。这将大幅减少所有阶段的处理像素数。

### 5.2 SIMD加速
以下操作适合NEON(ARM)向量化：
- `calc_center_shift`: 像素比较和累加
- `gray2bs/gray2bs2`: 逐像素阈值比较
- `sample_line/sample_one_curve`: 3×3均值滤波
- `do_low_pass_filter`: 27-tap FIR卷积
- `corner_score`: 3×3 smooth + 梯度计算

### 5.3 多线程流水线
当前流程是串行的。可考虑：
- 定位阶段使用多线程同时扫描水平/垂直/45°/135°
- 波形解码中4条曲线可并行处理

### 5.4 定位失败快速退出
如果水平中心线找不到BS pattern，且图像整体方差很低(模糊、无内容)，可快速返回失败而不继续尝试垂直和斜扫。
