// LineCodeSpec.h
//
// ISLI 行码 — 编解码共享常量与解交织 LUT（header-only）。
//
// 严格依据 doc/LineCode条码生成规则.md（§3 同步交织）与
//          doc/最优手机端解码全流程.md（§4 解交织）。
//
// 生成侧映射（doc §3.4）：
//   pos=0; for i in 0..111 { if(i%14==0) pos+=(i/14==4)?6:3; t[pos]=bch[i]; pos++; }
// 解码侧 LUT 是其镜像：kDeinterleaveLut[i] = bch 位 i 在 142-bit raw 流中的下标。
//
// 142-bit raw 流布局（2 行 × 71 位，Line0=raw[0..70], Line1=raw[71..141]）：
//   S1[0..2]=101  D1[3..16]   S2[17..19]=101  D2[20..33]   S3[34..36]=101  D3[37..50]
//   S4[51..53]=101  D4[54..67]   S5[68..70]=010  S6[71..73]=010  D5[74..87]
//   S7[88..90]=101  D6[91..104]  S8[105..107]=101  D7[108..121]
//   S9[122..124]=101  D8[125..138]  S10[139..141]=010
#ifndef LINECODE_LINE_CODE_SPEC_H
#define LINECODE_LINE_CODE_SPEC_H

#include <array>
#include <cstdint>

namespace linecode {

// ---- 同步/分块结构常量（doc §3.1）----
constexpr int kBitsPerData     = 14;   // 每个数据块 14 bit
constexpr int kSyncLen         = 3;    // 每个同步码 3 bit
constexpr int kDataBlocks      = 8;    // 8 个数据块
constexpr int kTotalData       = 112;  // 总数据位 = 8*14
constexpr int kSyncCount       = 10;   // 同步码数量
constexpr int kTotalBits       = 142;  // 总输出位 = 112 + 3*10
constexpr int kBitsPerRow      = 71;   // 单行 71 位（两行分割点在 bit71）

// ---- BCH 参数（doc §2.1）----
constexpr int kBchM            = 7;    // GF(2^7)
constexpr int kBchT            = 7;    // 纠错能力 t=7
constexpr int kEccBits         = 49;   // ecc 有效位数（生成多项式次数）
constexpr int kDataFrameBytes  = 10;   // 80-bit 数据帧 = 10 字节
constexpr int kDataFrameBits   = 80;
constexpr int kEccBytes        = 7;    // 56-bit ecc 帧 = 7 字节
constexpr int kPayloadBits     = 63;   // 有效载荷位数
constexpr int kLeadingZeros    = 17;   // 数据帧前 17 位固定为 0

// ---- 输入约束（doc §2.2）----
constexpr uint64_t kPayloadMax = 0x5555555555555555ULL;

// ---- 同步码位模式（doc §3.2）----
// NORMAL=101 (深-浅-深)，INVERTED=010 (浅-深-浅)。
enum SyncType : int { SYNC_NORMAL = 0, SYNC_INVERTED = 1 };

// 10 个同步码的预期类型，顺序 S1..S10（doc §3.3 / §3.5）。
// 正 正 正 正 反 反 正 正 正 反
constexpr std::array<int, kSyncCount> kSyncType = {
    SYNC_NORMAL, SYNC_NORMAL, SYNC_NORMAL, SYNC_NORMAL,
    SYNC_INVERTED, SYNC_INVERTED,
    SYNC_NORMAL, SYNC_NORMAL, SYNC_NORMAL, SYNC_INVERTED,
};

// 返回同步码 j 的 3 位模式（MSB-first：第一位最先出现在流中）。
inline std::array<int, kSyncLen> syncBits(int j) {
    if (j < 0 || j >= kSyncCount) return {0, 0, 0};
    return (kSyncType[j] == SYNC_NORMAL) ? std::array<int, kSyncLen>{1, 0, 1}
                                         : std::array<int, kSyncLen>{0, 1, 0};
}

// ---- 解交织 LUT ----
// 镜像生成侧映射：第 i 个 bch 位在 142-bit raw 流中的下标。
// C++11 的 constexpr 函数体不允许循环/分支，故改为首次访问时构建的静态表
// （Meyers 单例，C++11 起局部静态初始化线程安全）。
inline const std::array<int, kTotalData>& deinterleaveLut() {
    static const std::array<int, kTotalData> lut = []() {
        std::array<int, kTotalData> t{};
        int pos = 0;
        for (int i = 0; i < kTotalData; ++i) {
            if (i % kBitsPerData == 0) {
                // 第 5 组数据(i/14==4)前面有两个连续同步码 S5+S6(6 位)，其余跳 3 位。
                pos += (i / kBitsPerData == 4) ? (kSyncLen * 2) : kSyncLen;
            }
            t[i] = pos;
            ++pos;
        }
        return t;
    }();
    return lut;
}

// 10 个同步码在 142-bit raw 流中的起始下标（每个占 3 位）。
// S1=0,S2=17,S3=34,S4=51,S5=68 | S6=71,S7=88,S8=105,S9=122,S10=139。
constexpr std::array<int, kSyncCount> kSyncStart = {
    0, 17, 34, 51, 68, 71, 88, 105, 122, 139,
};

}  // namespace linecode

#endif  // LINECODE_LINE_CODE_SPEC_H
