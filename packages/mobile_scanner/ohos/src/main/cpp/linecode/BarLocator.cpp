#include "BarLocator.h"
#include "ISLILineDecoder.h"
#include "BSPatternMatch.h"
#include "CurveSampler.h"

#include <cmath>
#include <array>

static const int MIN_EDGE = 0;       //标志码中ISLI字符离开图像的最小边界
static const int SCAN_LINE_DIS = 8;  //扫描线间距（5→8：扫描列数 -37%；条码单元 ~20px，8px 间距仍每条采样 2+ 次，无混叠）
static const int LOCATING_ENOUGH = 64; // 逐列扫描采到足够定位点即提前停止（rotate_and_detect 实际只需 ~30 点）
static const int SKEW_SCAN_DIS = 5;  //45°扫描时扫描线间距dx、dy值
static const int BUCKET_SIZE = 8;

static void dummy_binarization(unsigned char* gray_line, int gray_len, std::vector<unsigned short> &bs)
{
    bs.reserve((size_t)gray_len / 4);
    int sign = +1; // +1 白 -1 黑
    int k = 0;

    for (int i = 0; i < gray_len; i++)
    {
        if (sign > 0)
        {
            if (0 == gray_line[i])
            {
                sign = -1;
                bs.push_back(k);
                k = 1;
                continue;
            }
        }
        else
        {
            if (0 != gray_line[i])
            {
                sign = +1;
                bs.push_back(k);
                k = 1;
                continue;
            }
        }
        k++;
    }
    bs.push_back(k);
}

template<typename T>
static double standard_deviation(std::vector<T> &data)
{
    double sum = 0.0;
    for (auto i : data)
    {
        sum += i;
    }
    double mean = sum / data.size();

    sum = 0.0;
    for (auto i : data)
    {
        sum += (i - mean) * (i - mean);
    }
    return sqrt(sum / data.size());
}

static double rotate_angle(std::vector<point_t> &pat_vec, double width, double angle, int &max_i)
{
    auto cosa = cos(angle);
    auto sina = sin(angle);

    const int bucket_num = static_cast<int>(1.414 * width) / BUCKET_SIZE + 1;
    // Hoist the histogram buffer out of the ~381-iter angle sweep in
    // rotate_and_detect(): a fresh std::vector per rotate_angle() call meant
    // ~381 heap alloc/free cycles per vertical_locating (the #2 decode hotspot
    // after gaussian). Reuse one thread-local buffer, zeroed each call —
    // bit-exact vs the original fresh resize (which value-init'd to 0).
    static thread_local std::vector<int> buckets;
    buckets.assign(bucket_num, 0);

    for (auto &pat : pat_vec)
    {
        double x1 = pat.x - width / 2.0;
        double y1 = pat.y - width / 2.0;
        double x2 = x1 * cosa + y1 * sina;
        size_t i = (int)x2 / BUCKET_SIZE + bucket_num / 2;
        if (i >= buckets.size())
            continue;
        buckets[i] ++;
    }

    //const int graph_h = 100;
    //__canvas.DrawImage("rotate", "null", bucket_num, graph_h, 0, 0);
    //for (size_t i = 0; i < buckets.size(); i++)
    //{
    //    __canvas.DrawLine("rotate", "color=0x000000", i, graph_h - buckets[i], i, graph_h);
    //}

    double std_dev = standard_deviation<int>(buckets);

    int max = 0;
    max_i = 0;
    for (size_t i = 0; i < buckets.size(); i++)
    {
        if (buckets[i] > max)
        {
            max = buckets[i];
            max_i = (int)i;
        }
    }
    //qDebug() << "std-dev" << std_dev;
    return std_dev;
}

static void filter_dot_in_line(std::vector<point_t> &input, std::vector<point_t> &output,
    double width, double angle, int idx)
{
    auto cosa = cos(angle);
    auto sina = sin(angle);

    const int bucket_num = static_cast<int>(1.414 * width) / BUCKET_SIZE + 1;

    for (auto &pat : input)
    {
        double x1 = pat.x - width / 2.0;
        double y1 = pat.y - width / 2.0;
        double x2 = x1 * cosa + y1 * sina;
        int i = (int)x2 / BUCKET_SIZE + bucket_num / 2;
        if (i == idx)
        {
            output.push_back(pat);
        }
    }
}

static double point_distance(point_t &a, point_t &b)
{
    double dx = b.x - a.x;
    double dy = b.y - a.y;
    return sqrt(dx * dx + dy * dy);
}

static void filter_isolated(std::vector<point_t> &input, std::vector<point_t> &output, point_t center)
{
    std::vector<bool> removed;
    removed.resize(input.size());
    output.reserve(input.size());
    output.push_back(center);

    int move;
    do {
        move = 0;
        for (size_t j = 0; j < output.size(); j++)
        {
            auto pt1 = output[j];
            for (size_t i = 0; i < input.size(); i++)
            {
                if (!removed[i])
                {
                    auto pt2 = input[i];
                    if (point_distance(pt1, pt2) < SCAN_LINE_DIS * 3)
                    {
                        output.push_back(pt2);
                        removed[i] = true;
                        move++;
                    }
                }
            }
        }
    } while (move > 0);
}

static void find_center(std::vector<point_t> &dots, point_t &center)
{
    point_t sum = { 0 };
    for (auto &pt : dots)
    {
        sum.x += pt.x;
        sum.y += pt.y;
    }
    center.x = sum.x / (int)dots.size();
    center.y = sum.y / (int)dots.size();
    center.width = 0;
}

static void rotate_and_detect(std::vector<point_t> &pat_vec, double width, point_t &center)
{
    const double pi = 3.1415926535897932384626433832795;
    double max_dev = 0.0;
    double max_angle = 0.0;
    int max_i = 0;

    // 步长0.3度 保证最多只旋转2个像素
    // 从30度到150度
    for (double angle = pi * 0.16; angle < pi * 0.83; angle += 0.00552480566567264123712647507169)
    {
        int tmp_i = 0;
        auto std_dev = rotate_angle(pat_vec, width, angle, tmp_i);
        if (std_dev > max_dev)
        {
            max_dev = std_dev;
            max_angle = angle;
            max_i = tmp_i;
        }
    }
    // TODO if max_dev is less than some threshold then quit decoding to fix the "green point misleading".
    // or just suppress it showing out.

    //qDebug() << __FUNCTION__ << "max_dev" << max_dev << "max_angle" << max_angle * 180.0 / pi
    //    << "max_i" << max_i;

#if REMOTE_DRAW
    for (auto &pat : pat_vec) {
        if (pat.type == binaryPattern) {
            __canvas.DrawDot("binarization", "shape=circle;color=0xff00ff;size=6", pat.x, pat.y);
        }
        else if (pat.type == logicalPattern) {
            __canvas.DrawDot("binarization", "shape=circle;color=0xff0000;size=6", pat.x, pat.y);
        }
        else {
            assert(false);
        }
    }
#endif
    std::vector<point_t> filtered_vec;
    filter_dot_in_line(pat_vec, filtered_vec, width, max_angle, max_i);

//#if REMOTE_DRAW
//    for (auto &pat : filtered_vec) {
//        __canvas.DrawDot("binarization", "shape=circle;color=0xff00ff;size=6", pat.x, pat.y);
//    }
//#endif
    find_center(filtered_vec, center);

#if defined(ILD_DEBUG)
    ild_get_debug_info()->pattern2 = filtered_vec.size();
    ild_get_debug_info()->diviation = max_dev;
#endif

#if REMOTE_DRAW
    __canvas.DrawDot("binarization", "shape=circle;color=0xffff00;size=6", center.x, center.y);
#endif

    //std::vector<point_t> filtered2_vec;
    //filter_isolated(filtered_vec, filtered2_vec, center);

#if REMOTE_DRAW
    //for (auto &pat : filtered2_vec) {
    //    __canvas.DrawDot("binarization", "shape=circle;color=0x00ff00;size=6", pat.x, pat.y);
    //}
#endif

    pat_vec.swap(filtered_vec);
}

void ild_vertical_scan(TImage* image, int x, unsigned char* pline)
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

int filter_by_width(std::vector<point_t> &pat_vec)
{
    std::array<int, ILD_MAX_PATTERN_SIZE> histogram;
    histogram.fill(0);

    for (auto &pat : pat_vec)
    {
        if ((int)pat.width < ILD_MAX_PATTERN_SIZE)
        {
            histogram[(int)pat.width] ++;
        }
    }

    const unsigned int INTEGRAL_WIN_SIZE = 3;
    const unsigned int PATTERN_SIZE_VAR = 2;

    int sum = 0;
    for (int i = 0; i < INTEGRAL_WIN_SIZE; i++)
        sum += histogram[i];
    int max_p = INTEGRAL_WIN_SIZE / 2;
    int max_v = sum;

    for (size_t i = INTEGRAL_WIN_SIZE / 2 + 1; i < histogram.size() - INTEGRAL_WIN_SIZE / 2; i++)
    {
        sum -= histogram[i - INTEGRAL_WIN_SIZE / 2 - 1];
        sum += histogram[i + INTEGRAL_WIN_SIZE / 2];
        if (sum > max_v)
        {
            max_v = sum;
            max_p = i;
        }
    }

    int min_size = max_p - PATTERN_SIZE_VAR;
    int max_size = max_p + PATTERN_SIZE_VAR;

    std::vector<point_t> output;
    output.reserve(pat_vec.size());
    int drop_num = 0;
    //根据尺寸过滤pattern
    for (size_t i = 0; i < pat_vec.size(); i++)
    {
        int size = (int)pat_vec[i].width;
        if (size < min_size || size > max_size)
        {
            drop_num++;
        }
        else
        {
            output.push_back(pat_vec[i]);
        }
    }

#if REMOTE_DRAW
    for (auto &pat : pat_vec) {
        __canvas.DrawDot("binarization", "shape=circle;color=0x0000ff;size=6", pat.x, pat.y);
    }
    for (auto &pat : output) {
        __canvas.DrawDot("binarization", "shape=circle;color=0xff0000;size=6", pat.x, pat.y);
    }
#endif

    pat_vec.swap(output);
    return drop_num;
}

/*
static void test_kmeans_clustering(std::vector<point_t> &pat_vec)
{
    KMeans kmeans;
    kmeans.SetK(5);
    std::vector<pointxyz_t> input;
    for (auto &pt : pat_vec)
    {
        pointxyz_t pxyz;
        pxyz.x = pt.x;
        pxyz.y = pt.y;
        pxyz.z = pt.width * 5.0;
        input.push_back(pxyz);
    }
    kmeans.SetInputCloud(input);
    kmeans.Cluster();
    kmeans.DrawResult("binarization");
}
*/

int ild_do_vertical_locating(TImage* image, std::vector<point_t> &pat_vec, point_t &center)
{
    tl::buffer<unsigned char> pline;
    pline.resize(image->h);

    int ret = 0;
    int x = image->w / 2;
    int step = SCAN_LINE_DIS;

    int k = 0;

    while (x >= MIN_EDGE && x < image->w - MIN_EDGE) {
        if ((int)pat_vec.size() >= LOCATING_ENOUGH) break;   // 已采到足够定位点，停止逐列扫描
        x = image->w / 2 + k * step;
        if (x >= image->w - MIN_EDGE){
            break;
        }
        ild_vertical_scan(image, x, &pline[0]);
        if (ild_bin_pattern_match(&pline[0], image->h, x, pat_vec)) {
            ret = 1;
        }
        if (0 == k) {
            k++;
            continue;
        }

        x = image->w / 2 - k * step;
        if (x < MIN_EDGE){
            break;
        }
        ild_vertical_scan(image, x, &pline[0]);
        if (ild_bin_pattern_match(&pline[0], image->h, x, pat_vec)) {
            ret = 1;
        }
        k++;
    }

    rotate_and_detect(pat_vec, image->w, center);

    return ret;
}


static unsigned char get_variance(tl::buffer<Byte> &line)
{
    unsigned char peak = 0;
    unsigned char vally = 255;
    for (auto pix : line)
    {
        if (peak < pix)
        {
            peak = pix;
        }
        if (vally > pix)
        {
            vally = pix;
        }
    }
    return peak - vally;
}

static const int patterns[20][20] = {
    { 1, 1, 1, 1, -1 },
    { 1, 1, 1, -1 },
    { 1, 0, 1, -1 },
    { 1, 1, 0, 1, -1 },
    { 1, 0, 1, 1, -1 },
    { 1, 1, 0, 0, 1, 1, -1 },
    { 1, 1, 0, 1, 1, -1 },
    { 1, 1, 0, 0, 1, -1 },
    { 1, 0, 0, 1, 1, -1 },
    { 1, 1, 0, 0, 0, 1, -1 },
    { 1, 1, -1 },
    { -2 }
};

static bool simple_match(unsigned char* bin, size_t bin_len, const int *pattern, int &pos)
{
    size_t len = 0;
    int pat[64];
    while (pattern[len] != -1) {
        pat[len] = !pattern[len] ? 255 : 0;
        len++;
    }
    bool bRet = false;
    for (size_t i = 0; i < bin_len; i++)
    {
        bool bFound = true;
        size_t a = i;
        for (size_t j = 0; j < len; j++)
        {
            if (bin[a] != pat[j])
            {
                bFound = false;
                break;
            }
            else
            {
                a++;
            }
        }
        if (bFound)
        {
            pos = (int)(i + len / 2);
            bRet = true;
        }
    }
    return bRet;
}

// FIXME subpixel alias
static bool match_rle(tl::buffer<int> &rle, size_t &shift)
{
    if (rle.size() < 3)
        return false;
    if (rle.size() < 5) // FIXME excessive requirement?
    {
        shift = rle[0] + rle[1] / 2;
        return true;
    }
    shift = rle[0] + rle[1] + rle[2] / 2;
    return true;
}

static bool detect_signle_bar(tl::buffer<Byte> &line,
    unsigned char avg_var, int &pos1, int &pos2)
{
    // Hoisted scratch buffers (see detect_pattern_precisely): detect_signle_bar is
    // called ~100s of times per bar_locating; fresh buffers each call = 4 heap
    // allocs/call. Reuse thread-local storage, cleared before each rebuild —
    // bit-exact (ild_get_rle appends, so rle_* must be cleared before the call;
    // clear() preserves capacity, the push_back loops rebuild identical contents).
    static thread_local tl::buffer<Byte> upward;
    static thread_local tl::buffer<int> rle_up;
    static thread_local tl::buffer<Byte> downward;
    static thread_local tl::buffer<int> rle_down;
    upward.clear();
    size_t mid = line.size() / 2;
    for (size_t i = 0; i < mid; i++)
    {
        upward.push_back(line[mid - i - 1]);
    }
    rle_up.clear();
    ild_get_rle(upward.data(), upward.size(), rle_up);
    size_t shift = 0;
    if (match_rle(rle_up, shift))
    {
        pos1 = (int)mid - (int)shift - 1;
        assert(pos1 >= 0);
    }
    downward.clear();
    size_t odd = line.size() % 2;
    for (size_t i = 0; i < mid; i++)
    {
        downward.push_back(line[mid + i + odd]);
    }
    rle_down.clear();
    ild_get_rle(downward.data(), downward.size(), rle_down);
    if (match_rle(rle_down, shift))
        pos2 = (int)(mid + shift + odd);

    auto var = get_variance(line);

    if (var < avg_var * 2 / 3) // brightness variation
        return false;
    else
        return true;
}

static inline Byte nearest_neighbor(TImage *img, double x, double y)
{
    int x2 = (int)(x + 0.5);
    int y2 = (int)(y + 0.5);
    // 修复：原代码仅检查上界(>=w/h)，遗漏下界(<0)。曲线拟合在边缘处可能算出 y<0，
    // 导致 at(x,-1) 越界写→堆破坏→批量解码时段错误。补全下界检查。
    if (x2 < 0 || y2 < 0 || x2 >= img->w || y2 >= img->h)
        return 255;
    else
        return img->at(x2, y2);
}

static bool detect_pattern_precisely(TImage *, TImage *bin_img, double x, double y, double cosa, double sina,
    double width, bool calc_bar_var, unsigned char &bar_var, 
    std::vector<point_t> &bar1_points, std::vector<point_t> &bar2_points)
{
    // Hoist the per-call scratch buffers out of the ~100s of detect_pattern_precisely
    // calls per bar_locating (the #3 decode stage after gaussian/vertical_locating).
    // A fresh vector/buffer each call meant heap alloc/free each call. Reuse
    // thread-local storage, cleared each call — bit-exact vs fresh buffers (all
    // consumers are size-bounded; clear() preserves capacity, the push_back loops
    // rebuild identical contents).
    static thread_local std::vector<point_t> points;
    static thread_local tl::buffer<Byte> line;
    points.clear();
    line.clear();
    const double SCAN_STEP = 1.0; // TODO 这里能不能调小一点? 
    for (double r = -width; r < 0.0; r += SCAN_STEP)
    {
        point_t pt;
        pt.x = cosa * r + x;
        pt.y = sina * r + y;
        pt.width = 0;
        auto pix = nearest_neighbor(bin_img, pt.x, pt.y);
        line.push_back(pix);
        if (!calc_bar_var)
        {
            points.push_back(pt);
        }
    }
    for (double r = 0.0; r < width; r += SCAN_STEP)
    {
        point_t pt;
        pt.x = cosa * r + x;
        pt.y = sina * r + y;
        pt.width = 0;
        auto pix = nearest_neighbor(bin_img, pt.x, pt.y);
        line.push_back(pix);
        if (!calc_bar_var)
        {
            points.push_back(pt);
        }
    }
    if (line.size() == 0)
        return false;
    if (calc_bar_var)
    {
        bar_var = get_variance(line);
    }
    else
    {
        int pos1 = -1;
        int pos2 = -1;
        if (detect_signle_bar(line, bar_var, pos1, pos2))
        {
            if (pos1 > 0)
            {
                point_t pt_bar1 = points[pos1];
#if REMOTE_DRAW
                //__canvas.DrawDot("binarization", "shape=plus;size=3;color=0x0000ff", pt_bar1.x, pt_bar1.y);
#endif
                bar1_points.push_back(pt_bar1);
            }
            if (pos2 > 0)
            {
                point_t pt_bar2 = points[pos2];
#if REMOTE_DRAW
                //__canvas.DrawDot("binarization", "shape=plus;size=3;color=0x0000ff", pt_bar2.x, pt_bar2.y);
#endif
                bar2_points.push_back(pt_bar2);
            }
            return true;
        }
        else
        {
            return false;
        }
    }
    return false;
}

static void trace_curve(double coefficient[4], double x, double &y, double &normal_cos, double &normal_sin)
{
    y = coefficient[3] * x * x * x + coefficient[2] * x * x + coefficient[1] * x + coefficient[0];
    double k = 3.0 * coefficient[3] * x * x + 2.0 * coefficient[2] * x + coefficient[1];
    double b = fabs(atan(-1.0 / k));
    normal_cos = cos(b);
    normal_sin = sin(b);
}

static const int SCAN_SINGLE_STEP = 2; // 1→2：步长翻倍，沿曲线采样点数减半（~400→~200）。条码单元~20px，无混叠。
static const double SCAN_PRECISE_STEP = 0.5;
static const int ERROR_TOLERANCE = 10;

void ild_locate_single_bar(TImage *image, TImage *bin_img, double coefficient[4], point_t center, double width,
    std::vector<point_t> &bar1_points, std::vector<point_t> &bar2_points)
{

    double x;
    double y;
    //point_t pt_bar1;
    //point_t pt_bar2;
    double cosb;
    double sinb;

    static const int VARIANCE_SAMPLE = 10;

    int sum_bar_var = 0;
    x = center.x - VARIANCE_SAMPLE / 2;
    for (int i = 0; i < VARIANCE_SAMPLE; i++)
    {
        trace_curve(coefficient, x, y, cosb, sinb);
        x += SCAN_SINGLE_STEP;
        // 求下平均值
        unsigned char bar_var;
        detect_pattern_precisely(image, bin_img, x, y, cosb, sinb, width, true, bar_var, bar1_points, bar2_points);
        sum_bar_var += bar_var;
    }
    unsigned char avg_bar_var = sum_bar_var / VARIANCE_SAMPLE;

    int err_count = 0;

    for (x = center.x; x > 1.0; x -= SCAN_SINGLE_STEP)
    {
        trace_curve(coefficient, x, y, cosb, sinb);

        if (detect_pattern_precisely(image, bin_img, x, y, cosb, sinb, width, false, avg_bar_var, bar1_points, bar2_points))
        {
            //bar1_points.push_back(pt_bar1);
            //bar2_points.push_back(pt_bar2);
            err_count = 0;
        }
        else
        {
            err_count++;
            if (err_count >= ERROR_TOLERANCE)
                break;
        }
        //__canvas.DrawLine("binarization", "color=0xff", cosb * -20.0 + x, sinb * -20.0 + y,
        //    cosb * 20.0 + x, sinb * 20 + y);
    }
    err_count = 0;
    for (x = center.x; x < image->w - 1; x += SCAN_SINGLE_STEP)
    {
        trace_curve(coefficient, x, y, cosb, sinb);

        if (detect_pattern_precisely(image, bin_img, x, y, cosb, sinb, width, false, avg_bar_var, bar1_points, bar2_points))
        {
            //bar1_points.push_back(pt_bar1);
            //bar2_points.push_back(pt_bar2);
            err_count = 0;
        }
        else
        {
            err_count++;
            if (err_count >= ERROR_TOLERANCE)
                break;
        }
        //__canvas.DrawLine("binarization", "color=0xff", cosb * -20.0 + x, sinb * -20.0 + y,
        //    cosb * 20.0 + x, sinb * 20 + y);
    }
}
