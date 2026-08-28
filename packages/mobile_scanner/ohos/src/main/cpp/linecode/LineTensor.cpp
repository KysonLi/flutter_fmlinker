// LineTensor.cpp —— 结构张量方案实现（FL-T 系列，独立于 LineLocator）。
//
// 步骤：
//  1. 降采样 stride=2（性能），Sobel 梯度。
//  2. 局部窗口结构张量累加 → 相干性 C / 主方向 θ / 幅值 m。
//  3. 近水平边缘投影 H[y]：逐行取"近水平边缘 run ≥ minRun"的长度和
//     （主方向形态学长度滤波的离散等价，滤文字短笔画）。
//  4. 双峰对搜索：H[y] 两个峰（行心距 ≈ 2·bw），gap 回落。
//  5. x 范围：两行中心列均值暗列。
//  6. 旋转矩形长宽比验证 + 合成置信度。
//
// 缓冲全部 thread_local，绝不堆分配。

#include "LineTensor.h"
#include "buffer.h"
#include <algorithm>
#include <cmath>

static const int    ILD_T_STRIDE   = 3;    // 降采样（速度优化 2→3：像素数 ×0.44）
static const double ILD_T_HOR_TOL  = 0.50; // 近水平判定容差（等价 |θg|≥67.5°，
                                           // 实现为代数式 |gy|≥2.414·|gx|，免 atan2）
static const int    ILD_T_MIN_RUN  = 5;    // 降采样域最小 run（≈原 15px，滤文字碎片）
static const double ILD_T_SEP_MIN  = 0.5;  // 行距下限 ×bwExp（放宽：码不满宽帧行距
                                           // 远小于 W/71，如 00016 sep≈9 vs bwExp 10.5）
static const double ILD_T_SEP_MAX  = 3.5;  // 行距上限 ×bwExp
static const double ILD_T_ASPECT_MIN = 8.0; // 候选矩形长宽比下限（码 23.7:1，实测≥8 即码）
static const double ILD_T_CONF_MIN = 0.50; // found 置信门
static const double ILD_T_EDGE_MIN = 0.15; // 近水平投影峰 vs 全图水平边强度比下限

// 结构张量（速度优化版 2026-08-20）：
//   - Sobel 展直公式 + int16 梯度（源是 3 抽头平滑的整数和，|g|≤3060）
//   - 窗口张量用 2D 前缀和（int64 精确），3x3 窗口和 O(1)/像素，
//     替代原 9 邻×3 乘；C=disc/tr 闭式（免 λ1/λ2）
//   - 去掉逐像素 atan2（近水平判定改代数式）
//   真机 584×234 原版 22-31ms；目标 <8ms。
// tiltOut：主倾角（行 y 随 x 的漂移，px 跨全宽；0=未估出/无倾）
static void tensor_field(const TImage* img, int ws, int hs,
                         tl::buffer<float>& coh, tl::buffer<float>& mag,
                         tl::buffer<double>& hproj, int* tiltOut)
{
    const int W = img->w, H = img->h;
    const int s = ILD_T_STRIDE;
    // coh 边界行/列（j=0/hs-1, i=0/ws-1）第二步相干计算不写；但路径跟踪的对角跟随
    // 会把 jj 走到 hs-1 → 读边界未初始化值 → 垃圾随 malloc 历史变 → tensor 定位
    // 顺序依赖（2026-08-27 自 wasm 端根治同步：基线 6 语料正/逆序解码差 32→2 帧）。
    // 显式清零消除该 UB。
    coh.assign(ws * hs, 0.0f);
    mag.resize(ws * hs);
    hproj.resize(H);
    *tiltOut = 0;

    // 预平滑（行内 3 抽头，int）
    static thread_local tl::buffer<int> sm;
    sm.resize(W * H);
    for (int y = 0; y < H; ++y) {
        const unsigned char* r0 = img->pixel + (size_t)y * img->bpl;
        int* dst = &sm[y*W];
        dst[0] = r0[0] + r0[std::min(1, W-1)];
        for (int x = 1; x < W - 1; ++x)
            dst[x] = r0[x-1] + r0[x] + r0[x+1];
        dst[W-1] = r0[W-2] + r0[W-1];
    }

    // 第一步：Sobel（展直公式）+ 平方项 int64 前缀和（(ws+1)×(hs+1)）
    static thread_local tl::buffer<short> gxB, gyB;
    static thread_local tl::buffer<long long> Sxx, Sxy, Syy;
    gxB.resize(ws * hs); gyB.resize(ws * hs);
    const int PW = ws + 1;
    Sxx.resize((size_t)PW * (hs + 1));
    Sxy.resize((size_t)PW * (hs + 1));
    Syy.resize((size_t)PW * (hs + 1));
    for (int i = 0; i < PW; ++i) {
        Sxx[i] = Sxy[i] = Syy[i] = 0;
        Sxx[(size_t)hs*PW + i] = Sxy[(size_t)hs*PW + i] = Syy[(size_t)hs*PW + i] = 0;
    }
    for (int j = 0; j < hs; ++j) {
        int yc = j * s + 1;
        if (yc >= H - 1) yc = H - 2;
        if (yc < 1) yc = 1;
        const int* rU = &sm[(size_t)(yc-1)*W];
        const int* rC = &sm[(size_t)yc*W];
        const int* rD = &sm[(size_t)(yc+1)*W];
        Sxx[(size_t)(j+1)*PW] = Sxy[(size_t)(j+1)*PW] = Syy[(size_t)(j+1)*PW] = 0;
        long long rxx = 0, rxy = 0, ryy = 0;
        const size_t rowP = (size_t)(j+1)*PW;
        const size_t prevP = (size_t)j*PW;
        for (int i = 0; i < ws; ++i) {
            int xc = i * s + 1;
            if (xc >= W - 1) xc = W - 2;
            if (xc < 1) xc = 1;
            int gx = (rU[xc+1] + 2*rC[xc+1] + rD[xc+1]) - (rU[xc-1] + 2*rC[xc-1] + rD[xc-1]);
            int gy = (rD[xc-1] + 2*rD[xc] + rD[xc+1]) - (rU[xc-1] + 2*rU[xc] + rU[xc+1]);
            gxB[j*ws+i] = (short)gx;
            gyB[j*ws+i] = (short)gy;
            mag[j*ws+i] = sqrtf((float)(gx*gx + gy*gy));
            rxx += (long long)gx*gx; rxy += (long long)gx*gy; ryy += (long long)gy*gy;
            Sxx[rowP + i+1] = Sxx[prevP + i+1] + rxx;
            Sxy[rowP + i+1] = Sxy[prevP + i+1] + rxy;
            Syy[rowP + i+1] = Syy[prevP + i+1] + ryy;
        }
    }

    // 第二步：3x3 窗口张量和（前缀和 O(1)/像素）→ 相干性 C=disc/tr
    //（"方向相干性"的载体：窗口内多像素梯度平均后，方向散布（文字）让
    // λ2 非零 → C 低；方向一致（码水平边）→ λ2≈0 → C 高。）
    for (int j = 1; j < hs - 1; ++j) {
        const size_t pBB = (size_t)(j+2)*PW, pTB = (size_t)(j-1)*PW;
        for (int i = 1; i < ws - 1; ++i) {
            long long Jxx = Sxx[pBB + i+2] - Sxx[pTB + i+2]
                          - Sxx[pBB + i-1] + Sxx[pTB + i-1];
            long long Jxy = Sxy[pBB + i+2] - Sxy[pTB + i+2]
                          - Sxy[pBB + i-1] + Sxy[pTB + i-1];
            long long Jyy = Syy[pBB + i+2] - Syy[pTB + i+2]
                          - Syy[pBB + i-1] + Syy[pTB + i-1];
            double tr = (double)Jxx + (double)Jyy;
            float C = 0.f;
            if (tr > 1e-6) {
                double dxx = (double)Jxx - (double)Jyy;
                double disc = sqrt(dxx*dxx + 4.0*(double)Jxy*(double)Jxy);
                C = (float)(disc / tr);
            }
            coh[j*ws+i] = C;
        }
    }

    // 第三步（路径跟踪 run 投影）：沿列前进允许 j±1 跟随——倾斜线在降采样
    // 网格上斜行，纯行内 run 会断裂（cache2/00134 倾斜码输给清晰文字的根因）。
    // 路径长 ≥ ILD_T_MIN_RUN 才计入 H（bin=路径 j 中点×s，直线单 bin 塌缩）。
    // 路径斜率 → 倾角直方图（长度加权）→ 主倾角 tiltOut（裁剪余量用）。
    for (int y = 0; y < H; ++y) hproj[y] = 0.0;
    {
        static thread_local tl::buffer<unsigned char> vis;
        vis.assign(ws * hs, 0);
        // 近水平判定：梯度方向近垂直 + 相干 + 幅值
        auto qual = [&](int j, int i) -> bool {
            int idx = j*ws+i;
            // 近水平边（梯度近垂直）：|θg|≥67.5° 的代数等价 |gy|≥2.414|gx|（免 atan2）
            if ((int)gyB[idx] < 0 ? -(int)gyB[idx] : (int)gyB[idx]
                < 2414 * ((int)gxB[idx] < 0 ? -(int)gxB[idx] : (int)gxB[idx]) / 1000)
                return false;
            if (coh[idx] < 0.2f || mag[idx] < 4.0f) return false;
            return true;
        };
        const int TB = 41;                        // -40..+40 px，2px/bin
        double thist[TB] = {0};
        for (int j = 1; j < hs - 1; ++j) {
            for (int i = 0; i < ws; ++i) {
                if (vis[j*ws+i] || !qual(j, i)) continue;
                int jj = j, ii = i;
                int len = 0; double wsum = 0;
                int j0 = jj, j1 = jj;
                while (ii < ws) {
                    if (!qual(jj, ii)) {
                        // 对角跟随：先上后下（贴着线走，容忍 ±1 行/列 倾斜）
                        if (jj > 0 && qual(jj - 1, ii)) --jj;
                        else if (jj < hs - 1 && qual(jj + 1, ii)) ++jj;
                        else break;
                    }
                    vis[jj*ws+ii] = 1;
                    wsum += coh[jj*ws+ii] * mag[jj*ws+ii];
                    ++len;
                    if (jj < j0) j0 = jj;
                    if (jj > j1) j1 = jj;
                    ++ii;
                }
                if (len < ILD_T_MIN_RUN) continue;
                int bin = (j0 + j1) / 2 * s;
                if (bin >= 0 && bin < H) {
                    hproj[bin] += wsum;
                    if (bin > 0) hproj[bin-1] += wsum * 0.5;
                    if (bin + 1 < H) hproj[bin+1] += wsum * 0.5;
                }
                double tiltPx = (double)(j1 - j0) * W / (double)len;
                if (fabs(tiltPx) <= 40.0) {
                    int b = (int)((tiltPx + 40.0) / 2.0);
                    if (b < 0) b = 0; if (b >= TB) b = TB - 1;
                    thist[b] += len;
                }
            }
        }
        int bb = -1; double bv = 0;
        for (int b = 1; b < TB - 1; ++b) {
            double v = thist[b-1] + thist[b] + thist[b+1];
            if (v > bv) { bv = v; bb = b; }
        }
        if (bb >= 0)
            *tiltOut = (int)lround((bb + 0.5) * 2.0 - 40.0);
    }
}

// 双峰对搜索（H[y] 剖面）。bandsOut/nBandsOut：导出 top 带列表（供候选对枚举）。
static void find_pair(const tl::buffer<double>& H, int Hn, double bwExp,
                      tl::buffer<double>& scratch, int* p0, int* p1,
                      double* v0, double* v1, double* med,
                      int* bandsY = 0, double* bandsV = 0, int* nBandsOut = 0)
{
    *p0 = *p1 = -1; *v0 = *v1 = 0; *med = 0;
    if (Hn < 12) return;
    scratch.resize(Hn);
    for (int y = 0; y < Hn; ++y) scratch[y] = H[y];
    std::nth_element(&scratch[0], &scratch[0]+Hn/2, &scratch[0]+Hn);
    *med = scratch[Hn/2];
    double maxv = 0;
    for (int y = 0; y < Hn; ++y) if (H[y] > maxv) maxv = H[y];
    if (maxv <= 0) return;
    // 局部极大 + 高度排序 → 取 top2 间距 ∈ [minSep,maxSep]
    struct { int y; double v; } pk[64];
    int np = 0;
    for (int y = 2; y < Hn - 2; ++y) {
        double v = H[y];
        if (v <= 0) continue;
        bool mx = true;
        for (int d = -2; d <= 2; ++d) if (d && H[y+d] > v) { mx = false; break; }
        if (!mx) continue;
        if (np < 64) { pk[np].y = y; pk[np].v = v; ++np; }
    }
    std::sort(pk, pk+np, [](const decltype(*pk)& a, const decltype(*pk)& b){ return a.v > b.v; });
    int minSep = (int)(bwExp * ILD_T_SEP_MIN); if (minSep < 6) minSep = 6;
    int maxSep = (int)(bwExp * ILD_T_SEP_MAX); if (maxSep > Hn-2) maxSep = Hn-2;
    // 带聚类：把间距 ≤8px 的邻近峰并入同一个"行带"（取带内最高为带峰）。
    // 码的每行贡献 1 条近水平边缘带，但带内可能因纹理有多个子峰
    // （00016 下行带 378/380/382/384）——子峰必须合并成一行，否则误判两行。
    struct { int y; double v; } bands[16];
    int nb = 0;
    const int BAND_R = 6;   // 带内子峰合并半径（00016 下行带子峰 378/384 间距 6；
                            // 上行/下行带间距 ≥8 须保留分离）
    for (int i = 0; i < np; ++i) {
        bool merged = false;
        for (int b = 0; b < nb; ++b)
            if (abs(pk[i].y - bands[b].y) <= BAND_R) { merged = true; break; }
        if (!merged && nb < 16) { bands[nb].y = pk[i].y; bands[nb].v = pk[i].v; ++nb; }
    }
    if (nb < 2) return;
    int p0y = bands[0].y; double p0v = bands[0].v;   // 主选=分数最高带（排序前留存）
    // 导出 top-8 带（y 升序）供候选对枚举
    if (bandsY && bandsV && nBandsOut) {
        int m = nb < 8 ? nb : 8;
        for (int a = 0; a < m; ++a)
            for (int b = a + 1; b < m; ++b)
                if (bands[b].y < bands[a].y) {
                    int ty = bands[a].y; double tv = bands[a].v;
                    bands[a].y = bands[b].y; bands[a].v = bands[b].v;
                    bands[b].y = ty; bands[b].v = tv;
                }
        for (int a = 0; a < m; ++a) { bandsY[a] = bands[a].y; bandsV[a] = bands[a].v; }
        *nBandsOut = m;
    }
    *p0 = p0y; *v0 = p0v;
    // 次高带：间距在窗口内（真行距 2·bw）
    for (int b = 1; b < nb; ++b) {
        int d = abs(bands[b].y - *p0);
        if (d >= minSep && d <= maxSep) { *p1 = bands[b].y; *v1 = bands[b].v; break; }
    }
}

// 行中心精化：H[y] 峰邻域加权重心
static double centroid(const tl::buffer<double>& H, int c, int halfW)
{
    int Hn = (int)H.size();
    int lo = c - halfW; if (lo < 0) lo = 0;
    int hi = c + halfW; if (hi >= Hn) hi = Hn - 1;
    double s = 0, sw = 0;
    for (int y = lo; y <= hi; ++y) { s += H[y]*(y+1); sw += H[y]; }
    return sw > 0 ? s/sw - 1.0 : (double)c;
}

// x 范围：两行中心间列均值暗列（相对背景）
static void x_extent(const TImage* img, int yA, int yB,
                     tl::buffer<double>& col, tl::buffer<double>& sbuf, int* xL, int* xR)
{
    const int W = img->w, H = img->h;
    *xL = -1; *xR = -1;
    col.resize(W);
    for (int x = 0; x < W; ++x) {
        double s = 0; int n = 0;
        for (int y = yA; y <= yB; ++y) {
            if (y < 0 || y >= H) continue;
            s += img->pixel[(size_t)y * img->bpl + x]; ++n;
        }
        col[x] = n ? s/n : 0;
    }
    sbuf.resize(W);
    for (int x = 0; x < W; ++x) sbuf[x] = col[x];
    std::nth_element(&sbuf[0], &sbuf[0]+W/2, &sbuf[0]+W);
    double bg = sbuf[W/2];
    double mn = col[0];
    for (int x = 1; x < W; ++x) if (col[x] < mn) mn = col[x];
    double thr = bg - 0.5*(bg - mn);
    for (int x = 0; x < W; ++x) if (col[x] < thr) { *xL = x; break; }
    for (int x = W-1; x >= 0; --x) if (col[x] < thr) { *xR = x; break; }
}

int ild_tensor_locate(const TImage* gray, IldTensorLoc* loc)
{
    loc->found = false;
    loc->yRow0 = loc->yRow1 = 0;
    loc->e0 = loc->e1 = loc->e2 = loc->e3 = 0;
    loc->pitch = loc->sep = loc->bw = 0;
    loc->tiltD = 0;
    loc->xL = loc->xR = -1;
    loc->conf = 0; loc->aspect = 0; loc->coh = 0; loc->hEdge = 0; loc->sweeps = 0;
    loc->nPairs = 0;

    const int W = gray->w, H = gray->h;
    if (W < 100 || H < 40) return 0;
    const int s = ILD_T_STRIDE;
    const int ws = W / s, hs = H / s;
    const double bwExp = (double)W / 71.0;

    static thread_local tl::buffer<float> coh, mag;
    static thread_local tl::buffer<double> hBuf, scratch, col, sbuf;
    int tiltD = 0;
    tensor_field(gray, ws, hs, coh, mag, hBuf, &tiltD);
    loc->tiltD = tiltD;

    int p0, p1; double v0, v1, med;
    int bY[8]; double bV[8]; int nB = 0;
    find_pair(hBuf, (int)hBuf.size(), bwExp, scratch, &p0, &p1, &v0, &v1, &med, bY, bV, &nB);
    // 候选对枚举：top-8 带组对（行距窗 [6, 3.5·bwExp+4]），min 分数降序，
    // 供"逐对裁剪→解码仲裁"。廉价特征（相干/转移/长宽比/gap）均无法区分
    // 码与文字/干扰线（GT 回归帧实测），唯一可靠仲裁 = 解码。
    loc->nPairs = 0;
    if (nB >= 2) {
        struct PC { int a, b; double s; } cand[28];
        int nc = 0;
        double lo = 6.0, hiW = 3.5 * bwExp + 4;
        for (int a = 0; a < nB; ++a)
            for (int b = a + 1; b < nB; ++b) {
                double d = fabs((double)bY[b] - bY[a]);
                if (d < lo || d > hiW) continue;
                double s = bV[a] < bV[b] ? bV[a] : bV[b];
                if (nc < 28) { cand[nc].a = a; cand[nc].b = b; cand[nc].s = s; ++nc; }
            }
        std::sort(cand, cand + nc,
                  [](const PC& x, const PC& y) { return x.s > y.s; });
        for (int i = 0; i < nc && loc->nPairs < 8; ++i) {
            loc->pairY0[loc->nPairs] = bY[cand[i].a];
            loc->pairY1[loc->nPairs] = bY[cand[i].b];
            loc->pairScore[loc->nPairs] = cand[i].s;
            ++loc->nPairs;
        }
    }
    if (p0 < 0 || p1 < 0) {
        if (getenv("ILD_T_DEBUG")) fprintf(stderr, "[tdbg] pair-fail p0=%d p1=%d\n", p0, p1);
        return 0;
    }

    double c0 = centroid(hBuf, p0, 3);   // halfW=3：窄行距帧（00016 sep≈8）两带
    double c1 = centroid(hBuf, p1, 3);   // 互不污染（窗口 6 会跨带拉近重心）
    double sep = fabs(c1 - c0);   // p0=最高峰可能在下行带（y 大），须取绝对值
    double bw = sep / 2.0;
    if (sep < 6 || sep > 2.8 * bwExp + 4) {
        if (getenv("ILD_T_DEBUG")) fprintf(stderr, "[tdbg] sep-fail c0=%.1f c1=%.1f sep=%.1f\n", c0, c1, sep);
        return 0;
    }

    // 四边缘近似：行中心 ± bw/2
    int yA = (int)(c0 < c1 ? c0 : c1);
    int yB = (int)(c0 < c1 ? c1 : c0);
    loc->yRow0 = yA; loc->yRow1 = yB;
    loc->sep = sep; loc->bw = bw;
    loc->pitch = (int)(bw * 2.0 + 0.5);

    x_extent(gray, yA - 3, yB + 3, col, sbuf, &loc->xL, &loc->xR);  // ±3 覆盖整码带
    if (loc->xL < 0 || loc->xR <= loc->xL) {
        if (getenv("ILD_T_DEBUG")) fprintf(stderr, "[tdbg] xext-fail x=[%d,%d]\n", loc->xL, loc->xR);
        return 0;
    }

    // 长宽比（旋转矩形筛选）
    double aspect = (double)(loc->xR - loc->xL) / (double)(yB - yA + 1);
    loc->aspect = aspect;
    if (aspect < ILD_T_ASPECT_MIN) {
        if (getenv("ILD_T_DEBUG")) fprintf(stderr, "[tdbg] aspect-fail %.1f\n", aspect);
        return 0;
    }

    // 合成置信度：相干性强度 + 投影峰相对锐度 + 长宽比
    double cohMean = 0; int cn = 0;
    for (int y = yA - 2; y <= yB + 2; ++y)
        for (int i = 0; i < ws; ++i) {
            int j = y / s;
            if (j < 0 || j >= hs) continue;
            cohMean += coh[j*ws+i]; ++cn;
        }
    loc->coh = cn ? cohMean / cn : 0;
    loc->hEdge = (v0 + v1) / 2.0;
    double sharp = (v0 + v1) / (2.0*(med + 1.0));
    struct Cl { static double c(double x){ return x<0?0:(x>1?1:x); } };
    double cCoh = Cl::c(loc->coh / 0.5);
    double cSharp = Cl::c(sharp / 6.0);
    double cAspect = Cl::c((aspect - ILD_T_ASPECT_MIN) / 20.0);
    loc->conf = 0.45*cCoh + 0.35*cSharp + 0.20*cAspect;

    // 四边缘填（行中心±bw/2 近似，供裁剪复用）
    double half = bw / 2.0;
    loc->e0 = (int)(yA - half); loc->e1 = (int)(yA + half);
    loc->e2 = (int)(yB - half); loc->e3 = (int)(yB + half);
    loc->sweeps = 1;
    loc->found = loc->conf >= ILD_T_CONF_MIN;
    if (getenv("ILD_T_DEBUG"))
        fprintf(stderr, "[tdbg] yA=%d yB=%d sep=%.1f bw=%.1f x=[%d,%d] aspect=%.1f coh=%.2f hEdge=%.1f conf=%.2f found=%d\n",
                yA, yB, sep, bw, loc->xL, loc->xR, aspect, loc->coh, loc->hEdge, loc->conf, loc->found);
    ILD_LOGD("tensor_locate: found=%d yA=%d yB=%d sep=%.1f bw=%.1f aspect=%.1f coh=%.2f conf=%.2f",
             loc->found, yA, yB, sep, bw, aspect, loc->coh, loc->conf);
    return loc->found ? 1 : 0;
}
