#include "ISLIIconDecoder.h"
#include "ISLIIconLocator.h"
#include "FrameTracer.h"
#include "CornerFinder.h"
#include "CurveSampler.h"
#include "Wave2Bits.h"
#include "bch.h"
#include "buffer.h"
#include "Common.h"
#include "kiss_fft.h"
#include <memory.h>
#include <assert.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#include <QDebug>
#endif


bch_control*   __bch_ctrl63 = 0;
bch_control*   __bch_ctrl127 = 0;

int isli_icon_decoder_init()
{
    if (0 == __bch_ctrl63) {
        __bch_ctrl63 = init_bch(6, 5, 0);
        __bch_ctrl127 = init_bch(7, 7, 0);

        return 1;
    }
    else {
        return 0;
    }
}

int isli_icon_decoder_uninit()
{
    if (__bch_ctrl63) {
        free_bch(__bch_ctrl63);
        __bch_ctrl63 = 0;

        free_bch(__bch_ctrl127);
        __bch_ctrl127 = 0;

        return 1;
    }
    else {
        return 0;
    }
}

#if REMOTE_DRAW
//给四角打上标记
static void mark_corner(double* px, double* py, int corner_pos[4], double frame_width)
{
    double cx = 0, cy = 0;
    for (int i = 0; i < 4; i++){
        cx += px[corner_pos[i]];
        cy += py[corner_pos[i]];
    }
    cx /= 4;
    cy /= 4;
    for (int i = 0; i < 4; i++){
        int k = corner_pos[i];

        double dx = px[k] - cx;
        double dy = py[k] - cy;
        double r = sqrt(dx * dx + dy * dy);
        double d = frame_width * 1.5;
        if (d < 10)
            d = 10;
        double ofstx = d / r * dx;
        double ofsty = d / r * dy;
        char no[2] = { 0 };
        no[0] = (char)('0' + i);

        __canvas.DrawDot("source", "shape=circle;color=0xff;size=6", short(px[k] + 0.5), short(py[k] + 0.5));
        __canvas.DrawText("source", "color=0xff", short(px[k] + ofstx - 4 + 0.5), short(py[k] + ofsty - 8 + 0.5), no);
        //__canvas.DrawLine("source", "color=0xff", cx, cy, short(px[k] + ofstx + 0.5), short(py[k] + ofsty + 0.5));
    }
}
#endif

// ________________________________________________________________________________________________________________________________________________________
//|                                       data                                         |                               ecc                                 |
//|____________________________________________________________________________________|___________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4      |     BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |
//|-_______________|________________|________________|________________|________________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|xxxxxxxxvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvxxxxxxxxxx|
//|________________|________________|________________|________________|________________|________________|________________|________________|________________|
//
// 63bit排列顺序：从BYTE0到BYTE8，每个BYTE内从b0到b7，x表示不使用且固定为0,v为有效bit
static const int PRESET_DATA_ZERO_BITS_START1 = 4;
static const int PRESET_DATA_ZERO_BITS_END1   = 7;
static const int PRESET_ECC_ZERO_BITS_START1  = 64;
static const int PRESET_ECC_ZERO_BITS_END1    = 68;

static void compact_bits(const unsigned char bits[63], unsigned char received[9])
{
    memset(received, 0, 9);

    int k = 0;
    for (int i = 0; i < 8 * 9; i++){
        if ((i >= PRESET_DATA_ZERO_BITS_START1 && i <= PRESET_DATA_ZERO_BITS_END1) || (i >= PRESET_ECC_ZERO_BITS_START1 && i <= PRESET_ECC_ZERO_BITS_END1)) {
            continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
}

static void bits2string(unsigned char bits[5], char str[12])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 5*8; i++) {
        if (i >= PRESET_DATA_ZERO_BITS_START1 && i <= PRESET_DATA_ZERO_BITS_END1) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    for (int i = 0; i < 11; i++) {
        char c = (v % 10) + '0';
        str[10 - i] = c;
        v = v / 10;
    }
    str[11] = 0;
}

static int bits_decode(const unsigned char bits[63], char isli_code[12])
{
    unsigned char received[9] = { 0 };
    unsigned int error_loc[5] = { 0 };
    
    compact_bits(bits, received);

    int err_num = decode_bch(__bch_ctrl63, &received[0], 5, &received[5], 0, 0, error_loc);
    if (err_num >= 0 && err_num <= 2) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            if (((k >= PRESET_DATA_ZERO_BITS_START1) && (k <= PRESET_DATA_ZERO_BITS_END1)) ||
                ((k >= PRESET_ECC_ZERO_BITS_START1) && (k <= PRESET_ECC_ZERO_BITS_END1))){
                return 0;
            }
            received[k >> 3] ^= (1 << (k & 7));
        }

        static const unsigned char zeros[5] = { 0 };
        unsigned char data[5] = { 0 };
        unsigned char ecc[4] = { 0 };
        memcpy(data, received, 5);
        encode_bch(__bch_ctrl63, data, 5, ecc);
        if (0 == memcmp(&received[5], ecc, 4)) {
            if (memcmp(data, zeros, sizeof(data))) {
                bits2string(data, isli_code);
                return 1;
            }
        }
    }

    return 0;
}

// __________________________________________________________________________________________________________________________________________________________________________
//|                                       data， 80bits - 2个x位 - 15个0位 = 63位有效位                                                                                        | 
//|_________________________________________________________________________________________________________________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4       |    BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |     BYTE9      |
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|0000000000000000|0000000000000000|vvvvvvvvvvvvvv00|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|                                       ecc[49bits]                                                   |                |                                 
//|_____________________________________________________________________________________________________|________________|
//|     BYTE10     |     BYTE11     |     BYTE12     |     BYTE13     |     BYTE14      |     BYTE15    |     BYTE16     |
//|________________|________________|________________|________________|_________________|_______________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vv00000000000000|
//|________________|________________|________________|________________|_________________|_______________|________________|
//
// 127bit排列顺序：从BYTE0到BYTE16，每个BYTE内从b0到b7，v为有效bit,0为预设固定值0
static const int PRESET_DATA_ZERO_BITS_START2 = 0;
static const int PRESET_DATA_ZERO_BITS_END2   = 16;
static const int PRESET_ECC_ZERO_BITS_START2  = 48;
static const int PRESET_ECC_ZERO_BITS_END2    = 54;

static void compact_bits2(const unsigned char bits[112], unsigned char received[17])
{
    memset(received, 0, 17);

    int i = 0, k = 0;
    for (i = 0, k = 0; i < 10*8; i++){
        if (i >= PRESET_DATA_ZERO_BITS_START2 &&
            i <= PRESET_DATA_ZERO_BITS_END2) {
            continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
    for (i = 0; i < 7*8; i++){
        if (i >= PRESET_ECC_ZERO_BITS_START2 &&
            i <= PRESET_ECC_ZERO_BITS_END2){
            continue;
        }
        if (bits[k]) {
            int j = 80 + i;
            received[j >> 3] |= (1 << (j & 7));
        }
        k++;
    }
}

static void bits2string2(unsigned char bits[10], char str[20])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 80; i++) {
        if (i >= PRESET_DATA_ZERO_BITS_START2 && i <= PRESET_DATA_ZERO_BITS_END2) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    for (int i = 0; i < 19; i++) {
        char c = (v % 10) + '0';
        str[18 - i] = c;
        v = v / 10;
    }
    str[19] = 0;
}

static int bits_decode2(const unsigned char bits[112], char isli_code[20])
{
    unsigned char received[17] = { 0 };
    unsigned int error_loc[7] = { 0 };

    compact_bits2(bits, received);

    int err_num = decode_bch(__bch_ctrl127, &received[0], 10, &received[10], 0, 0, error_loc);
    if (err_num >= 0 && err_num <= 5) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            if (((k >= PRESET_DATA_ZERO_BITS_START2) && (k <= PRESET_DATA_ZERO_BITS_END2)) ||
                ((k >= PRESET_ECC_ZERO_BITS_START2)  && (k <= PRESET_ECC_ZERO_BITS_END2))){
                return 0;
            }
            received[k >> 3] ^= (1 << (k & 7));
        }

        static const unsigned char zeros[10] = { 0 };
        unsigned char data[10] = { 0 };
        unsigned char ecc[7] = { 0 };
        memcpy(data, received, 10);
        encode_bch(__bch_ctrl127, data, 10, ecc);
        if (0 == memcmp(&received[10], ecc, 7)) {
            if (memcmp(data, zeros, sizeof(data))){
                bits2string2(data, isli_code);
                return 1;
            }
        }
    }

    return 0;
}

static unsigned char get_avg_brightness(IMAGE *image)
{
    unsigned char *pixel = image->pixel;
    size_t len = image->h * image->bpl;
    size_t upper = len - len % 4;
    int sum = 0; // for a 1920x1080 image which is all white, it is sufficient.
    for (size_t i = 0; i < upper; i += 4)
    {
        assert(i + 3 < len);
        sum += pixel[i];
        sum += pixel[i + 1];
        sum += pixel[i + 2];
        sum += pixel[i + 3];
    }
    for (size_t i = upper; i < len; i++)
    {
        assert(i < len);
        sum += pixel[i];
    }
    return (unsigned char)(sum / len);
}

static float hanning_function(float N, float n)
{
    const float PI = 3.1415926535897932384626433832795f;
    float tmp = sin((PI * n) / (N - 1.0f));
    return tmp * tmp;
}

static void hanning_window(size_t len, tl::buffer<float> &window)
{
    window.resize(len);
    for (size_t i = 0; i < len; i++)
    {
        window[i] = hanning_function(len, i);
    }
    //ild_draw_wave2(true, "color=0xff", "hanning", window, 400);
}

static void vertical_scan(IMAGE* image, int x, unsigned char* pline)
{
    unsigned char* psrc = image->pixel + x;
    unsigned char* pdst = pline;
    int bpl = image->bpl;
    int h = image->h;

    for (int v = 0; v < h; v++){
        *pdst++ = *psrc;
        psrc += bpl;
    }
}

static void horizontal_scan(IMAGE* image, int y, unsigned char* pline)
{
    unsigned char *p = image->pixel + y * image->bpl;
    memcmp(pline, p, image->bpl);
}

static float calc_line_fft(tl::buffer<Byte> &line, tl::buffer<float> &window, const char *graph_name)
{
    UNREFERENCED_PARAMETER(graph_name);

    tl::buffer<kiss_fft_cpx> fft_in;
    fft_in.resize(line.size());

    for (size_t i = 0; i < line.size(); i++)
    {
        fft_in[i].r = line[i] / 255.0f * window[i];
        fft_in[i].i = 0;
    }
    kiss_fft_cfg cfg = kiss_fft_alloc((int)fft_in.size(), 0, 0, 0);
    tl::buffer<kiss_fft_cpx> fft_out;
    fft_out.resize(fft_in.size());
    kiss_fft(cfg, fft_in.data(), fft_out.data());

    //ILDLOG("frequency_bin: %f", fft_out[0].r);
    tl::buffer<float> amplitude;
    amplitude.reserve(fft_out.size());
    for (size_t i = 1; i < fft_out.size(); i++)
    {
        auto cpx = fft_out[i];
        amplitude.push_back(sqrt(cpx.r * cpx.r + cpx.i * cpx.i));
    }
    float sum2 = 0;
    size_t margin = (size_t)(amplitude.size() * 0.03125); // old: 0.021875
    for (size_t i = margin; i < amplitude.size() - margin; i++)
    {
        sum2 += amplitude[i];
    }
    //ILDLOG("fft_sum: %.2f", sum2);

#if REMOTE_DRAW
    //ild_draw_wave2(true, "color=0xff", graph_name, amplitude, 700);
#endif

    kiss_fft_free(cfg);
    return sum2;
}

static float is_image_blur(IMAGE *img)
{
    tl::buffer<float> window;
    hanning_window(img->h, window);

    tl::buffer<Byte> line;
    line.resize(img->h);

    float max = 0;
    for (int i = 1; i <= 3; i++)
    {
        int x = img->w * i / 4;
        vertical_scan(img, x, line.data());
        float ret = calc_line_fft(line, window, "fft1");
        if (ret > max)
            max = ret;
    }
    hanning_window(img->w, window);
    line.resize(img->w);
    for (int i = 1; i <= 3; i++)
    {
        int y = img->h * i / 4;
        horizontal_scan(img, y, line.data());
        float ret = calc_line_fft(line, window, "fft2");
        if (ret > max)
            max = ret;
    }
    return max;
}

int isli_icon_decoder_do_image_decode(IMAGE* image, char isli_code[MAX_DECODE_ISLI_CODE_LEN],
    short feax[MAX_FEATURE_POINT_NUM], short feay[MAX_FEATURE_POINT_NUM], int *brightness, int *is_blur)
{
    int ret = 0;

    memset(isli_code, 0, MAX_DECODE_ISLI_CODE_LEN);
    if (0 == __bch_ctrl63){
        return 0;
    }

    *brightness = get_avg_brightness(image);
    if (*brightness < 40) {
        *is_blur = 1;
        return 0;
    }
    if (is_image_blur(image) < ILD_BLUR_THRESHOLD)
    {
        ILDLOG("is_blur");
        *is_blur = 1;
        return 0;
    }

    //定位isli icon
    int x1, y1, x2, y2;
    double frame_size; //for debug 
    ret = do_isliicon_locating(image, &x1, &y1, &x2, &y2, &frame_size);
    if (!ret){
        return 0;
    }
#if REMOTE_DRAW
    __canvas.DrawLine("source", "color=0xff", (short)x1, (short)y1, (short)x2, (short)y2);
#endif
    feax[4] = (short)x1;
    feay[4] = (short)y1;
    feax[5] = (short)x2;
    feay[5] = (short)y2;

    //外框追踪
    static const int MAX_DOT_NUM = 88 * 3;
    double* px = new double[MAX_DOT_NUM];
    double* py = new double[MAX_DOT_NUM];
    int dot_num = MAX_DOT_NUM;
    ret = do_trace_frame2(image, x1, y1, x2, y2, frame_size, px, py, &dot_num);
    if (!ret || dot_num < 44) { // origin: 88
        delete[] px;
        delete[] py;
        return 0;
    }

    //定位外框的四角，将外框追踪点分为4段
    int corner_pos[4];
    int is_clockwise = 0;
    is_clockwise = do_corner_finder(px, py, dot_num, corner_pos);
    finetune_corners(image, px, py, dot_num, corner_pos, frame_size, is_clockwise);
#if REMOTE_DRAW
    mark_corner(px, py, corner_pos, frame_size);
#endif
    for (int i = 0; i < 4; i++){
        feax[i] = short(px[corner_pos[i]] + 0.5);
        feay[i] = short(py[corner_pos[i]] + 0.5);
    }

    //逐段拟合曲线，采样波形
    int one_curve_len = max_curve_length();
    unsigned char* curve_buffer = new unsigned char[(size_t)(one_curve_len * 4)];
    unsigned char* pcurve[4] = { 0 };
    int            curve_len[4] = { 0 };
    
    for (int i = 0; i < 4; i++){
        pcurve[i] = curve_buffer + i * one_curve_len;
        curve_len[i] = one_curve_len;
    }
    
    if (do_curve_sample(image, px, py, dot_num, corner_pos, is_clockwise, pcurve, curve_len)){
        unsigned char bits[112];

        do_wave2bits63(pcurve, curve_len, bits);
        if (bits_decode(bits, isli_code)){
            ret = 1;
        }
        else{   
            do_wave2bits112(pcurve, curve_len, bits);
            if (bits_decode2(bits, isli_code)) {
                ret = 1;
            }
            else {
                ret = 0;
            }
        }
    }
    delete[] px;
    delete[] py;
    delete[] curve_buffer;

    return ret;
}

