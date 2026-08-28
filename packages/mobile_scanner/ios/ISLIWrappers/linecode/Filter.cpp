#include "Filter.h"

/*

FIR filter designed with
http://t-filter.appspot.com

sampling frequency: 18 Hz

* 0 Hz - 1 Hz
gain = 1
desired ripple = 10 dB
actual ripple = 6.633008253802547 dB

* 2 Hz - 9 Hz
gain = 0
desired attenuation = -40 dB
actual attenuation = -41.770936619464415 dB

*/

#define FILTER_TAP_NUM 17

static double lp_filter_coef[FILTER_TAP_NUM] = {
    0.011044269869122793,
    0.020679412002954506,
    0.03640052036462914,
    0.05593251970490355,
    0.07752545632849764,
    0.09866448524757082,
    0.1165098889441427,
    0.12845804862849539,
    0.1326642085474269,
    0.12845804862849539,
    0.1165098889441427,
    0.09866448524757082,
    0.07752545632849764,
    0.05593251970490355,
    0.03640052036462914,
    0.020679412002954506,
    0.011044269869122793
};


void ild_low_pass_filter(unsigned char* in, int len, unsigned char* out)
{
    int k = sizeof(lp_filter_coef) / sizeof(lp_filter_coef[0]) / 2;

    for (int i = 0; i < len; i++) {
        int p = 0;
        double acc = 0;
        
        for (int j = i - k; j <= i + k; j++){
            int m = j;
            if (m < 0)
                m += len;
            else if (m >= len)
                m -= len;
            
            acc += (in[m] * lp_filter_coef[p++]);
        }
        acc /= 1.208;
        if (acc < 0)
            acc = 0;
        else if (acc > 255)
            acc = 255;
        
        out[i] = (unsigned char)(acc + 0.5);
    }
}

