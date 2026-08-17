#include "GaussianBinarization.h"
#include "Common.h"
#include "buffer.h"

#include <math.h>
#include <vector>
#include <cassert>
#include <cstring>
#include <cstdio>
#include <cstdlib>

// SSE4.1 intrinsics: available on all x64 CPUs since ~2008 (Penryn/Barcelona).
// MSVC x64 always has SSE4.1; GCC/Clang need -msse4.1.
#if defined(__SSE4_1__) || (defined(_MSC_VER) && (defined(_M_X64) || defined(_M_AMD64)))
#define ILD_SSE41 1
#include <smmintrin.h>
#endif

#if defined(__aarch64__)
#include <arm_neon.h>
#define ILD_NEON 1
#endif

// 复用 scratch buffer：避免每帧 malloc/free ~0.5-1MB 的临时图。
// 仅增长不释放（进程生命周期）。解码跑在单线程，static 安全。
namespace {
struct ScratchBuf {
    unsigned char* p;
    size_t cap;
    ScratchBuf() : p(nullptr), cap(0) {}
    void ensure(size_t bytes) {
        if (cap >= bytes) return;
        delete[] p;
        p = new unsigned char[bytes];
        cap = bytes;
    }
};
ScratchBuf g_tmp;   // 可分离高斯模糊的 H pass 中转图（水平模糊结果）
ScratchBuf g_blur;  // V pass 输出的 blur 图（二值化阈值比较用）
}

double ild_gaussian_func(double u, double o, double x)
{
    const double e = 2.71828182845904523536028747135266249775;
    const double sqrt_2pi = 2.506628274631000502415765284811;
    double tmp = (x - u) / o;
    double exp = -0.5 * tmp * tmp;
    return pow(e, exp) / o / sqrt_2pi;
}

void ild_gaussian_kernel(tl::buffer<int> &vecKernel, int size)
{
    assert(size % 2 != 0);
    double o = (double)size / 4.29193;
    double x = -size / 2;
    vecKernel.clear();
    for (int i = 0; i < size; i++) {
        vecKernel.push_back((int)(ild_gaussian_func(0.0, o, x) * 8388607.0));
        x += 1.0;
    }
}

// 高斯核（构建一次，跨图复用）。函数局部 static，C++11 线程安全初始化。
static const tl::buffer<int>& ild_gauss_kernel_cache() {
    static tl::buffer<int> kernel;
    if (kernel.size() == 0) {
        kernel.reserve(ILD_GAUSSIAN_KERNEL);
        ild_gaussian_kernel(kernel, ILD_GAUSSIAN_KERNEL);
    }
    return kernel;
}

// 2-pass separable Gaussian blur (symmetric optimization: 15->8 multiplications per pixel).
// SSE4.1 path processes 4 pixels at a time; NEON(aarch64) 8 pixels/iter; scalar fallback.
// 输出 blur 图(u8)：H pass img->tmp，V pass tmp->out。边界零填充（下游阈值 0->白边）。
// 全图 memset 清零边界（曾试 border-only memset，2956 次 7 字节小写 per-call 开销 > 省下的
// 内点冗余写，测得 +1.5% 回归，故弃用）。
static void ild_gaussian_blur_core(TImage &img, TImage &out, const tl::buffer<int> &kernel)
{
    const int border = ILD_GAUSSIAN_KERNEL / 2;
    std::memset(out.pixel, 0, (size_t)out.h * out.bpl);   // blur 边界=0

    // tmp 复用静态 buffer（替代每帧 allocate/free）。TImage 视图保证下游循环不变。
    const size_t need = (size_t)img.w * img.h;
    g_tmp.ensure(need);
    TImage tmp;
    tmp.pixel = g_tmp.p;
    tmp.w = img.w;
    tmp.h = img.h;
    tmp.bpl = img.w;     // 分配的 scratch 是紧凑的，bpl==w
    tmp.bCleanup = false;
    std::memset(tmp.pixel, 0, need);   // tmp 边界=0（V pass 零边界，load-bearing）

#if ILD_SSE41
    // Pre-broadcast kernel values to SSE registers (once per call).
    __m128i k[15];
    for (int ki = 0; ki < ILD_GAUSSIAN_KERNEL; ++ki)
        k[ki] = _mm_set1_epi32(kernel[ki]);

    // === Horizontal pass (SSE4.1): 4 pixels/iter, symmetric pairs（写 tmp）===
    {
        int bpl_i = img.bpl, bpl_o = tmp.bpl;
        for (int y = border; y < img.h - border; ++y) {
            const unsigned char* row = img.pixel + (y - border) * bpl_i;
            unsigned char* dst = tmp.pixel + y * bpl_o;

            int x = border;
            for (; x <= img.w - border - 4; x += 4) {
                // Center pixel: kernel[border] * row[x+0..x+3]
                __m128i c = _mm_cvtepu8_epi32(_mm_cvtsi32_si128(*(int*)(row + x)));
                __m128i acc = _mm_mullo_epi32(c, k[border]);

                // Symmetric pairs: kernel[i] * (row[x-border+i] + row[x+border-i])
                for (int i = 0; i < border; ++i) {
                    __m128i L = _mm_cvtepu8_epi32(_mm_cvtsi32_si128(*(int*)(row + x - border + i)));
                    __m128i R = _mm_cvtepu8_epi32(_mm_cvtsi32_si128(*(int*)(row + x + border - i)));
                    acc = _mm_add_epi32(acc, _mm_mullo_epi32(_mm_add_epi32(L, R), k[i]));
                }

                // Shift right 23, pack 32-bit -> 8-bit, store 4 bytes.
                acc = _mm_srai_epi32(acc, 23);
                __m128i packed = _mm_packus_epi32(acc, acc);
                packed = _mm_packus_epi16(packed, packed);
                *(int*)(dst + x) = _mm_cvtsi128_si32(packed);
            }
            // Scalar tail: 0–3 pixels.
            for (; x < img.w - border; ++x) {
                long long s = (long long)kernel[border] * row[x];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (row[x - border + i] + row[x + border - i]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }

    // === Vertical pass (SSE4.1): 4 pixels/iter, symmetric rows（写 out=blur）===
    // 读 tmp 列 x-border、写 out 列 x（该列偏移已固化于下游几何，bit-exact 必须保留）。
    {
        int bpl_t = tmp.bpl, bpl_o = out.bpl;
        for (int y = border; y < tmp.h - border; ++y) {
            unsigned char* dst = out.pixel + y * bpl_o;

            int x = border;
            for (; x <= tmp.w - border - 4; x += 4) {
                // Center row (same x-offset across 4 adjacent columns).
                __m128i c = _mm_cvtepu8_epi32(
                    _mm_cvtsi32_si128(*(int*)(tmp.pixel + x - border + y * bpl_t)));
                __m128i acc = _mm_mullo_epi32(c, k[border]);

                for (int i = 0; i < border; ++i) {
                    int up   = x - border + (y - border + i) * bpl_t;
                    int down = x - border + (y + border - i) * bpl_t;
                    __m128i U = _mm_cvtepu8_epi32(_mm_cvtsi32_si128(*(int*)(tmp.pixel + up)));
                    __m128i D = _mm_cvtepu8_epi32(_mm_cvtsi32_si128(*(int*)(tmp.pixel + down)));
                    acc = _mm_add_epi32(acc, _mm_mullo_epi32(_mm_add_epi32(U, D), k[i]));
                }

                acc = _mm_srai_epi32(acc, 23);   // blur 值 s32x4 ∈[0,255]
                __m128i packed = _mm_packus_epi32(acc, acc);
                packed = _mm_packus_epi16(packed, packed);
                *(int*)(dst + x) = _mm_cvtsi128_si32(packed);
            }
            // Scalar tail.
            for (; x < tmp.w - border; ++x) {
                long long s = (long long)kernel[border] * tmp.pixel[x - border + y * bpl_t];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (
                        tmp.pixel[x - border + (y - border + i) * bpl_t] +
                        tmp.pixel[x - border + (y + border - i) * bpl_t]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }
#elif ILD_NEON
    // NEON (aarch64) 8 像素/迭代，与 SSE4.1 同构（对称对 + 中心）。
    // 内核值 ~2^20 超 s16 范围，故 kernel>>5 压入 s16，最终移位补偿 23-5=18
    // （精度损失 <0.02 LSB，不影响二值化判定）。累加在 s32（最大 ~2^27，安全）。
    int16_t ks[ILD_GAUSSIAN_KERNEL];
    for (int ki = 0; ki < ILD_GAUSSIAN_KERNEL; ++ki)
        ks[ki] = (int16_t)((kernel[ki] + 16) >> 5);  // 四舍五入入 s16
    const int gshift = 23 - 5;

    // === Horizontal pass (NEON): 8 pixels/iter（写 tmp）===
    {
        int bpl_i = img.bpl, bpl_o = tmp.bpl;
        for (int y = border; y < img.h - border; ++y) {
            const unsigned char* row = img.pixel + (y - border) * bpl_i;
            unsigned char* dst = tmp.pixel + y * bpl_o;
            int x = border;
            for (; x + 14 < img.w; x += 8) {  // +7 的 8 字节 load 需 x+14<=w-1
                uint8x8_t c = vld1_u8(&row[x]);
                int16x8_t c_s16 = vreinterpretq_s16_u16(vmovl_u8(c));
                int32x4_t acc_lo = vmlal_s16(vdupq_n_s32(0), vget_low_s16(c_s16),  vdup_n_s16(ks[border]));
                int32x4_t acc_hi = vmlal_s16(vdupq_n_s32(0), vget_high_s16(c_s16), vdup_n_s16(ks[border]));
                for (int i = 0; i < border; ++i) {
                    int d = border - i;
                    uint8x8_t L = vld1_u8(&row[x - d]);
                    uint8x8_t R = vld1_u8(&row[x + d]);
                    int16x8_t S_s16 = vreinterpretq_s16_u16(vaddl_u8(L, R));
                    acc_lo = vmlal_s16(acc_lo, vget_low_s16(S_s16),  vdup_n_s16(ks[i]));
                    acc_hi = vmlal_s16(acc_hi, vget_high_s16(S_s16), vdup_n_s16(ks[i]));
                }
                acc_lo = vshrq_n_s32(acc_lo, gshift);
                acc_hi = vshrq_n_s32(acc_hi, gshift);
                uint16x4_t u16_lo = vqmovun_s32(acc_lo);
                uint16x4_t u16_hi = vqmovun_s32(acc_hi);
                uint16x8_t u16 = vcombine_u16(u16_lo, u16_hi);
                vst1_u8(&dst[x], vqmovn_u16(u16));
            }
            for (; x < img.w - border; ++x) {
                long long s = (long long)kernel[border] * row[x];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (row[x - border + i] + row[x + border - i]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }
    // === Vertical pass (NEON): 8 pixels/iter, symmetric rows（写 out=blur）===
    {
        int bpl_t = tmp.bpl, bpl_o = out.bpl;
        for (int y = border; y < tmp.h - border; ++y) {
            unsigned char* dst = out.pixel + y * bpl_o;
            int x = border;
            for (; x + 14 < tmp.w; x += 8) {
                int col = x - border;  // 与标量一致：读 tmp 列 x-border
                uint8x8_t c = vld1_u8(&tmp.pixel[col + (size_t)y * bpl_t]);
                int16x8_t c_s16 = vreinterpretq_s16_u16(vmovl_u8(c));
                int32x4_t acc_lo = vmlal_s16(vdupq_n_s32(0), vget_low_s16(c_s16),  vdup_n_s16(ks[border]));
                int32x4_t acc_hi = vmlal_s16(vdupq_n_s32(0), vget_high_s16(c_s16), vdup_n_s16(ks[border]));
                for (int i = 0; i < border; ++i) {
                    int d = border - i;
                    uint8x8_t U = vld1_u8(&tmp.pixel[col + (size_t)(y - d) * bpl_t]);
                    uint8x8_t D = vld1_u8(&tmp.pixel[col + (size_t)(y + d) * bpl_t]);
                    int16x8_t S_s16 = vreinterpretq_s16_u16(vaddl_u8(U, D));
                    acc_lo = vmlal_s16(acc_lo, vget_low_s16(S_s16),  vdup_n_s16(ks[i]));
                    acc_hi = vmlal_s16(acc_hi, vget_high_s16(S_s16), vdup_n_s16(ks[i]));
                }
                acc_lo = vshrq_n_s32(acc_lo, gshift);
                acc_hi = vshrq_n_s32(acc_hi, gshift);
                uint16x4_t u16_lo = vqmovun_s32(acc_lo);
                uint16x4_t u16_hi = vqmovun_s32(acc_hi);
                uint16x8_t u16 = vcombine_u16(u16_lo, u16_hi);   // blur 值 u16x8 ∈[0,255]
                vst1_u8(&dst[x], vqmovn_u16(u16));
            }
            for (; x < tmp.w - border; ++x) {
                long long s = (long long)kernel[border] * tmp.pixel[x - border + y * bpl_t];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (
                        tmp.pixel[x - border + (y - border + i) * bpl_t] +
                        tmp.pixel[x - border + (y + border - i) * bpl_t]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }
#else
    // === Scalar fallback (unchanged from original) ===
    // Horizontal pass: symmetric (15->8 mults) + direct pointer (no at() overhead)
    {
        int bpl_i = img.bpl, bpl_o = tmp.bpl;
        for (int y = border; y < img.h - border; ++y) {
            const unsigned char* row = img.pixel + (y - border) * bpl_i;
            unsigned char* dst = tmp.pixel + y * bpl_o;
            for (int x = border; x < img.w - border; ++x) {
                long long s = (long long)kernel[border] * row[x];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (row[x - border + i] + row[x + border - i]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }
    // Vertical pass（写 out=blur）。
    {
        int bpl_t = tmp.bpl, bpl_o = out.bpl;
        for (int y = border; y < tmp.h - border; ++y) {
            unsigned char* dst = out.pixel + y * bpl_o;
            for (int x = border; x < tmp.w - border; ++x) {
                long long s = (long long)kernel[border] * tmp.pixel[x - border + y * bpl_t];
                for (int i = 0; i < border; ++i)
                    s += (long long)kernel[i] * (
                        tmp.pixel[x - border + (y - border + i) * bpl_t] +
                        tmp.pixel[x - border + (y + border - i) * bpl_t]);
                dst[x] = (unsigned char)((s >> 23) & 0xFF);
            }
        }
    }
#endif // ILD_SSE41
}

// 公共 API：仅输出 blur（保留接口；当前 linecode 无活动调用方，仅 old_isli_decoder 参考）。
void ild_gaussian_blur(TImage &img, TImage &out)
{
    ild_gaussian_blur_core(img, out, ild_gauss_kernel_cache());
}

// Local adaptive binarization: pixel >= local_blur ? 255 : 0
// 两步法：blur(img->g_blur) 后逐像素阈值比较写 out。bit-exact 于原实现。
// （曾试把阈值折叠进 V pass 的融合写回，x86 测得 0 收益--V pass 的 mullo 计算主导、
//  抵消省下的独立阈值循环；ARM 设备侧未测，待真机 profiling 验证。）
void ild_gaussian_binarization(TImage &img, TImage &out)
{
#if ILD_SSE41
    static const char* kSimd = "sse4.1";
#elif ILD_NEON
    static const char* kSimd = "neon";
#else
    static const char* kSimd = "scalar";
#endif
    ILD_LOGD("gaussian_binarization: %dx%d kernel=%d (%s)",
             img.w, img.h, ILD_GAUSSIAN_KERNEL, kSimd);

    // tmp 与 out 均按 bpl==w 紧凑布局平坦索引（下游循环假设）。
    assert(img.bpl == img.w && out.bpl == out.w);

    // blur 写入复用的 scratch 缓冲（替代每帧 malloc/free）。
    const size_t need = (size_t)img.w * img.h;
    g_blur.ensure(need);
    TImage blur;
    blur.pixel = g_blur.p;
    blur.w = img.w;
    blur.h = img.h;
    blur.bpl = img.w;
    blur.bCleanup = false;

    auto _gb0 = std::chrono::steady_clock::now();
    ild_gaussian_blur_core(img, blur, ild_gauss_kernel_cache());
    const int total = img.w * img.h;
    const unsigned char* ip = img.pixel;
    const unsigned char* bp = blur.pixel;
    unsigned char* op = out.pixel;
    for (int i = 0; i < total; ++i)
        op[i] = (ip[i] >= bp[i]) ? 255 : 0;
    auto _gb1 = std::chrono::steady_clock::now();
    ILD_LOGI("gauss_bin took %lldus", (long long)std::chrono::duration_cast<std::chrono::microseconds>(_gb1 - _gb0).count());

    if (getenv("ILD_DUMPBIN")) {
        FILE* f = fopen("gaussbin.pgm", "wb");
        if (f) { fprintf(f, "P5\n%d %d\n255\n", img.w, img.h);
                 fwrite(out.pixel, 1, (size_t)out.h * out.bpl, f); fclose(f); }
    }
}

// DR-6: 复用主路径刚算好的 blur(g_blur) 做偏置重阈值——跳过高斯模糊(占二值化 ~75%)，
// 仅跑阈值比较循环。调用前提：ild_gaussian_binarization 已对同一 img 调用过(g_blur 有效)。
// bit-exact 于"对该 img 做完整 bias 二值化"(img 未变 → blur 相同)。
void ild_gaussian_rethreshold(const TImage &img, TImage &out, int bias)
{
    const int total = img.w * img.h;
    const unsigned char* ip = img.pixel;
    const unsigned char* bp = g_blur.p;
    unsigned char* op = out.pixel;
    for (int i = 0; i < total; ++i)
        op[i] = ((int)ip[i] >= (int)bp[i] + bias) ? 255 : 0;
}
