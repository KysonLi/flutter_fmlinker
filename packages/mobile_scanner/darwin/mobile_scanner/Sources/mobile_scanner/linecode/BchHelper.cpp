#include "Common.h"
#include "bch.h"
#include "BchHelper.h"
#include <string.h>

extern bch_control*   __bch_ctrl127;
extern bch_control*   __bch_ctrl64;

// __________________________________________________________________________________________________________________________________________________________________________
//|                                       data， 80bits - 2个x位 - 15个0位 = 63位有效位                                                                                        | 
//|_________________________________________________________________________________________________________________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4       |    BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |     BYTE9      |
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|0000000000000000|0000000000000000|vvvvvvvvvvvvvv00|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|                                       ecc[49bits]                                                   |                |                                 
//|_____________________________________________________________________________________________________|________________|
//|     BYTE10     |     BYTE11     |     BYTE12     |     BYTE13     |     BYTE14      |     BYTE15    |     BYTE16     |
//|________________|________________|________________|________________|_________________|_______________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vv00000000000000|
//|________________|________________|________________|________________|_________________|_______________|________________|
//
// 127bit排列顺序：从BYTE0到BYTE16，每个BYTE内从b0到b7，v为有效bit,0为预设固定值0
static const int PRESET_DATA_ZERO_BITS_START = 0;
static const int PRESET_DATA_ZERO_BITS_END = 16;
static const int PRESET_ECC_ZERO_BITS_START = 48;
static const int PRESET_ECC_ZERO_BITS_END = 54;

static void compact_bits2(const unsigned char bits[112], unsigned char received[17])
{
    memset(received, 0, 17);

    int i = 0, k = 0;
    for (i = 0, k = 0; i < 10 * 8; i++){
        if (i >= PRESET_DATA_ZERO_BITS_START &&
            i <= PRESET_DATA_ZERO_BITS_END) {
            continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
    for (i = 0; i < 7 * 8; i++){
        if (i >= PRESET_ECC_ZERO_BITS_START &&
            i <= PRESET_ECC_ZERO_BITS_END){
            continue;
        }
        if (bits[k]) {
            int j = 80 + i;
            received[j >> 3] |= (1 << (j & 7));
        }
        k++;
    }
}

static void bits2string2(unsigned char bits[10], char str[20])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 80; i++) {
        if (i < 17) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    for (int i = 0; i < 19; i++) {
        char c = (v % 10) + '0';
        str[18 - i] = c;
        v = v / 10;
    }
    str[19] = 0;
}

void recover_112bits(const unsigned char data[10], const unsigned char ecc[7], unsigned char bits[112])
{
    int i = 0;
    int k = 0;

    for (i = 0; i < 80; i++) {
        if (i < 17)
            continue;
        if (data[i / 8] & (1 << (i & 7))){
            bits[k] = 1;
        }
        else{
            bits[k] = 0;
        }
        k++;
    }
    for (i = 0; i < 56; i++) {
        if (i >= 48 && i < 55)
            continue;
        if (ecc[i / 8] & (1 << (i & 7))){
            bits[k] = 1;
        }
        else{
            bits[k] = 0;
        }
        k++;
    }
}

int ild_bits_decode_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT])
{
    unsigned char fliped[ILD_BIT_COUNT];
    //if (bits[0] == 0xff && bits[1] == 0x00 && bits[2] == 0xff)

    for (size_t i = 0; i < ILD_BIT_COUNT; i++)
    {
        fliped[ILD_BIT_COUNT - i - 1] = bits[i];
    }
    return ild_bits_decode2(fliped, isli_code, corrected_bits);
}

int ild_bits_decode2(const unsigned char bits[ILD_BIT_COUNT], char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT])
{
    unsigned char received[17] = { 0 };
    unsigned int error_loc[7] = { 0 };

    compact_bits2(bits, received);

    int err_num = decode_bch(__bch_ctrl127, &received[0], 10, &received[10], 0, 0, error_loc);
    //ILDLOG("err_num: %d", err_num);
    if (err_num >= 0 && err_num <= 6) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            if (((k >= PRESET_DATA_ZERO_BITS_START) && (k <= PRESET_DATA_ZERO_BITS_END)) ||
                ((k >= PRESET_ECC_ZERO_BITS_START) && (k <= PRESET_ECC_ZERO_BITS_END))){
                return 0;
            }
            //ILDLOG("error_loc: %d", k);
            received[k >> 3] ^= (1 << (k & 7));
        }

        unsigned char data[10] = { 0 };
        unsigned char ecc[7] = { 0 };
        memcpy(data, received, 10);
        encode_bch(__bch_ctrl127, data, 10, ecc);
        if (0 == memcmp(&received[10], ecc, 7)) {
            //用于调试
            recover_112bits(data, ecc, corrected_bits);

            bits2string2(data, isli_code);
            // exclude '000000' situation
            int nz = 0;
            for (size_t i = 0; i < 20; i++)
            {
                if (isli_code[i] == '\0')
                    break;
                if (isli_code[i] != '0')
                    nz = 1;
            }
            if (!nz)
            {
                ILDLOG("all zero isli_code");
            }
            if (nz && strncmp(isli_code, "0000000549755813887", 19) == 0)
            {
                ILDLOG("reject known-false isli_code");
                return 0;
            }
            return nz;
        }
    }

    return 0;
}

// ________________________________________________________________________________________________________________________________________________________
//|                                       data                                         |                               ecc                                 |
//|____________________________________________________________________________________|___________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4      |     BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |
//|-_______________|________________|________________|________________|________________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|xxvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|xxxxxxxxxxxxxxxx|
//|________________|________________|________________|________________|________________|________________|________________|________________|________________|
//
// 63bit排列顺序：从BYTE0到BYTE8，每个BYTE内从b0到b7，x表示不使用且固定为0,v为有效bit
// data 39bit, ecc 24bit

static const int PRESET_DATA_ZERO_BITS_START3 = 7;
static const int PRESET_DATA_ZERO_BITS_END3 = 7;
static const int PRESET_ECC_ZERO_BITS_START3 = 64;
static const int PRESET_ECC_ZERO_BITS_END3 = 71;

static void compact_bits_short_chain(const unsigned char bits[64], unsigned char received[9])
{
    memset(received, 0, 9);

    int k = 0;
    for (int i = 0; i < 8 * 9; i++){
        if ((i >= PRESET_DATA_ZERO_BITS_START3 && i <= PRESET_DATA_ZERO_BITS_END3) || 
            (i >= PRESET_ECC_ZERO_BITS_START3 && i <= PRESET_ECC_ZERO_BITS_END3)) {
                continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
}

// FIXME
static void bits2string_short_chain(unsigned char bits[5], char str[20])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 40; i++) {
        if (i == PRESET_DATA_ZERO_BITS_START3) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    for (int i = 0; i < 19; i++) {
        char c = (v % 10) + '0';
        str[18 - i] = c;
        v = v / 10;
    }
    str[19] = 0;
}

int ild_bits_decode_short_chain(const unsigned char bits[ILD_BIT_COUNT2], char isli_code[20], 
    unsigned char corrected_bits[ILD_BIT_COUNT2])
{
    UNREFERENCED_PARAMETER(corrected_bits);
    unsigned char received[9] = { 0 };
    unsigned int error_loc[7] = { 0 };

    compact_bits_short_chain(bits, received);

    int err_num = decode_bch(__bch_ctrl64, &received[0], 5, &received[5], 0, 0, error_loc);
    //ILDLOG("err_num: %d", err_num);
    if (err_num >= 0 && err_num <= 1) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            if (((k >= PRESET_DATA_ZERO_BITS_START3) && (k <= PRESET_DATA_ZERO_BITS_END3)) ||
                ((k >= PRESET_ECC_ZERO_BITS_START3) && (k <= PRESET_ECC_ZERO_BITS_END3))){
                return 0;
            }
            //ILDLOG("error_loc: %d", k);
            received[k >> 3] ^= (1 << (k & 7));
        }

        unsigned char data[5] = { 0 };
        unsigned char ecc[4] = { 0 };
        memcpy(data, received, 5);
        encode_bch(__bch_ctrl64, data, 5, ecc);
        if (0 == memcmp(&received[5], ecc, 4)) {
            //用于调试
            //recover_112bits(data, ecc, corrected_bits);

            bits2string_short_chain(data, isli_code);
            // exclude '000000' situation
            int nz = 0;
            for (size_t i = 0; i < 20; i++)
            {
                if (isli_code[i] == '\0')
                    break;
                if (isli_code[i] != '0')
                    nz = 1;
            }
            if (!nz)
            {
                ILDLOG("all zero isli_code");
            }
            if (nz && strncmp(isli_code, "0000000549755813887", 19) == 0)
            {
                ILDLOG("reject known-false isli_code");
                return 0;
            }
            return nz;
        }
    }

    return 0;
}

int ild_bits_decode_short_chain_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT2])
{
    unsigned char fliped[ILD_BIT_COUNT2];
    //if (bits[0] == 0xff && bits[1] == 0x00 && bits[2] == 0xff)

    for (size_t i = 0; i < ILD_BIT_COUNT2; i++)
    {
        fliped[ILD_BIT_COUNT2 - i - 1] = bits[i];
    }
    return ild_bits_decode_short_chain(fliped, isli_code, corrected_bits);
}