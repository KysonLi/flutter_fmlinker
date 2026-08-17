#include "BresenhamLine.h"

static void switch_to_octant_zero_from(int octant, int *x, int *y);
static void switch_from_octant_zero_to(int octant, int *x, int *y);
static void swap(int *a, int *b);

static int get_octant(int x1, int y1, int x2, int y2)
{
    int dx = x2 - x1;
    int dy = y2 - y1;


    if (dy >= 0)
    {
        if (dx >= 0)
        {
            if (dx >= dy)
            {
                return 0;
            }
            else
            {
                return 1;
            }
        }
        else
        {
            if (-dx < dy)
            {
                return 2;
            }
            else
            {
                return 3;
            }
        }
    }
    else
    {
        if (dx < 0)
        {
            if (-dx >= -dy)
            {
                return 4;
            }
            else
            {
                return 5;
            }
        }
        else
        {
            if (dx < -dy)
            {
                return 6;
            }
            else
            {
                return 7;
            }
        }
    }
}

int bresenham_line(int x1, int y1, int x2, int y2, draw_pixel_callback_t callback, void *userdata)
{
    int octant = get_octant(x1, y1, x2, y2);
    switch_to_octant_zero_from(octant, &x1, &y1);
    switch_to_octant_zero_from(octant, &x2, &y2);

    // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
    if (x2 < x1) // FIXME i figure it out by guess, dont understand the underlying truth or it is omitted by the document.
    {
        swap(&x1, &x2);
        swap(&y1, &y2);
    }
    int dx = x2 - x1;
    int dy = y2 - y1;
    //ILDLOG("dx: %d dy: %d", dx, dy);
    int D = 2 * dy - dx;
    int y = y1;

    for (int x = x1; x <= x2; x++)
    {
        int tx = x;
        int ty = y;
        switch_from_octant_zero_to(octant, &tx, &ty);
        if (!callback(tx, ty, userdata))
        {
            return 0;
        }

        if (D > 0)
        {
            y = y + 1;
            D -= 2 * dx;
        }
        D += 2 * dy;
    }
    return 1;
}

static void swap(int *a, int *b)
{
    int t = *a;
    *a = *b;
    *b = t;
}

// use it on input
static void switch_to_octant_zero_from(int octant, int *x, int *y)
{
    switch (octant)
    {
    case 0: break; //return (x, y)
    case 1: swap(x, y); break; //return (y, x)
    case 2: swap(x, y); *x = -*x; break; //return (y, -x)
    case 3: *x = -*x; break; //return (-x, y)
    case 4: *x = -*x; *y = -*y; break; //return (-x, -y)
    case 5: swap(x, y); *x = -*x; *y = -*y; break; //return (-y, -x)
    case 6: swap(x, y); *y = -*y; break; //return (-y, x)
    case 7: *y = -*y; break; //return (x, -y)
    }
}

// use it on output
static void switch_from_octant_zero_to(int octant, int *x, int *y)
{
    switch (octant)
    {
    case 0: break; //return (x, y)
    case 1: swap(x, y); break; //return (y, x)
    case 2: swap(x, y); *y = -*y; break; //return (-y, x)
    case 3: *x = -*x; break; //return (-x, y)
    case 4: *x = -*x; *y = -*y; break; //return (-x, -y)
    case 5: swap(x, y); *x = -*x; *y = -*y; break; //return (-y, -x)
    case 6: swap(x, y); *x = -*x; break; //return (y, -x)
    case 7: *y = -*y; break; //return (x, -y)
    }
}