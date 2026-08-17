#include <math.h>


int do_line_sample(unsigned char* bits, int w, int h, int bpl,
                   int* px, int* py, int pn,
                   unsigned short* psample_buf, int buf_len)
{
    int sample_len = 0;
    if (pn < 2) {
        return 0;
    }
    for (int i = 1; i < pn; i++) {
        int dx = px[i] - px[i - 1];
        int dy = py[i] - py[i - 1];

        if (0 == dx && 0 == dy) {
            break;
        }

        double k = sqrt(double(dx*dx + dy * dy));
        int step_x = int(dx * 1024 / k + 0.5);
        int step_y = int(dy * 1024 / k + 0.5);
        int len = int(k);
        int sx = px[i - 1] * 1024;
        int sy = py[i - 1] * 1024;
        for (int s = 0; s < len; s++) {
            //sample at sx, sy
            int u = (sx + 512) >> 10;
            int v = (sy + 512) >> 10;

            if ((u >= 0 && u < w) && (v >= 0 && v < h)) {
                int ofst = v * bpl + u;
                psample_buf[sample_len] = (unsigned short)(bits[ofst] + bits[ofst + 1] + bits[ofst - 1]);
                
                ofst -= bpl;
                psample_buf[sample_len] += bits[ofst] + bits[ofst + 1] + bits[ofst - 1];

                ofst += 2*bpl;
                psample_buf[sample_len] += bits[ofst] + bits[ofst + 1] + bits[ofst - 1];

                psample_buf[sample_len] /= 9;

                sample_len++;
                if (sample_len >= buf_len){
                    return sample_len;
                }
            }

            sx += step_x;
            sy += step_y;
        }
    }

    return sample_len;
}

