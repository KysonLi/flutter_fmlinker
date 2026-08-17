#ifndef __CORNERFINETUNER_H__
#define __CORNERFINETUNER_H__

#include "ImageType.h"

void fine_tune_corner_coord(IMAGE* image,
                            short  corner_x,
                            short  corner_y,
                            short  frame_width,
                            short* ft_x,
                            short* ft_y);
#endif

