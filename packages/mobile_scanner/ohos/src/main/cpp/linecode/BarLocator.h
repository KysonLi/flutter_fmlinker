#pragma once

#include "Common.h"
#include "TImage.h"
#include "BSPatternMatch.h"

int ild_do_vertical_locating(TImage* image, std::vector<point_t> &pat_vec, point_t &center);
void ild_locate_single_bar(TImage *image, TImage *bin_img, double coefficient[4], point_t center, 
    double width, std::vector<point_t> &bar1_points, std::vector<point_t> &bar2_points);
void ild_vertical_scan(TImage* image, int x, unsigned char* pline);
