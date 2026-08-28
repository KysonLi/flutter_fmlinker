// LineLocator.cpp —— 灰度域双横线检测器（FL-1）。
//
// 算法（详见 LineLocator.h 头注释）：
//   1) 剪切补偿垂直梯度投影 g[y]：列 x 采样于 y + round(T·x/W)，
//      g[y] = mean_x |I(x,ys) - I(x,ys-1)|。行模块上下缘全长度有墨 →
//      每条行贡献上下两道全宽垂直边缘。
//   2) quadruple 搜索 (y0, pitch p∈[3,30] 整数)：四个槽位 y0+i·p 必须
//      各自吸附到 ±max(1,p/3) 内的原始 g 局部极大，且四个吸附峰互异
//      —— 互异性杀掉"宽噪声峰上小间距别名"（别名槽位会复用同一物理峰）。
//      score = Σ峰高 − 2·gap回落罚（e1..e2 白隔区均值超 0.5·最弱边缘才罚）。
//      实测 cache 已解码帧 pitch≈4.4-5（码仅占 40% 帧宽）—— 无尺度假设。
//   3) 倾斜扫描：T=0 先做，锐度强命中提前出线（生产典型 1 次投影）；
//      否则扫 ±4..±40 取最优。
//   4) x 范围检测（band 区列均值暗列）→ V1 转移数(阈值 25/40) /
//      V2 同步模板 / V3 列覆盖率 → 合成 conf。
//
// 所有缓冲 thread_local，函数绝不堆分配、不抛异常。

#include "LineLocator.h"
#include "buffer.h"
#include <algorithm>
#include <cmath>

// ---- 常量（FL-1 阶段用 1798 图语料标定；先给保守初值）----
static const int    ILD_FL_PITCH_MIN   = 3;     // 模块宽下限（px；低于此解码分辨率不足）
static const int    ILD_FL_PITCH_MAX   = 30;    // 上限（sync_crop 的 bw2 上限同源）
static const double ILD_FL_T_MID       = 0.45;  // found 置信门（FL-1 语料标定：recall 95.8%/reject桶检 41.3%）
static const int    ILD_FL_T25_MIN     = 15;    // V1 硬门：真码行内必有模块结构（t25<15 必非码）
static const int    ILD_FL_TILT_MAX    = 24;    // 置信路径倾角上限：大倾角紧裁剪 margin 膨胀
                                                // 省不了面积，且 |tilt|≥40 为扫描边界吸引伪影
                                                //（实测 00179 双码 mismatch 逃逸者即 tilt=40）→ 回落旧路径
static const double ILD_FL_BAL_MIN     = 0.35;  // 四边缘均衡度硬门（min/max）
static const double ILD_FL_EARLY_SHARP = 3.5;   // 任一剪切强命中即停扫（FL-1 语料
                                                // 已解码帧 sharp p50≈5/p10≈1.9，6.0 几乎不触发）
static const double ILD_FL_GAP_DIP_K   = 0.5;   // gap 回落门：白隔均值 ≤ 0.5·最弱边缘免罚
static const int    ILD_FL_X_STRIDE    = 8;     // 投影 x 步长（V1/V2/V3 行剖面仍逐列，不受影响）
static const int    ILD_FL_NM_WIN      = 10;    // 最近局部极大查找窗口（±px）

// 倾斜扫描表：0 优先；覆盖 ±40px 纵向漂移（≈±3° @746 宽，FL-1 实测分布后调整）
static const int kSweepList[] = { 0, 4, -4, 8, -8, 12, -12, 16, -16,
                                  20, -20, 24, -24, 32, -32, 40, -40 };
static const int kSweepCount = (int)(sizeof(kSweepList) / sizeof(kSweepList[0]));

// 单次剪切的 quadruple 搜索结果（e/v 为吸附后的真实局部极大位置与高度）
struct FlQuad {
    bool   ok;
    int    y0, p;       // 搜索最优网格起点与整数间距（仅诊断）
    int    e0, e1, e2, e3;
    double v[4];        // 四边缘 g 高度
    double score;       // Σ峰高 − gap 罚
    double med;         // median(g)
    double dom;         // 支配度 = score / 次优不相交 quad 的 score（无次优=99）
    bool   has2;        // 存在不相交次优 quad
    int    s2e0, s2e3;  // 次优 quad 边缘范围（供双码歧义校验）
};

// ---- 步骤 1：剪切补偿垂直梯度投影 ----
static void fl_project(const TImage* img, int T, tl::buffer<double>& g, tl::buffer<int>& dx)
{
    const int W = img->w, H = img->h;
    dx.resize(W);
    for (int x = 0; x < W; ++x)
        dx[x] = (int)floor((double)T * x / W + 0.5);
    g.resize(H);
    for (int y = 0; y < H; ++y) g[y] = 0.0;
    for (int y = 0; y < H; ++y) {
        long long s = 0; int n = 0;
        for (int x = ILD_FL_X_STRIDE / 2; x < W; x += ILD_FL_X_STRIDE) {
            int ys = y + dx[x];
            if (ys < 1 || ys >= H) continue;   // 边界守卫（大倾角时首尾列出界）
            int d = (int)img->pixel[(size_t)ys * img->bpl + x]
                  - (int)img->pixel[(size_t)(ys - 1) * img->bpl + x];
            if (d < 0) d = -d;
            s += d; ++n;
        }
        g[y] = n ? (double)s / n : 0.0;
    }
}

// ---- 步骤 2：quadruple 搜索（槽位吸附互异局部极大 + gap 回落罚[前缀和 O(1)]）----
static void fl_find_quadruple(const tl::buffer<double>& g,
                              tl::buffer<int>& isMax, tl::buffer<int>& nm,
                              tl::buffer<double>& scratch, tl::buffer<double>& prefix, FlQuad* out)
{
    out->ok = false; out->y0 = 0; out->p = 0;
    out->e0 = out->e1 = out->e2 = out->e3 = 0;
    out->score = 0; out->med = 0; out->dom = 99.0;
    out->has2 = false; out->s2e0 = out->s2e3 = 0;
    out->v[0] = out->v[1] = out->v[2] = out->v[3] = 0;
    const int H = (int)g.size();
    if (H < 4 * ILD_FL_PITCH_MIN + 2) return;

    scratch.resize(H);
    for (int i = 0; i < H; ++i) scratch[i] = g[i];
    std::nth_element(&scratch[0], &scratch[0] + H / 2, &scratch[0] + H);
    out->med = scratch[H / 2];

    // gap 均值前缀和：gpre[y+1] = Σ g[0..y]，任意区间均值 O(1)
    prefix.resize(H + 1);
    prefix[0] = 0.0;
    for (int y = 0; y < H; ++y) prefix[y + 1] = prefix[y] + g[y];

    // 局部极大标记 + 每行最近极大索引（±ILD_FL_NM_WIN 内，无则 -1）
    isMax.resize(H); nm.resize(H);
    for (int y = 0; y < H; ++y) isMax[y] = 0;
    for (int y = 1; y < H - 1; ++y)
        if (g[y] >= g[y - 1] && g[y] > g[y + 1] && g[y] > 0) isMax[y] = 1;
    for (int y = 0; y < H; ++y) {
        nm[y] = -1;
        for (int d = 0; d <= ILD_FL_NM_WIN; ++d) {
            if (y - d >= 0 && isMax[y - d]) { nm[y] = y - d; break; }
            if (y + d < H && isMax[y + d]) { nm[y] = y + d; break; }
        }
    }

    double best = -1e18, second = -1e18;   // second = 与最优不相交的次优（双码帧检测）
    int by0 = -1, bp = 0, be[4] = {0, 0, 0, 0};
    double bv[4] = {0, 0, 0, 0};
    int s2y0 = -1, s2p = 0;
    for (int p = ILD_FL_PITCH_MIN; p <= ILD_FL_PITCH_MAX; ++p) {
        int tol = p / 3; if (tol < 1) tol = 1;
        int ymax = H - 3 * p - 1;
        for (int y0 = 0; y0 <= ymax; ++y0) {
            int m[4]; double v[4];
            bool okq = true;
            for (int i = 0; i < 4; ++i) {
                int slot = y0 + i * p;
                int mi = nm[slot];
                if (mi < 0 || (mi - slot > tol) || (slot - mi > tol)) { okq = false; break; }
                for (int j = 0; j < i; ++j)
                    if (m[j] == mi) { okq = false; break; }   // 同一物理峰不得复用（杀别名）
                if (!okq) break;
                m[i] = mi; v[i] = g[mi];
            }
            if (!okq) continue;
            double vmin = v[0];
            for (int i = 1; i < 4; ++i) if (v[i] < vmin) vmin = v[i];
            double s = v[0] + v[1] + v[2] + v[3];
            // gap 回落：m1..m2 之间（1 模块白隔）原始 g 均值应显著低于最弱边缘
            int gn = m[2] - m[1] - 1;
            if (gn > 0) {
                double gm = (prefix[m[2]] - prefix[m[1] + 1]) / gn;
                double pen = gm - ILD_FL_GAP_DIP_K * vmin;
                if (pen > 0) s -= 2.0 * pen;
            }
            if (s > best) {
                if (by0 >= 0 && (y0 + 3 * p < by0 || by0 + 3 * bp < y0)) {
                    second = best; s2y0 = by0; s2p = bp;   // 旧最优与新最优不相交 → 次优
                }
                best = s; by0 = y0; bp = p;
                be[0] = m[0]; be[1] = m[1]; be[2] = m[2]; be[3] = m[3];
                bv[0] = v[0]; bv[1] = v[1]; bv[2] = v[2]; bv[3] = v[3];
            } else if (s > second && (y0 + 3 * p < by0 || by0 + 3 * bp < y0)) {
                second = s; s2y0 = y0; s2p = p;
            }
        }
    }
    if (by0 < 0) return;
    out->dom = (second > 0 && best > 0) ? best / second : 99.0;
    out->has2 = (s2y0 >= 0 && second > 0);
    out->s2e0 = s2y0;
    out->s2e3 = s2y0 + 3 * s2p;
    out->ok = true;
    out->y0 = by0; out->p = bp;
    out->e0 = be[0]; out->e1 = be[1]; out->e2 = be[2]; out->e3 = be[3];
    out->v[0] = bv[0]; out->v[1] = bv[1]; out->v[2] = bv[2]; out->v[3] = bv[3];
    out->score = best;
}

// g 在窗口内的加权重心 → 亚像素质心（窗口覆盖频带的两道边缘，重心≈带中心）
static double fl_centroid(const tl::buffer<double>& g, int lo, int hi)
{
    const int H = (int)g.size();
    if (lo < 0) lo = 0; if (hi >= H) hi = H - 1;
    double s = 0, sw = 0;
    for (int y = lo; y <= hi; ++y) { s += g[y] * (y + 1); sw += g[y]; }
    return sw > 0 ? (s / sw - 1.0) : (double)((lo + hi) / 2);
}

// ---- x 范围检测：band 区 [e0,e3] 列均值，暗列（相对背景）判定首尾 ----
static void fl_x_extent(const TImage* img, const tl::buffer<int>& dx,
                        int e0, int e3, tl::buffer<double>& colMean,
                        tl::buffer<double>& sbuf, int* xL, int* xR)
{
    const int W = img->w, H = img->h;
    *xL = -1; *xR = -1;
    if (W < 8) return;
    colMean.resize(W);
    for (int x = 0; x < W; ++x) {
        double s = 0; int n = 0;
        for (int y = e0; y <= e3; ++y) {
            int ys = y + dx[x];
            if (ys < 0) ys = 0; if (ys >= H) ys = H - 1;
            s += img->pixel[(size_t)ys * img->bpl + x]; ++n;
        }
        colMean[x] = n ? s / n : 0.0;
    }
    // 背景 = 列均值中位数；暗阈值 = bg - 0.5·(bg - min)
    sbuf.resize(W);
    for (int x = 0; x < W; ++x) sbuf[x] = colMean[x];
    std::nth_element(&sbuf[0], &sbuf[0] + W / 2, &sbuf[0] + W);
    double bg = sbuf[W / 2];
    double mn = colMean[0];
    for (int x = 1; x < W; ++x) if (colMean[x] < mn) mn = colMean[x];
    double thr = bg - 0.5 * (bg - mn);
    for (int x = 0; x < W; ++x)
        if (colMean[x] < thr) { *xL = x; break; }
    for (int x = W - 1; x >= 0; --x)
        if (colMean[x] < thr) { *xR = x; break; }
}

// 行剖面：沿（剪切补偿后的）行中心取灰度序列，V1/V2/V3 共用
static void fl_row_profile(const TImage* img, const tl::buffer<int>& dx, double yc,
                           tl::buffer<unsigned char>& prof)
{
    const int W = img->w, H = img->h;
    prof.resize(W);
    int ybase = (int)(yc + 0.5);
    for (int x = 0; x < W; ++x) {
        int ys = ybase + dx[x];
        if (ys < 0) ys = 0; if (ys >= H) ys = H - 1;
        prof[x] = img->pixel[(size_t)ys * img->bpl + x];
    }
}

// V1 转移数（[xL,xR] 两行 |Δ|>thr 各自计数求和）+ V3 列覆盖率（任一行梯度>25）
static void fl_trans_cover(const tl::buffer<unsigned char>& p0v, const tl::buffer<unsigned char>& p1v,
                           int xL, int xR, int* trans40, int* trans25, double* coverage)
{
    if (xL < 0) xL = 0;
    if (xR < xL) xR = (int)p0v.size() - 2;
    long t40 = 0, t25 = 0, cov = 0; int n = 0;
    for (int x = xL; x + 1 <= xR; ++x) {
        int d0 = (int)p0v[x + 1] - (int)p0v[x]; if (d0 < 0) d0 = -d0;
        int d1 = (int)p1v[x + 1] - (int)p1v[x]; if (d1 < 0) d1 = -d1;
        if (d0 > 40) ++t40;  if (d1 > 40) ++t40;
        if (d0 > 25) ++t25;  if (d1 > 25) ++t25;
        if ((d0 > 25 ? d0 : d1) > 25) ++cov;
        ++n;
    }
    *trans40 = (int)t40;
    *trans25 = (int)t25;
    *coverage = n > 0 ? (double)cov / n : 0.0;
}

// V4：转移间隔规整度（文字干扰判据，FL-1b）。真码沿行每模块 1-2 个
// |Δ|>25 转移、间距 ≈bw 均匀；文字呈字符内密集 + 字间/词间大空洞
// （max_gap >> mean_gap）。目测证实文字是最大误检源（crop 精度仅 ~22%）。
// 返回 0..1：1 = 规整（码状），0 = 破碎/无结构。转移过少（模糊）时给 0
// ——这类帧本就不可解，诚实不 found 好过裁错。
static double fl_trans_regular(const tl::buffer<unsigned char>& p0v, int xL, int xR)
{
    if (xL < 0) xL = 0;
    if (xR >= (int)p0v.size() - 1) xR = (int)p0v.size() - 2;
    if (xR - xL < 32) return 0;
    int prev = -1;
    int nGap = 0;
    long sumGap = 0, sumSq = 0;
    int maxGap = 0;
    for (int x = xL; x <= xR; ++x) {
        int d = (int)p0v[x + 1] - (int)p0v[x];
        if (d < 0) d = -d;
        if (d > 25) {
            if (prev >= 0) {
                int g = x - prev;
                ++nGap; sumGap += g; sumSq += (long)g * g;
                if (g > maxGap) maxGap = g;
            }
            prev = x;
        }
    }
    if (nGap < 20) return 0;                      // 转移太少：模糊/空白，非清晰码
    double mean = (double)sumGap / nGap;
    double var = (double)sumSq / nGap - mean * mean;
    if (var < 0) var = 0;
    double cv = (mean > 0) ? var / (mean * mean) : 9.9;   // 变异系数²
    // 码：cv²≈0.3-1.5（模块边界抖动）；文字：词空洞 → cv²>4、maxGap/mean>4
    double ratio = (mean > 0) ? (double)maxGap / mean : 9.9;
    double cvScore = cv <= 3.0 ? 1.0 : (cv >= 8.0 ? 0.0 : (8.0 - cv) / 5.0);
    double rgScore = ratio <= 3.0 ? 1.0 : (ratio >= 6.0 ? 0.0 : (6.0 - ratio) / 3.0);
    return cvScore < rgScore ? cvScore : rgScore;
}

// （sync_crop 硬编码 xL=0 假设码贴左缘；实测码可起于任意 x）。
// V2：S1=101 模板分（镜像 sync_crop :913-921 公式），左端全宽扫描取最大
// （sync_crop 硬编码 xL=0 假设码贴左缘；实测码可起于任意 x）。
static double fl_sync_score(const tl::buffer<unsigned char>& prof, int W, double bw)
{
    int ibw = (int)(bw + 0.5); if (ibw < 4) ibw = 4;
    int hw = ibw / 3; if (hw < 2) hw = 2; if (hw > 6) hw = 6;
    if (W < 3 * ibw + 2 * hw + 1) return 0;
    int step = ibw / 4; if (step < 1) step = 1;
    double best = 0;
    for (int xL = 0; xL + 2 * ibw + hw < W; xL += step) {
        double sc = 0; bool valid = true;
        for (int c = 0; c < 3; ++c) {
            double v = 0; int n = 0;
            int xc = xL + c * ibw;
            for (int dxx = -hw; dxx <= hw; ++dxx) {
                int xs = xc + dxx;
                if (xs >= 0 && xs < W) { v += prof[xs]; ++n; }
            }
            if (n < 3) { valid = false; break; }
            v /= n;
            sc += (c == 1) ? (v - 128.0) : (128.0 - v);   // 模板 101：暗-亮-暗
        }
        if (valid && sc > best) best = sc;
    }
    return best;
}

int ild_locate_two_lines(const TImage* gray, IldLineLoc* loc)
{
    loc->found = false;
    loc->yRow0 = loc->yRow1 = 0;
    loc->e0 = loc->e1 = loc->e2 = loc->e3 = 0;
    loc->pitch = loc->sep = loc->bw = 0;
    loc->tiltD = 0; loc->conf = 0;
    loc->sharp = 0; loc->balance = 0; loc->dom = 99.0; loc->reg = 0;
    loc->trans40 = loc->trans25 = 0;
    loc->coverage = 0; loc->syncScore = 0;
    loc->xL = loc->xR = -1; loc->sweeps = 0; loc->ambig = 0;

    const int W = gray->w, H = gray->h;
    if (W < 71 * ILD_FL_PITCH_MIN || H < 4 * ILD_FL_PITCH_MIN + 2) return 0;

    static thread_local tl::buffer<double> g, scratch, colMean, sbuf, prefix;
    static thread_local tl::buffer<int> dx, isMax, nm;
    static thread_local tl::buffer<unsigned char> prof0, prof1;

    // ---- 步骤 3：倾斜扫描，选归一化分数最优的剪切 ----
    bool haveBest = false;
    int bestT = 0, lastT = 0;
    double bestScore = -1e18, bestMed = 0;
    FlQuad bq;
    for (int si = 0; si < kSweepCount; ++si) {
        int T = kSweepList[si];
        fl_project(gray, T, g, dx);
        lastT = T; ++loc->sweeps;
        FlQuad q;
        fl_find_quadruple(g, isMax, nm, scratch, prefix, &q);
        double norm = q.ok ? q.score / (4.0 * (q.med + 2.0)) : -1.0;
        if (norm > bestScore) {
            bestScore = norm; bestT = T; haveBest = q.ok; bestMed = q.med;
            bq = q;
        }
        // 任一剪切强命中即停扫：正确 T 的分数显著高于错 T（倾斜码扫到自己的
        // T 才触发），未倾斜码 T=0 即触发 → 生产典型 1-2 次投影
        if (q.ok && q.v[0] / (q.med + 2.0) >= ILD_FL_EARLY_SHARP) break;
        // 无望帧早弃：前 5 个剪切（0/±4/±8）后归一化分数仍低 → 判无码终止。
        // 实测 notfound 帧烧满 17 扫描 ~8ms 只为得出"没有"；好帧 norm≥3.5
        // 早已早退，此处只拦截 norm<2.5 的死帧（约 97% 的失败帧）。
        if (si == 4 && bestScore < 2.5) break;
    }
    if (!haveBest) return 0;

    // 最优剪切的投影若非最后一次计算，重算一次（g 后续精化要用）
    if (lastT != bestT) {
        fl_project(gray, bestT, g, dx);
        ++loc->sweeps;
    }
    loc->tiltD = bestT;

    // ---- 行中心精化：每条行窗口（覆盖该行两道边缘）内 g 加权重心 ----
    int p = bq.p;
    int win = p / 2 + 1; if (win < 1) win = 1; if (win > 8) win = 8;
    double c0 = fl_centroid(g, bq.e0 - win + 1, bq.e1 + win - 1);
    double c1 = fl_centroid(g, bq.e2 - win + 1, bq.e3 + win - 1);
    double sep = c1 - c0;
    double bw = sep / 2.0;
    loc->pitch = p;
    loc->sep = sep;
    loc->bw = bw;
    loc->yRow0 = (int)(c0 + 0.5);
    loc->yRow1 = (int)(c1 + 0.5);
    loc->e0 = bq.e0; loc->e1 = bq.e1; loc->e2 = bq.e2; loc->e3 = bq.e3;
    ILD_LOGD("line_locate: c0=%.1f c1=%.1f pitch=%d sep=%.1f bw=%.1f T=%d norm=%.1f",
             c0, c1, p, sep, bw, bestT, bestScore);

    double vMin = bq.v[0], vMax = bq.v[0];
    for (int i = 1; i < 4; ++i) {
        if (bq.v[i] < vMin) vMin = bq.v[i];
        if (bq.v[i] > vMax) vMax = bq.v[i];
    }
    loc->balance = vMax > 0 ? vMin / vMax : 0;
    loc->sharp = vMin / (bestMed + 2.0);
    loc->dom = bq.dom;

    // ---- x 范围 + V1/V2/V3 ----
    fl_x_extent(gray, dx, bq.e0, bq.e3, colMean, sbuf, &loc->xL, &loc->xR);
    fl_row_profile(gray, dx, c0, prof0);
    fl_row_profile(gray, dx, c1, prof1);
    fl_trans_cover(prof0, prof1, loc->xL, loc->xR,
                   &loc->trans40, &loc->trans25, &loc->coverage);
    loc->syncScore = fl_sync_score(prof0, W, bw > 2 ? bw : p);
    loc->reg = fl_trans_regular(prof0, loc->xL, loc->xR);

    // ---- 合成置信度 ----
    struct Cl01 { static double c(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); } };
    double sharpP = Cl01::c(loc->sharp / 6.0);
    double balP   = Cl01::c((loc->balance - ILD_FL_BAL_MIN) / (1.0 - ILD_FL_BAL_MIN));
    double transP = Cl01::c(loc->trans25 / 60.0);
    double covP   = Cl01::c((loc->coverage - 0.08) / 0.20);   // 实测真码 cov≈0.21（模糊剖面 |Δ|>25 稀疏）
    double syncP  = Cl01::c(loc->syncScore / 384.0);
    double geomP  = Cl01::c(1.0 - fabs(bw - p) / (0.30 * p));   // 精化 bw 与搜索 pitch 一致性
    loc->conf = 0.25 * sharpP + 0.20 * balP + 0.20 * transP
              + 0.15 * covP + 0.10 * syncP + 0.10 * geomP;

    // ---- 双码歧义校验：次优不相交 quad 若也具码结构 → 回避置信路径 ----
    // 背景：实测语料存在同帧双码（两卡同框，如 cache1 的 0104+0110）。
    // 置信路径若先解到"另一条码"，输出与设备/旧路径不一致（台架表现为
    // mismatch）。分数支配度无法区分（正常帧杂讯 quad 分数也接近真码），
    // 改用结构校验：次优 quad 行内的转移数也达码级 → 判定歧义。
    bool pitchOK = p >= ILD_FL_PITCH_MIN && p <= ILD_FL_PITCH_MAX;
    bool balOK = loc->balance >= ILD_FL_BAL_MIN;
    bool transOK = loc->trans25 >= ILD_FL_T25_MIN;
    if (bq.has2 && pitchOK && balOK && transOK) {
        int axL, axR;
        fl_x_extent(gray, dx, bq.s2e0, bq.s2e3, colMean, sbuf, &axL, &axR);
        // 次优 quad 带中心近似：4 边缘等距时上行/下行中心 ≈ 跨度的 1/4 与 3/4 处
        double c2_0 = bq.s2e0 + (bq.s2e3 - bq.s2e0) * 0.25;
        double c2_1 = bq.s2e0 + (bq.s2e3 - bq.s2e0) * 0.75;
        static thread_local tl::buffer<unsigned char> prof2, prof3;
        fl_row_profile(gray, dx, c2_0, prof2);
        fl_row_profile(gray, dx, c2_1, prof3);
        int at40, at25; double acov;
        fl_trans_cover(prof2, prof3, axL, axR, &at40, &at25, &acov);
        // 隔离度：真第二条码上下一个跨度内应安静（独立成带）。icon 盾牌是
        // ~60 行高的连续结构团，其上骑出的杂讯 quad 上下同样繁忙 → 非码。
        // （盾牌行内转移数同样高，t25 单独无法区分——实测 cache 真拍摄帧
        //   的"第二结构"多为盾牌，纯 t25 门几乎关死全部置信路径。）
        double inMax = 0;
        for (int y = bq.s2e0; y <= bq.s2e3; ++y)
            if (y >= 0 && y < H && g[y] > inMax) inMax = g[y];
        int span2 = bq.s2e3 - bq.s2e0;
        int qM = span2 + 2;
        double qt = 0; int qtn = 0;
        for (int y = bq.s2e0 - qM; y < bq.s2e0; ++y)
            if (y >= 0 && y < H) { qt += g[y]; ++qtn; }
        double qb = 0; int qbn = 0;
        for (int y = bq.s2e3 + 1; y <= bq.s2e3 + qM; ++y)
            if (y >= 0 && y < H) { qb += g[y]; ++qbn; }
        double qtM = qtn ? qt / qtn : 1e9;
        double qbM = qbn ? qb / qbn : 1e9;
        double qMax = qtM > qbM ? qtM : qbM;
        loc->ambig = (at25 >= ILD_FL_T25_MIN && inMax > 0 && qMax < 0.5 * inMax) ? 1 : 0;
        ILD_LOGD("line_locate: second quad y=[%d,%d] t25=%d inMax=%.1f qMax=%.1f ambig=%d",
                 bq.s2e0, bq.s2e3, at25, inMax, qMax, loc->ambig);
    }

    // ---- 硬几何门 + 置信门（标定用：诊断量已全部填充）----
    bool tiltOK = bestT >= -ILD_FL_TILT_MAX && bestT <= ILD_FL_TILT_MAX;
    // V4 间隔规整硬门（用户要求 crops_v2 方案全量裁剪）：
    // reg≥0.6 只放行"转移间隔规整"的候选。已知局限：码间隔本不均（连续黑
    // 模块无转移），会漏检部分真码——全量预计 found 极少（V4 首测 7/1798）。
    loc->found = pitchOK && balOK && transOK && tiltOK && loc->conf >= ILD_FL_T_MID
              && !loc->ambig && loc->reg >= 0.6;
    ILD_LOGD("line_locate: found=%d conf=%.3f sharp=%.1f bal=%.2f dom=%.2f t25=%d cov=%.2f sync=%.0f x=[%d,%d] ambig=%d",
             loc->found, loc->conf, loc->sharp, loc->balance, loc->dom, loc->trans25,
             loc->coverage, loc->syncScore, loc->xL, loc->xR, loc->ambig);
    return loc->found ? 1 : 0;
}

void ild_line_loc_crop(const IldLineLoc* loc, int W, int H, int* y0, int* y1)
{
    (void)W;
    // 目审反馈：原 margin(0.6bw+8, cap26)+|tilt| 对倾斜码太紧 → 放宽：
    // 基础余量 1.0bw+12（cap 40），倾角余量 ×1.5（tiltD 为直方图粗估，
    // 路径斜率会低估），最小高 48。宽松裁剪只多花少量 gaussian 面积，
    // 对解码仲裁无损（更大上下文反而更稳）。
    double bw = loc->bw; if (bw < 2) bw = 8;
    int m = (int)(bw + 0.5) + 12;
    if (m < 16) m = 16; if (m > 40) m = 40;
    int tilt = loc->tiltD; if (tilt < 0) tilt = -tilt;
    m += tilt * 3 / 2;               // 倾斜漂移 + 估计误差余量
    int top = loc->e0 - m;
    int bot = loc->e3 + m;
    int minH = (loc->e3 - loc->e0) + 2 * m + 8;
    if (minH < 48) minH = 48;
    if (bot - top + 1 < minH) {
        int c = (top + bot) / 2;
        top = c - minH / 2;
        bot = top + minH - 1;
    }
    if (top < 0) top = 0;
    if (bot >= H) bot = H - 1;
    if (bot < top) bot = top;
    *y0 = top; *y1 = bot;
}
