#pragma once

typedef int(*draw_pixel_callback_t)(int x, int y, void *userdata);

int bresenham_line(int x1, int y1, int x2, int y2, draw_pixel_callback_t callback, void *userdata);
