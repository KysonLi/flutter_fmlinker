#include "CurveFit.h"
#include "MatrixSolver.h"
#include <math.h>
#include <string.h>
#include "buffer.h"

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
int ild_fit_curve(double* px, double* py, int len, double c[4])
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

int ild_curve_fit_with_coord_normalization(double* px, double* py, size_t dot_num, double coefficient[4], double* rcos, double* rsin)
{
    tl::buffer<double> nx;
    nx.resize(dot_num);
    tl::buffer<double> ny;
    ny.resize(dot_num);
    
    normalize_point_coord(px, py, (int)dot_num, nx.data(), ny.data(), rcos, rsin);
    return ild_fit_curve(nx.data(), ny.data(), (int)dot_num, coefficient);
}

