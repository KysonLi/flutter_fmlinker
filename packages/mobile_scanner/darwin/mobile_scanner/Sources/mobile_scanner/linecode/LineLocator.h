#ifndef __ILD_LINELOCATOR_H__
#define __ILD_LINELOCATOR_H__

// LineLocator —— 灰度域"两条平行横线"快速检测器（FL 系列）。
//
// 链码物理形态：两条水平行（各 71 模块长 × 1 模块高），行心距 2 模块，
// 中间 1 模块白隔。每个模块无论黑实心还是白底竖纹，上下缘都有墨 →
// 沿整条行的上/下边缘是强【垂直】梯度 —— 与数据内容无关的几何信号。
// （对比：vertical_locating 匹配防伪纹理游程，是间接信号，63% 拒绝来源。）
//
// 检测签名 = 【四条等间距垂直梯度边缘】：上行上/下缘、下行上/下缘，
// pitch = 模块宽 bw，行心距 = 2·pitch。quadruple 搜索 (y0, pitch) 无尺度
// 假设 —— 实测 cache 语料码仅占 40% 帧宽（bw≈4.4 vs W/71≈10.5），
// 不能假设码满宽/贴左缘（sync_crop 与 clean_flat 的假设）。
//
// 流程：垂直梯度行投影（列向剪切补偿倾斜）→ max-pool → quadruple 搜索
// （pitch∈[3,30] 整数全扫）→ x 范围检测 → V1 转移数/V2 同步模板/V3 列覆盖率
// 验证 → 合成置信度 conf。
//
// 坐标约定：
//   yRow0/yRow1/e0..e3 —— x=0（左缘参考）处的行值；投影列偏移 dx[x]=round(T·x/W)。
//   tiltD —— 行的纵向漂移（px，跨全宽）：正值 = 行 y 随 x 增大。矫正应为
//            列向垂直剪切 y' = y - tiltD·x/W（decode_landscape 现有 deskew 是
//            行向水平剪切，不能纠正这种倾角）。
//   xL/xR —— 码的 x 占用范围（band 区列均值暗列判定），V2/V3 只在该范围计。
//   缓冲全部 thread_local —— 函数绝不堆分配、不抛异常。

#include "TImage.h"

struct IldLineLoc
{
    bool   found;      // 硬几何门全过 且 conf >= ILD_FL_T_MID
    int    yRow0;      // 上行中心（x=0 参考）
    int    yRow1;      // 下行中心
    int    e0, e1, e2, e3; // 四边缘行：e0/e1=上行上/下缘，e2/e3=下行上/下缘
    double pitch;      // 搜索等间距（整数 px）= 模块宽的原始估计
    double sep;        // yRow1 - yRow0（真码 ≈ 2·bw）
    double bw;         // 模块宽度精化 = sep/2（行心距恰 2 模块）
    int    tiltD;      // 纵向漂移（见上）
    double conf;       // 0..1 合成置信度
    // ---- 诊断量（FL-1 标定用；检测判定只看 found/conf）----
    double sharp;      // 边缘相对锐度 = min(edge)/(median+2)
    double balance;    // 四边缘均衡度 = min(edge)/max(edge)
    double reg;        // V4 转移间隔规整度 0..1（文字干扰判据：码=模块级等距转移，
                       // 文字=字间/词间大空洞 → reg 低 → 不 found，避免裁出文字）
    double dom;        // 支配度 = 最优/次优不相交 quad 分数比（≈99=无次优=单码帧；
                       // 低值=帧内另有可比结构，典型=同帧双码，FL 置信路径应回避）
    int    trans40;    // [xL,xR] 两行 |Δ|>40 水平转移总数
    int    trans25;    // 同上，阈值 25（模糊边缘主信号）
    double coverage;   // [xL,xR] 列覆盖率（任一行内梯度>25 的列占比）
    double syncScore;  // S1=101 模板最大分（0..384，行 0 上全宽扫描左端）
    int    xL, xR;     // 码的 x 范围（找不到时 -1/-1）
    int    sweeps;     // 实际投影次数（性能诊断，典型 1）
    int    ambig;      // 双码歧义：次优不相交 quad 的行内也具码结构（t25≥门限）
                       // → 帧内另有第二条码，FL 置信路径须回避（回落旧路径，
                       //   由旧路径/扫描窗决定取哪条，与设备行为一致）
};

// 灰度图上找两条平行横线。绝不分配（thread_local 投影缓冲）。返回 loc->found。
// loc 总是被尽可能填充（含未 found 的 best-effort 值），便于离线标定分析。
int ild_locate_two_lines(const TImage* gray, IldLineLoc* loc);

// 紧裁剪规则：[e0, e3] ± margin（gaussian 核 15 零填充边界 7px[放大域] +
// bar_locating 法向扫描余量 + 倾斜漂移 |tiltD|）。最小高度保底 40。
// y0/y1 钳到 [0,H-1]，保证 y1 >= y0。仅 FL 置信路径使用，
// 替代 sync_crop 的 margin=16/强制最小高 80。
void ild_line_loc_crop(const IldLineLoc* loc, int W, int H, int* y0, int* y1);

#endif // __ILD_LINELOCATOR_H__
