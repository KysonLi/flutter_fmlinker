#pragma once


int ild_bits_decode2(const unsigned char bits[ILD_BIT_COUNT], char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT]);

int ild_bits_decode_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT]);

int ild_bits_decode_short_chain(const unsigned char bits[ILD_BIT_COUNT2], char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT2]);

int ild_bits_decode_short_chain_inverted(const unsigned char *bits, char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT2]);