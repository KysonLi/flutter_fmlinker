#ifndef __CURVEFIT_H__
#define __CURVEFIT_H__

int do_curve_fit_with_coord_normalization(double* px, double* py, int dot_num, int start, int end, int is_clockwise, double c[4], double* rcos, double* rsin);

#endif

