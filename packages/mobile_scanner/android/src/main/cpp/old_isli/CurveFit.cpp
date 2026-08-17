#include "CurveFit.h"
#include "MatrixSolver.h"
#include <math.h>
#include <string.h>


static const int N = 4;

static void calcA(double* px, int len, double** A)
{
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            double tx = 0;
            for (int k = 0; k < len; k++){
                double dx = 1.0;
                for (int l = 0; l < j + i; l++){
                    dx = dx * px[k];
                }
                tx += dx;
            }
            A[i][j] = tx;
        }
    }
}

static void calcB(double* px, double* py, int len, double* b)
{
    for (int i = 0; i < N; i++) {
        double ty = 0;
        for (int k = 0; k < len; k++){
            double dy = 1.0;
            for (int l = 0; l < i; l++){
                dy = dy * px[k];
            }
            ty += py[k] * dy;
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

    calcA(px, len, &A[0]);
    calcB(px, py, len, &b[0]);

    //Ac=b，求c
    return do_matrix_solve(A, N, b, c);
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

    int is_cycle = 0;
    if (is_clockwise) {
        if (end < start) {
            //顺时针，头比尾小，循环了
            is_cycle = 1;
            len = end + dot_num - start + 1;
            xx = new double[(size_t)len];
            yy = new double[(size_t)len];
            
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
            xx = new double[(size_t)len];
            yy = new double[(size_t)len];
            
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

    double* nx = new double[(size_t)len];
    double* ny = new double[(size_t)len];
    
    normalize_point_coord(xx, yy, len, nx, ny, rcos, rsin);
    succ = fit_curve(nx, ny, len, c);
    
    delete[] nx;
    delete[] ny;
    if (is_cycle) {
        delete[] xx;
        delete[] yy;
    }

    return succ;
}

