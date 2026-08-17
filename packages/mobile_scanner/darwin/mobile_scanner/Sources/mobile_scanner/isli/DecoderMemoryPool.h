#ifndef __DECODERMEMORYPOOL_H__
#define __DECODERMEMORYPOOL_H__

// Decoder memory pool - pre-allocated buffers to eliminate per-frame heap allocs
// All buffers are used sequentially across pipeline stages (no concurrency)

struct DecoderMemoryPool {
    // Constants - use literal values for MSVC array-size compatibility
    static const int MAX_IMAGE_DIM = 4096;
    static const int MAX_CURVE_LEN = 1152;  // 128 * 9 (MAX_SPAN * SAMPLES_PER_SPAN)
    static const int MAX_DOTS      = 264;   // 88 * 3
    static const int MAX_PATCH_DIM = 128;

    // === Large shared scratch buffers (sequentially reused across stages) ===
    unsigned char scratch_uchar[4096];
    int           scratch_int[4096];
    double        scratch_double[4096 * 2];

    // === FrameTracer ===
    double px[264];
    double py[264];

    // === CurveSampler ===
    unsigned char curve_buf[1152 * 4];
    unsigned char filtered_buf[1152 * 4];

    // === CurveFit ===
    double fit_xx[264];
    double fit_yy[264];
    double fit_nx[264];
    double fit_ny[264];

    // === Wave2Bits ===
    unsigned char wave_bin[1152];
    int           wave_score[1152];

    // === CornerFinder ===
    int angle_buf[264];

    // === CornerFinetuner ===
    unsigned char bw_patch[128 * 128];
    long long     score_patch[128 * 128];
    unsigned char smooth_patch[192 * 192];  //预计算 3×3 均值区域（corner_score 加速）

    // === Binarization ===
    unsigned short bs_buf[4096 / 4];

    // === ISLIIconLocator ===
    unsigned char vert_scan_buf[4096];
    unsigned char skew_wave_buf[4096 * 2];
    unsigned char binarize_th_buf[4096];
};

// Global pool pointer, lifecycle managed by isli_icon_decoder_init/uninit
extern DecoderMemoryPool* g_pool;

#endif
