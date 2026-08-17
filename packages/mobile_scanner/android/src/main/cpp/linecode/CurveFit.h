#ifndef __ILD_CURVEFIT_H__
#define __ILD_CURVEFIT_H__

#include "Common.h"
#include <vector>

int ild_curve_fit_with_coord_normalization(double* px, double* py, size_t dot_num, double coefficient[4], double* rcos, double* rsin);
int ild_fit_curve(double* px, double* py, int len, double c[4]);

#endif

