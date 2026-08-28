#ifndef __ILD_BSPATTERNMATCH_H__
#define __ILD_BSPATTERNMATCH_H__

#include "Common.h"
#include "buffer.h"
#include <vector>

enum IldPatterType
{
    binaryPattern,
    logicalPattern
};

struct point_t
{
    double x;
    double y;
    double width;
    int type;
};

struct PatternNode
{
    PatternNode(int v) :
        left(nullptr),
        right(nullptr),
        value(v),
        is_end(false) {}
    PatternNode *left;
    PatternNode *right;
    int value;
    bool is_end;
};

int ild_bspatternmatch(unsigned short* bs, int bs_len, int x, std::vector<point_t> &pos_vec);

int ild_bin_pattern_match(unsigned char* bin, size_t bin_len, int x, std::vector<point_t> &pos_vec);

void ild_init_pattern_match(PatternNode **root);

void ild_free_pattern_tree(PatternNode *root);

void ild_get_rle(unsigned char* bin, size_t bin_len, tl::buffer<int> &rle);

#endif