#include "MatrixSolver.h"
#include <string.h>
#include "stdio.h"

static void diagonal(double** a, int N, double* b){
    int i, j, k;
    double temp = 0;

    for (i = 0; i < N; i++){
        if (a[i][i] == 0){
            for (j = 0; j < N; j++){
                if (j == i) continue;
                if (a[j][i] != 0 && a[i][j] != 0){
                    for (k = 0; k < N; k++){
                        temp = a[j][k];
                        a[j][k] = a[i][k];
                        a[i][k] = temp;
                    }
                    temp = b[j];
                    b[j] = b[i];
                    b[i] = temp;
                    break;
                }
            }
        }
    }
}

int do_matrix_solve(double** a, int N, double* b, double*x)
{
    memset(x, 0, sizeof(double)* N);

    diagonal(a, N, b);

    int i, j, k;
    for (k = 0; k < N; k++){
        for (i = k + 1; i < N; i++){
            if (a[k][k] == 0){
                //Solution is not exist!
                return 0;
            }
            double M = a[i][k] / a[k][k];
            for (j = k; j < N; j++){
                a[i][j] -= M * a[k][j];
            }
            b[i] -= M*b[k];
        }
    }
    for (i = N - 1; i >= 0; i--){
        double s = 0;
        for (j = i; j < N; j++){
            s = s + a[i][j] * x[j];
        }
        x[i] = (b[i] - s) / a[i][i];
    }

    return 1;
}

