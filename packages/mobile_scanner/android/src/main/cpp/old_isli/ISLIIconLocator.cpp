#include "ISLIIconLocator.h"
#include "Filter.h"
#include "Binarization.h"
#include "BSPatternMatch.h"
#include "LineScanner.h"
#include <math.h>
#include <assert.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#endif

static const int MIN_EDGE = 40;       //标志码中ISLI字符离开图像的最小边界
static const int SCAN_LINE_DIS = 15;  //扫描线间距
static const int SKEW_SCAN_DIS = 11;  //45°扫描时扫描线间距dx、dy值

static int locate_in_line(unsigned char* gray_line, int line_len, int* pos1, int* pos2, double* frame_size)
{
    //unsigned char* filtered = new unsigned char[line_len];
    //do_low_pass_filter(gray_line, line_len, filtered);

    //__canvas.DrawImage("profile", "null", line_len, 256, 0, 0);
    //for (int s = 1; s < line_len; s++) {
    //    __canvas.DrawLine("profile", "color=0xff00", s, 256 - (gray_line[s]), s - 1, 256 - (gray_line[s - 1]));
    //}
    //for (int s = 1; s < line_len; s++) {
    //    __canvas.DrawLine("profile", "color=0xff", s, 256 - (filtered[s]), s - 1, 256 - (filtered[s - 1]));
    //}

    unsigned short* bs = new unsigned short[(size_t)line_len / 4];
    int bs_num = do_binarizaiton(gray_line, line_len, bs, line_len / 4);
    
    int r = do_bspatternmatch_hollow1(bs, bs_num, pos1, pos2, frame_size);

    if (!r) {
        r = do_bspatternmatch_hollow2(bs, bs_num, pos1, pos2, frame_size);
    }
    if (!r) {
        r = do_bspatternmatch_hollow3(bs, bs_num, pos1, pos2, frame_size);
    }
    if (!r) {
        r = do_bspatternmatch(bs, bs_num, pos1, pos2, frame_size);
    }
    
    //delete[] filtered;
    delete[] bs;

    return r;
}

static int do_horizontal_locating(IMAGE* image,
                                  int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    int y = image->h / 2;
    int step = SCAN_LINE_DIS;

    int k = 0;
    while (y >= MIN_EDGE && y < image->h - MIN_EDGE) {
        y = image->h / 2 + k * step;
        if (y >= image->h - MIN_EDGE){
            break;
        }
        if (locate_in_line(image->pixel + y * image->bpl, image->w, x1, x2, frame_size)) {
            *y1 = *y2 = y;
            return 1;
        }
        
        if (0 == k) {
            k++;
            continue; //第一次扫描
        }
        y = image->h / 2 - k * step;
        if (y < MIN_EDGE){
            break;
        }
        if (locate_in_line(image->pixel + y * image->bpl, image->w, x1, x2, frame_size)) {
            *y1 = *y2 = y;
            return 1;
        }
        k++;
    }

    return 0;
}


static int do_vertical_locating(IMAGE* image,
                                int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    unsigned char* pline = new unsigned char[(size_t)image->h];

    int ret = 0;
    int x = image->w / 2;
    int step = SCAN_LINE_DIS;

    int k = 0;
    while (x >= MIN_EDGE && x < image->w - MIN_EDGE) {
        x = image->w / 2 + k * step;
        if (x >= image->w - MIN_EDGE){
            break;
        }
        do_vertical_scan(image, x, pline);
        if (locate_in_line(pline, image->h, y1, y2, frame_size)) {
            *x1 = *x2 = x;
            ret = 1;
            break;
        }
        if (0 == k) {
            k++;
            continue; //第一次扫描
        }
        
        x = image->w / 2 - k * step;
        if (x < MIN_EDGE){
            break;
        }
        do_vertical_scan(image, x, pline);
        if (locate_in_line(pline, image->h, y1, y2, frame_size)) {
            *x1 = *x2 = x;
            ret = 1;
            break;
        }
        k++;
    }

    delete[] pline;

    return ret;
}

static SKEW_LINE* create_45degree_lines(int w, int h, int* len)
{
    static const int MARGIN = 150;
    double dx = 1 / sqrt(2.0);
    double dy = dx;

    int scan_line_num = (w - MARGIN) / SKEW_SCAN_DIS + (h - MARGIN) / SKEW_SCAN_DIS + 2;

    SKEW_LINE* lines = new SKEW_LINE[(size_t)scan_line_num];
    int edge = w < h ? w : h;
    lines[0].sx = 0;
    lines[0].sy = 0;
    lines[0].dx = dx;
    lines[0].dy = dy;
    lines[0].len = int(edge * sqrt(2.0));

    int end0 = 0;
    int end1 = 0;
    int i = 1;
    int k = 1;
    while (k < scan_line_num){
        int sx = 0;
        int sy = i * SKEW_SCAN_DIS;
        int ex = h - 1 - sy;
        if (ex > w - 1){
            ex = w - 1;
        }
        int ey = ex + sy;
        if (ey >= h - 1) {
            ey = h - 1;
        }
        int m = ex - sx;
        int n = ey - sy;
        if (sy + MARGIN < h) {
            lines[k].len = int(sqrt(double(m * m + n * n)));
            lines[k].sx = sx;
            lines[k].sy = sy;
            lines[k].dx = dx;
            lines[k].dy = dy;
            k++;

            //__canvas.DrawLine("source", "color=0xff", sx, sy, ex, ey);
        }
        else{
            end0 = 1;
        }

        sx = i * SKEW_SCAN_DIS;
        sy = 0;
        ey = w - 1 - sx;
        if (ey > h - 1){
            ey = h - 1;
        }
        ex = ey + sx;
        if (ex > w - 1){
            ex = w - 1;
        }
        m = ex - sx;
        n = ey - sy;
        if (w - sx > MARGIN) {
            lines[k].len = int(sqrt(double(m * m + n * n)));
            lines[k].sx = sx;
            lines[k].sy = sy;
            lines[k].dx = dx;
            lines[k].dy = dy;
            k++;

            //__canvas.DrawLine("source", "color=0xff", sx, sy, ex, ey);
        }
        else {
            end1 = 1;
        }
        if (end1 && end0)
            break;
        i++;
    }
    assert(k <= scan_line_num);
    *len = k;

    return lines;
}

static SKEW_LINE* create_135degree_lines(int w, int h, int* len)
{
    static const int MARGIN = 150;
    double dx = 1 / sqrt(2.0);
    double dy = dx;

    int scan_line_num = (w - MARGIN) / SKEW_SCAN_DIS + (h - MARGIN) / SKEW_SCAN_DIS + 2;

    SKEW_LINE* lines = new SKEW_LINE[(size_t)scan_line_num];
    int edge = w < h ? w : h;
    lines[0].sx = 0;
    lines[0].sy = h - 1;
    lines[0].dx = dx;
    lines[0].dy = -dy;
    lines[0].len = int(edge * sqrt(2.0));

    int end0 = 0;
    int end1 = 0;
    int i = 1;
    int k = 1;
    while (k < scan_line_num){
        int sx = 0;
        int sy = h - 1 - i * SKEW_SCAN_DIS;
        int ex = sy;
        int ey = 0;
        if (ex >= w) {
            ey = ex - (w - 1);
            ex = w - 1;
        }
        int m = ex - sx;
        int n = ey - sy;
        if (sy > MARGIN) {
            lines[k].len = int(sqrt(double(m * m + n * n)));
            lines[k].sx = sx;
            lines[k].sy = sy;
            lines[k].dx = dx;
            lines[k].dy = -dy;
            k++;
#if REMOTE_DRAW
            __canvas.DrawLine("source", "color=0xff", sx, sy, ex, ey);
#endif
        }
        else{
            end0 = 1;
        }

        sx = i * SKEW_SCAN_DIS;
        sy = h - 1;
        ex = h - 1 + sx;
        ey = 0;
        if (ex >= w) {
            ey = ex - (w - 1);
            ex = w - 1;
        }
        m = ex - sx;
        n = ey - sy;
        if (w - sx > MARGIN) {
            lines[k].len = int(sqrt(double(m * m + n * n)));
            lines[k].sx = sx;
            lines[k].sy = sy;
            lines[k].dx = dx;
            lines[k].dy = -dy;
            k++;
#if REMOTE_DRAW
            __canvas.DrawLine("source", "color=0xff", sx, sy, ex, ey);
#endif
        }
        else {
            end1 = 1;
        }
        if (end1 && end0)
            break;
        i++;
    }
    assert(k <= scan_line_num);
    *len = k;

    return lines;
}

static int do_skew_locating(IMAGE* image, SKEW_LINE* lines, int line_num,
    int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    int ret = 0;

    unsigned char* wave = 0;
    int wave_len = 0;

    for (int i = 0; i < line_num; i++){
        if (0 == wave || lines[i].len > wave_len) {
            delete[] wave;
            wave = new unsigned char[(size_t)(lines[i].len)];
            wave_len = lines[i].len;
        }
        do_skew_scan(image, &lines[i], wave);

        int a = 0, b = 0;
        if (locate_in_line(wave, wave_len, &a, &b, frame_size)) {
            *x1 = int(lines[i].sx + lines[i].dx * a + 0.5);
            *y1 = int(lines[i].sy + lines[i].dy * a + 0.5);
            *x2 = int(lines[i].sx + lines[i].dx * b + 0.5);
            *y2 = int(lines[i].sy + lines[i].dy * b + 0.5);
            ret = 1;
            break;
        }
    }
    delete[] wave;

    return ret;
}

int do_isliicon_locating(IMAGE* image,
    int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    int ret = 0;

    ret = do_horizontal_locating(image, x1, y1, x2, y2, frame_size);
    if (ret) {
        return ret;
    }

    ret = do_vertical_locating(image, x1, y1, x2, y2, frame_size);
    if (ret) {
        return ret;
    }

    int line_num = 0;
    SKEW_LINE* lines = create_45degree_lines(image->w, image->h, &line_num);
    ret = do_skew_locating(image, lines, line_num, x1, y1, x2, y2, frame_size);
    delete[] lines;
    if (ret) {
        return ret;
    }

    line_num = 0;
    lines = create_135degree_lines(image->w, image->h, &line_num);
    ret = do_skew_locating(image, lines, line_num, x1, y1, x2, y2, frame_size);
    delete[] lines;
    if (ret) {
        return ret;
    }

    return 0;
}

