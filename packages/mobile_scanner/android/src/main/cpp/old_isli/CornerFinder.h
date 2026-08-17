#ifndef __CORNERFINDER_H__
#define __CORNERFINDER_H__

#include "ImageType.h"

int do_corner_finder(double* px, double* py, int dot_num, int corner_pos[4]);

void finetune_corners(IMAGE* image, double* px, double* py, int dot_num, int corner_pos[4], double frame_width, int is_clockwise);

#endif

