#include "CurveFit.h"
#include "MatrixSolver.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
#include <math.h>
#include <string.h>


static const int N = 4;

//优化：预计算每个点的 x^1 ~ x^6，避免 calcA/calcB 中重复的幂次循环
static void precompute_powers(double* px, int len, double* pow_cache, int max_power)
{
    for (int k = 0; k < len; k++) {
        double* pc = pow_cache + k * (max_power + 1);
        pc[0] = 1.0;
        double x = px[k];
        pc[1] = x;
        for (int p = 2; p <= max_power; p++) {
            pc[p] = pc[p - 1] * x;
        }
    }
}

static void calcA(double* px, int len, double** A, double* pow_cache)
{
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            int power = j + i;
            double tx = 0;
            const double* pc = pow_cache + power;
            for (int k = 0; k < len; k++, pc += 7) {
                tx += *pc;
            }
            A[i][j] = tx;
        }
    }
}

static void calcB(double* px, double* py, int len, double* b, double* pow_cache)
{
    for (int i = 0; i < N; i++) {
        double ty = 0;
        const double* pc = pow_cache + i;
        for (int k = 0; k < len; k++, pc += 7) {
            ty += py[k] * (*pc);
        }
        b[i] = ty;
    }
}

//y = c[0] + c[1]*x + c[2]*x^2 + c[3]*x^3
static int fit_curve(double* px, double* py, int len, double c[4])
{
    double a[N*N];
    double *A[N] = { &a[0], &a[N], &a[2*N], &a[3*N] };
    double b[N];

    //预计算 x^0~x^6 的幂次，避免 calcA/calcB 中的重复循环
    double* pow_cache = g_pool ? g_pool->scratch_double : new double[(size_t)len * 7];
    precompute_powers(px, len, pow_cache, 6);

    calcA(px, len, &A[0], pow_cache);
    calcB(px, py, len, &b[0], pow_cache);

    if (!g_pool) delete[] pow_cache;

    //Ac=b，求c
    int r = do_matrix_solve(A, N, b, c);
    if (!r) {
        ISLII_LOGE("[curve] fit_curve: matrix solve FAILED (singular), len=%d", len);
    }
    return r;
}

//shift first point to origin, rotate last point to x-axis
static void normalize_point_coord(double* px_in, double * py_in, int len, double* px_out, double* py_out, double* rcos, double* rsin)
{
    double shift_x = -px_in[0];
    double shift_y = -py_in[0];

    double dx = px_in[len - 1] - px_in[0];
    double dy = py_in[len - 1] - py_in[0];
    double r = sqrt(dx * dx + dy * dy);

    double cosa = dx / r;
    double sina = dy / r;

    for (int i = 0; i < len; i++) {
        double x = px_in[i] + shift_x;
        double y = py_in[i] + shift_y;

        px_out[i] = +x * cosa + y * sina;
        py_out[i] = -x * sina + y * cosa;
    }

    *rcos = cosa;
    *rsin = -sina;
}

int do_curve_fit_with_coord_normalization(double* px, double* py, int dot_num, int start, int end, int is_clockwise, double c[4], double* rcos, double* rsin)
{
    int succ = 0;
    int len = 0;
    double* xx = 0;
    double* yy = 0;

    //使用内存池或退化为堆分配
    double* nx = g_pool ? g_pool->fit_nx : 0;
    double* ny = g_pool ? g_pool->fit_ny : 0;
    bool own_nx = false;

    int is_cycle = 0;
    if (is_clockwise) {
        if (end < start) {
            //顺时针，头比尾小，循环了
            is_cycle = 1;
            len = end + dot_num - start + 1;
            xx = g_pool ? g_pool->fit_xx : new double[(size_t)len];
            yy = g_pool ? g_pool->fit_yy : new double[(size_t)len];

            int m = 0;
            for (int i = start; i <= end + dot_num; i++) {
                int k = i % dot_num;
                xx[m] = px[k];
                yy[m] = py[k];
                m++;
            }
        }
    }
    else {
        if (end > start) {
            //逆时针，尾比头小，循环了
            is_cycle = 1;
            len = dot_num - (end - start - 1);
            xx = g_pool ? g_pool->fit_xx : new double[(size_t)len];
            yy = g_pool ? g_pool->fit_yy : new double[(size_t)len];

            int m = 0;
            for (int i = end; i <= start + dot_num; i++){
                int k = i % dot_num;
                xx[m] = px[k];
                yy[m] = py[k];
                m++;
            }
        }
    }
    if (!is_cycle) {
        len = end > start ? end - start + 1 : start - end + 1;
        if (is_clockwise) {
            xx = px + start;
            yy = py + start;
        }
        else {
            xx = px + end;
            yy = py + end;
        }
    }

    if (!nx) {
        nx = new double[(size_t)len];
        ny = new double[(size_t)len];
        own_nx = true;
    }

    normalize_point_coord(xx, yy, len, nx, ny, rcos, rsin);
    succ = fit_curve(nx, ny, len, c);

    if (own_nx) {
        delete[] nx;
        delete[] ny;
    }
    if (is_cycle && !g_pool) {
        delete[] xx;
        delete[] yy;
    }

    return succ;
}

