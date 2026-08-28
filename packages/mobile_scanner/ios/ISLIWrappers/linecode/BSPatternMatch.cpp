#include "BSPatternMatch.h"
#include <cmath>

#if REMOTE_DRAW
#include "canvas.h"
#include <QDebug>
#endif

int ild_bspatternmatch(unsigned short* bs, int bs_len, int x2, std::vector<point_t> &pos_vec)
{
    double x = bs[0];
    int ret = 0;
    const double TOLERANCE = 0.6;
    //qDebug() << __FUNCTION__ << "----";
    for (int i = 3; i < bs_len; i += 2)
    {
        //double w1 = bs[i - 2] + bs[i - 1];
        //double w2 = bs[i - 1] + bs[i];
        double w1 = bs[i - 2];
        double w2 = bs[i - 1];
        double w3 = bs[i];
        double ratio1 = w1 / w3;
        double ratio2 = w2 / w1;
        double ratio3 = w2 / w3;

        if (fabs(ratio1 - 1.0) < TOLERANCE)
        {
            if (fabs(ratio2 - 1.0) < TOLERANCE && fabs(ratio3 - 1.0) < TOLERANCE)
            {
                point_t pattern;
                pattern.x = x2;
                pattern.y = x + (w1 + w2 + w3) / 2.0;
                pattern.width = w1 + w2 + w3;

                if (pattern.width >= 8 && pattern.width <= 64)
                {
                    pos_vec.push_back(pattern);
                }
                //__canvas.DrawDot("source", "shape=plus;size=3;color=0x0000ff", 0, x);
                //qDebug() << __FUNCTION__ << fabs(ratio2 - 1.0);
                ret = 1;
            }
        }
        x += w1;
        x += w2;
    }
    return ret;
}

bool do_match(unsigned char* bin, size_t bin_len, const int *pattern, int x, std::vector<point_t> &pos_vec)
{
    size_t len = 0;
    int pat[64];
    while (pattern[len] != -1) {
        pat[len] = !pattern[len] ? 255 : 0;
        len ++;
    }
    bool bRet = false;
    for (size_t i = 0; i < bin_len; i++)
    {
        bool bFound = true;
        size_t a = i;
        for (size_t j = 0; j < len; j++)
        {
            if (bin[a] != pat[j])
            {
                bFound = false;
                break;
            }
            else
            {
                a ++;
            }
        }
        if (bFound)
        {
            point_t pt;
            pt.x = x;
            pt.y = i + len / 2.0;
            pt.width = len;
            pos_vec.push_back(pt);
            bRet = true;
        }
    }
    return bRet;
}

//PatternNode *g_pattern_tree = nullptr;

bool tree_match(PatternNode *pattern_tree, unsigned char* bin, size_t bin_len, int x, std::vector<point_t> &pos_vec)
{
    bool bRet = false;
    for (size_t i = 0; i < bin_len; i++)
    {
        if (bin[i] != 255)
            continue;
        
        size_t j = i + 1;
        size_t match_len = 1;
        PatternNode *node = pattern_tree;
        PatternNode *prev = pattern_tree;
        while (node && j < bin_len)
        {
            if (!bin[j]) // black
            {
                prev = node;
                node = node->left;
            }
            else // white
            {
                prev = node;
                node = node->right;
            }
            match_len ++; // ??
            j++;
            //if (prev->is_end)
            //    break; // FIXME shortcircuit, long pattern with same begin will never been found.
        }

        if (prev->is_end)
        {
            point_t pt;
            pt.x = x;
            pt.y = i + match_len / 2.0;
            pt.width = match_len;
            pt.type = binaryPattern;
            pos_vec.push_back(pt);
            bRet = true;
        }
    }
    return bRet;
}


// 1 black 0 white
static const int patterns[200][40] = {
    { 0, 1, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 0, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 0, 1, 0, -1 },

    { 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, -1 },

    // 4 4 4
    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, -1 },

    // 5 4 4
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, -1 },
    { 0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 0, -1 },

    // 4 4 5
    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },

    // 5 5 5
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },

    { 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },

    { 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },

    { 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },

    // 5 6 5
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },
    { 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },

    /*
    // 6
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 }, // 6 7 6
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },       // 6 5 6
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },

    // 6 5 5
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1 },

    // 6 6 5
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1 },

    // 6 4 5
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, -1 },

    // 6 4 6
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },

    // 6 5 6
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },

    // 6 7 6
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, -1 },

    // 7
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 }, // 7 7 7
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },    // 6 7 7
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },    // 7 7 6
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },

    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },    // 6 5 7
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, -1 },    // 7 5 6
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, -1 },
    { 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, -1 },
    */
    { -2 }
};

void ild_init_pattern_match(PatternNode **root)
{
    *root = new PatternNode(0xFF);

    size_t i = 0;
    while (patterns[i][0] != -2)
    {
        size_t j = 1;
        assert(patterns[i][0] == 0);
        PatternNode *node = *root;
        PatternNode *prev = node;
        while (patterns[i][j] != -1)
        {
            if (patterns[i][j] == 1)
            {
                if (node->left)
                {
                    prev = node;
                    node = node->left;
                }
                else
                {
                    auto *p = new PatternNode(0x00);
                    node->left = p;
                    prev = node;
                    node = node->left;
                }
            }
            else if(patterns[i][j] == 0)
            {
                if (node->right)
                {
                    prev = node;
                    node = node->right;
                }
                else
                {
                    auto *p = new PatternNode(0xFF);
                    node->right = p;
                    prev = node;
                    node = node->right;
                }
            }
            j ++;
        }
        node->is_end = true;
        i ++;
    }
}

static void traverse_tree(PatternNode *node, std::vector<PatternNode *> &vecNodes)
{
    if (!node)
        return;
    vecNodes.push_back(node);
    traverse_tree(node->left, vecNodes);
    traverse_tree(node->right, vecNodes);
}

void ild_free_pattern_tree(PatternNode *root)
{
    std::vector<PatternNode *> vecNodes;
    traverse_tree(root, vecNodes);
    for (auto node: vecNodes)
        delete node;
}

static inline void put_result(int x, int y, double width, std::vector<point_t> &pos_vec)
{
    point_t pt;
    pt.x = x;
    pt.y = y;
    pt.width = width;
    pt.type = logicalPattern;
    pos_vec.push_back(pt);
}

static bool match_pattern_rle(tl::buffer<int> &rle, int x, int th1, int th2, int min_size, int max_size,
    std::vector<point_t> &pos_vec)
{
    int y = 0;
    bool bRet = false;

    for (size_t i = 0; i + 2 < rle.size(); i++)
    {
        if (i % 2 == 0) // find a black block
        {
            y += rle[i];
            continue;
        }

        // bwb www bwb
        if (i  + 6 < rle.size())
        {
            bool c1 = abs(rle[i + 1] - rle[i]) <= th1;
            bool c2 = abs(rle[i + 2] - rle[i + 1]) <= th1;
            bool c3 = abs(rle[i + 2] - rle[i]) <= th1;
            int up_size = rle[i] + rle[i + 1] + rle[i + 2];

            bool c4 = abs(rle[i + 5] - rle[i + 4]) <= th1;
            bool c5 = abs(rle[i + 6] - rle[i + 5]) <= th1;
            bool c6 = abs(rle[i + 6] - rle[i + 4]) <= th1;
            int down_size = rle[i + 4] + rle[i + 5] + rle[i + 6];

            bool c7 = abs(rle[i + 3] - up_size) <= th2;
            bool c8 = abs(rle[i + 3] - down_size) <= th2;
            bool c9 = abs(down_size - up_size) <= th2;

            int all_size = up_size + rle[i + 3] + down_size;
            bool c10 = all_size >= min_size && all_size <= max_size;

            if (c1 && c2 && c3 && c4 && c5 && c6 && c7 && c8 && c9 && c10)
            {
                put_result(x, y + all_size / 2, all_size, pos_vec);
                bRet = true;
                y += rle[i];
                continue;
            }
        }

        // bbb www bwb
        if (i + 4 < rle.size())
        {
            bool c1 = abs(rle[i + 3] - rle[i + 2]) <= th1;
            bool c2 = abs(rle[i + 4] - rle[i + 3]) <= th1;
            bool c3 = abs(rle[i + 4] - rle[i + 2]) <= th1;
            int down_size = rle[i + 2] + rle[i + 3] + rle[i + 4];

            bool c4 = abs(rle[i + 1] - rle[i]) <= th2;
            bool c5 = abs(down_size - rle[i + 1]) <= th2;
            bool c6 = abs(down_size - rle[i]) <= th2;
            int all_size = rle[i] + rle[i + 1] + down_size;
            bool c7 = all_size >= min_size && all_size <= max_size;

            if (c1 && c2 && c3 && c4 && c5 && c6 && c7)
            {
                put_result(x, y + all_size / 2, all_size, pos_vec);
                bRet = true;
                y += rle[i];
                continue;
            }
        }

        // bwb www bbb
        if (i + 4 < rle.size())
        {
            bool c1 = abs(rle[i + 1] - rle[i]) <= th1;
            bool c2 = abs(rle[i + 2] - rle[i + 1]) <= th1;
            bool c3 = abs(rle[i + 2] - rle[i]) <= th1;
            int up_size = rle[i] + rle[i + 2] + rle[i + 3];

            bool c4 = abs(up_size - rle[i + 3]) <= th2;
            bool c5 = abs(rle[i + 3] - rle[i + 4]) <= th2;
            bool c6 = abs(rle[i + 4] - up_size) <= th2;
            int all_size = up_size + rle[i + 3] + rle[i + 4];
            bool c7 = all_size >= min_size && all_size <= max_size;

            if (c1 && c2 && c3 && c4 && c5 && c6 && c7)
            {
                put_result(x, y + all_size / 2, all_size, pos_vec);
                bRet = true;
                y += rle[i];
                continue;
            }
        }

        // bbb www bbb
        bool c1 = abs(rle[i + 1] - rle[i]) <= th2;
        bool c2 = abs(rle[i + 2] - rle[i + 1]) <= th2;
        bool c3 = abs(rle[i + 2] - rle[i]) <= th2;
        int all_size = rle[i] + rle[i + 1] + rle[i + 2];
        bool c4 = all_size >= min_size && all_size <= max_size;
        if (c1 && c2 && c3 && c4)
        {
            put_result(x, y + all_size / 2, all_size, pos_vec);
            bRet = true;
        }
        y += rle[i];
    }
    return bRet;
}

void ild_get_rle(unsigned char* bin, size_t bin_len, tl::buffer<int> &rle)
{
    rle.reserve(100);
    bool white = true;
    int step = 0;
    for (size_t i = 0; i < bin_len; i++)
    {
        assert(bin[i] == 0 || bin[i] == 255);
        if (white)
        {
            if (bin[i] != 255)
            {
                rle.push_back(step);
                white = false;
                step = 1;
            }
            else
            {
                step ++;
            }
        }
        else
        {
            if (bin[i] != 0)
            {
                rle.push_back(step);
                white = true;
                step = 1;
            }
            else
            {
                step++;
            }
        }
    }
    rle.push_back(step);
}

int ild_bin_pattern_match(unsigned char* bin, size_t bin_len, int x, std::vector<point_t> &pos_vec)
{
    tl::buffer<int> rle;
    ild_get_rle(bin, bin_len, rle);
    int ret = 0;
    if (match_pattern_rle(rle, x, 2, 4, 12, 30, pos_vec))
    {
        ret = 1;
    }
    if (match_pattern_rle(rle, x, 4, 8, 30, 90, pos_vec))
    {
        ret = 1;
    }
    if (match_pattern_rle(rle, x, 12, 8, 90, 9999, pos_vec))
    {
        ret = 1;
    }
    return ret;
}
