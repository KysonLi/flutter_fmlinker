#include "FrameTracer.h"
#include "CircleArea.h"
#include "Common.h"
#include "BresenhamLine.h"
#include <math.h>
#include <memory.h>

#ifdef REMOTE_DRAW
#undef REMOTE_DRAW
#endif
#define REMOTE_DRAW 1
#if REMOTE_DRAW
#include "canvas.h"
#endif
#include <stdlib.h>
#include <assert.h>

#define ROUND2INT(x) ((x) >= 0 ? int((x) + 0.5) : int((x) - 0.5))


//调用者保证CircleArea覆盖的pixel没有超出图像边界
static void calc_center_shift(IMAGE* img,
                              double ini_cx, double ini_cy, CircleArea* ca,
                              double* dx, double* dy)
{
    long sum = 0;
    long avg = 0;
    long th = 0;
    int ox = ROUND2INT(ini_cx);
    int oy = ROUND2INT(ini_cy);
    for (int y = -ca->r, i = 0; y <= ca->r; y++, i++) {
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + (oy + y) * img->bpl + (ox + x);
        for (int j = 0; j < len; j++){
            sum += *ppixel++;
#if REMOTE_DRAW
            __canvas.DrawDot("source", "color=0xff0000", x + ini_cx + j, y + ini_cy);
#endif
        }
    }
    avg = sum / ca->area;
    th = ROUND2INT(avg * 1.2);

    int cx = 0;
    int cy = 0;
    int cnt = 0;
    for (int y = -ca->r, i = 0; y <= ca->r; y++, i++) {
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + (oy + y) * img->bpl + (ox + x);
        for (int j = 0 ; j < len; j++){
            if (*ppixel++ <= th) {
                cx += (x + j);
                cy += y;
                cnt++;

#if REMOTE_DRAW
                __canvas.DrawDot("source", "color=0x00", x + ox + j, y + oy);
#endif
            }
            else {
#if REMOTE_DRAW
                __canvas.DrawDot("source", "color=0xffffff", x + ox + j, y + oy);
#endif
            }
        }
    }
    
    *dx = (double)cx / cnt;
    *dy = (double)cy / cnt;
}

static int amend_center(IMAGE* image,
    double ini_cx, double ini_cy, CircleArea* ca,
    double* out_cx, double* out_cy)
{
    double dx, dy;

    static const int MAX_TRY = 3;
    double T = ca->r / 8;

    if (T < 1) {
        T = 1;
    }

    for (int i = 0; i < MAX_TRY; i++) {
        if (ROUND2INT(ini_cx) < ca->r || ROUND2INT(ini_cx) + ca->r >= image->w ||
            ROUND2INT(ini_cy) < ca->r || ROUND2INT(ini_cy) + ca->r >= image->h)
            break;

        calc_center_shift(image, ini_cx, ini_cy, ca, &dx, &dy);
       
        if (dx <= T && dx >= -T &&
            dy <= T && dy >= -T) {
            *out_cx = ini_cx + dx;
            *out_cy = ini_cy + dy;
#if REMOTE_DRAW
            __canvas.DrawDot("source", "color=0xff00", ROUND2INT(*out_cx), ROUND2INT(*out_cy));
#endif
            return 1;
        }
        else {
            ini_cx += dx;
            ini_cy += dy;
#if REMOTE_DRAW
            __canvas.DrawDot("source", "color=0xff", ROUND2INT(ini_cx), ROUND2INT(ini_cy));
#endif
        }
    }

    return 0;
}

static void calc_step(int x0, int y0, int x1, int y1, double step, double* dx, double *dy)
{
    int xx = x1 - x0;
    int yy = y1 - y0;

    double r = sqrt((double)(xx*xx + yy * yy));
    *dx = step * yy / r;
    *dy = step * xx / r;

    if (xx >= 0) {
        if (yy > 0) {
            *dx = -*dx;
        }
    }
    else {
        if (yy < 0){
            *dx = -*dx;
        }
    }
}

static const int MAX_BUFFER = 490;

typedef struct _ScanAdjustData {
    IMAGE *image;
    unsigned char buffer[MAX_BUFFER];
    int count;
    unsigned char avg;
    int sum_x;
    int sum_y;
    int black_count;
} ScanAdjustData;

void init_scan_adjust_data(ScanAdjustData *data)
{
    data->image = NULL;
    memset(data->buffer, 0, MAX_BUFFER);
    data->count = 0;
    data->avg = 0;
    data->sum_x = 0;
    data->sum_y = 0;
    data->black_count = 0;
}

#define GET_PIXEL(image, x, y) (*((image)->pixel + ((y) * (image)->bpl) + (x)))
#define IS_ZERO(d) ((d) < 0.000001 && (d) > -0.000001)

static int get_pixel_avg_cb(int x, int y, void *ud)
{
    ScanAdjustData *data = (ScanAdjustData *)ud;
    IMAGE *image = data->image;
    if (x < 0 || x >= image->w || y < 0 || y >= image->h)
        return 0;
    //__canvas.DrawDot("source", "color=0x00ff00", x, y);
    unsigned char pixel = GET_PIXEL(image, x, y);
    assert(data->count < MAX_BUFFER);
    if (data->count >= MAX_BUFFER)
        return 0;
    data->buffer[data->count ++] = pixel;
    return 1;
}

static int find_center_cb(int x, int y, void *ud)
{
    ScanAdjustData *data = (ScanAdjustData *)ud;
    IMAGE *image = data->image;
    if (x < 0 || x >= image->w || y < 0 || y >= image->h)
        return 0;
    unsigned char pixel = GET_PIXEL(image, x, y);

    if (pixel < data->avg)
    {
        data->sum_x += x;
        data->sum_y += y;
        data->black_count ++;
    }
    return 1;
}

static int scan_triangle(double ini_cx, double ini_cy, double frame_width, double angle, 
    draw_pixel_callback_t callback, void *userdata)
{
    double da = 1.2; // 75 度
    //const double STEP = 2.3094010767585030580365951220078; // 隔行扫描
    double r = (frame_width * 1.2) / sin(da);
    double a = cos(da) * r;
    int x1, y1, x2, y2;
    //int octant;
    for (int i = 0; i < 5; i++)
    {
        x1 = ROUND2INT(r * cos(angle - da) + ini_cx);
        y1 = ROUND2INT(-r * sin(angle - da) + ini_cy); //因为数学里y向上增长 计算机里y向下增长
        x2 = ROUND2INT(r * cos(angle + da) + ini_cx);
        y2 = ROUND2INT(-r * sin(angle + da) + ini_cy);
#if REMOTE_DRAW
        __canvas.DrawLine("source", "color=0x0000ff", x1, y1, x2, y2);
#endif
        if (!bresenham_line(x1, y1, x2, y2, callback, userdata))
            return 0;
        //octant = get_octant(x1, -y1, x2, -y2);
        a += 2.0;
        da = acos(a / r);
        if (isnan(da) || isinf(da))
            break;
    }
    //ILDLOG("octant: %d", octant);
    return 1;
}

static int amend_center2(IMAGE* image,
    double ini_cx, double ini_cy, double frame_width, double *angle,
    double* out_cx, double* out_cy)
{
    UNREFERENCED_PARAMETER(image);
    UNREFERENCED_PARAMETER(out_cx);
    UNREFERENCED_PARAMETER(out_cy);

    int times = 0;
    double last_cx = ini_cx;
    double last_cy = ini_cy;
    int ret = 1;

    do {
        ScanAdjustData data;
        init_scan_adjust_data(&data);
        data.image = image;

        if (!scan_triangle(ini_cx, ini_cy, frame_width, *angle, get_pixel_avg_cb, &data))
        {
            ret = 0;
            break;
        }
    
        int sum = 0;
        for (int i = 0; i < data.count; i++)
        {
            sum += data.buffer[i];
        }
        if (data.count == 0)
        {
            ret = 0;
            break;
        }
        unsigned char avg = sum / data.count;
//        ILDLOG("count: %d avg: %d", data.count, avg);

        data.avg = avg;

        if (!scan_triangle(ini_cx, ini_cy, frame_width, *angle, find_center_cb, &data))
        {
            ret = 0; 
            break;
        }

        if (data.black_count == 0)
        {
            ret = 0;
            break;
        }
        *out_cx = (double)data.sum_x / (double)data.black_count;
        *out_cy = (double)data.sum_y / (double)data.black_count;
#if REMOTE_DRAW
        __canvas.DrawDot("source", "shape=plus;color=0x0000ff;size=3", (short)*out_cx, (short)*out_cy);
#endif

        if (fabs(*out_cx - last_cx) < 1.0 && fabs(*out_cy - last_cy) < 1.0) {
            break;
        }
        double dx = *out_cx - ini_cx;
        double dy = *out_cy - ini_cy;
        // http://en.cppreference.com/w/cpp/numeric/math/atan2
        *angle = atan2(-dy, dx);
        last_cx = *out_cx;
        last_cy = *out_cy;
        times ++;
    } while (times < 5);

    return ret;
}

int do_trace_frame2(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                   double* px, double* py, int* dot_num)
{
    UNREFERENCED_PARAMETER(sx1);
    UNREFERENCED_PARAMETER(sy1);
    const double PI = 3.1415926535897932384626433832795;
    double angle = PI * 1.5; //(double)rand() / (double)RAND_MAX * PI * 2.0;
    //double degree = angle / PI * 180;
    //ILDLOG("degree: %.2f", degree);

    double amended_cx = 0;
    double amended_cy = 0;
    double ini_cx = sx0;
    double ini_cy = sy0;

    double step = frame_width / 3;
    double dx = 0;
    double dy = 0;

    double last_cx = ini_cx;
    double last_cy = ini_cy;
    double cur_cx = ini_cx + dx;
    double cur_cy = ini_cy + dy;
    int succ = 1;
    int cnt = 1;

    px[0] = ini_cx;
    py[0] = ini_cy;
    while (succ) {
        succ = amend_center2(image, cur_cx, cur_cy, frame_width, &angle, &amended_cx, &amended_cy);
        px[cnt] = amended_cx;
        py[cnt] = amended_cy;
        cnt++;
        if (cnt >= *dot_num){
            //轨迹追踪脱轨了
            succ = false;
            break;
        }

        if (succ) {
#if REMOTE_DRAW
            __canvas.DrawDot("source", "shape=corss;color=0xff;size=4", amended_cx, amended_cy);
#endif
            dx = amended_cx - last_cx;
            dy = amended_cy - last_cy;

            if (0 == dx && 0 == dy){
                //循环了！
                succ = false;
                break;
            }
            
            double L = dx * dx + dy * dy;
            dx = dx * step / sqrt(L);
            dy = dy * step / sqrt(L);
            cur_cx = amended_cx + dx;
            cur_cy = amended_cy + dy;
            last_cx = cur_cx;
            last_cy = cur_cy;

            double a = ini_cx - cur_cx;
            double b = ini_cy - cur_cy;
            if (cnt > 10 && fabs(a) < frame_width && fabs(b) < frame_width){
                *dot_num = cnt;
                break;
            }
        }
    }
    ILDLOG("tracing count: %d", cnt);
    return succ;
}

int do_trace_frame(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                   double* px, double* py, int* dot_num)
{
    CircleArea ca;
    init_CircleArea(&ca, (short)ROUND2INT(frame_width * 1.1));

    double amended_cx = 0;
    double amended_cy = 0;
    double ini_cx = sx0;
    double ini_cy = sy0;
    if (amend_center(image, ini_cx, ini_cy, &ca, &amended_cx, &amended_cy)) {
        ini_cx = amended_cx;
        ini_cy = amended_cy;
    }
    else {
        return 0;
    }

    double step = frame_width / 2;
    double dx = 0;
    double dy = 0;
    calc_step(sx0, sy0, sx1, sy1, step, &dx, &dy);

    double last_cx = ini_cx;
    double last_cy = ini_cy;
    double cur_cx = ini_cx + dx;
    double cur_cy = ini_cy + dy;
    int succ = 1;
    int cnt = 1;

    px[0] = ini_cx;
    py[0] = ini_cy;
    while (succ) {
        succ = amend_center(image, cur_cx, cur_cy, &ca, &amended_cx, &amended_cy);
        px[cnt] = amended_cx;
        py[cnt] = amended_cy;
        cnt++;
        if (cnt >= *dot_num){
            //轨迹追踪脱轨了
            succ = false;
            break;
        }

        if (succ) {
            //__canvas.DrawDot("source", "shape=corss;color=0xff;size=4", amended_cx, amended_cy);
            dx = amended_cx - last_cx;
            dy = amended_cy - last_cy;

            if (0 == dx && 0 == dy){
                //循环了！
                succ = false;
                break;
            }

            double L = dx * dx + dy * dy;
            dx = dx * step / sqrt(L);
            dy = dy * step / sqrt(L);
            cur_cx = amended_cx + dx;
            cur_cy = amended_cy + dy;
            last_cx = amended_cx;
            last_cy = amended_cy;

            double a = ini_cx - cur_cx;
            double b = ini_cy - cur_cy;
            if (cnt > 10 && -step < a && a < step && -step < b && b < step){
                *dot_num = cnt;
                break;
            }
        }
    }
    uninit_CircleArea(&ca);

    return succ;
}

