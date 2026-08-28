#ifndef __ILD_GAUSSIAN_BINARIZATION_H__
#define __ILD_GAUSSIAN_BINARIZATION_H__

#include <vector>
#include "TImage.h"
#include "buffer.h"
#include "Common.h"

double ild_gaussian_func(double u, double o, double x);
void ild_gaussian_kernel(tl::buffer<int> &vecKernel, int size);
void ild_gaussian_blur(TImage &img, TImage &out);
void ild_gaussian_binarization(TImage &img, TImage &out);
void ild_gaussian_rethreshold(const TImage &img, TImage &out, int bias);

#endif