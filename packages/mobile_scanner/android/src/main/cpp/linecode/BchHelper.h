#pragma once


int ild_bits_decode2(const unsigned char bits[ILD_BIT_COUNT], char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT]);

// rej=5 桶诊断（bench_diag /DILD_BENCH_DIAG）：本帧 112-bit 路径最小 BCH err_num
// （100=不可纠；7=差1位被 cap=6 拒；<7=守卫拒）。帧入口需在 do_image_decode 复位。
extern int g_ild_min_bch_err;

int ild_bits_decode_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT]);

int ild_bits_decode_short_chain(const unsigned char bits[ILD_BIT_COUNT2], char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT2]);

int ild_bits_decode_short_chain_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT2]);