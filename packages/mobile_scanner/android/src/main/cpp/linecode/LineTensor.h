#ifndef __ILD_LINETENSOR_H__
#define __ILD_LINETENSOR_H__

// LineTensor —— 结构张量 + 主方向形态学 + 旋转矩形筛选（找两条平行横线）。
//
// 独立于 LineLocator 的新检测路径，专门应对"文字块误检"（用户目测主痛点）。
// 链码几何先验：两条行 = 长、方向一致的近水平边缘，区域长宽比 ≈ 71:3 ≈ 23.7:1。
//
// 算法（3 组件）：
//   1) 结构张量方向相干性：局部窗口累加 J=[ΣGx² ΣGxGy; ΣGxGy ΣGy²]，
//      特征值 λ1≥λ2，相干性 C=(λ1-λ2)/(λ1+λ2)（高=单方向一致边缘），
//      主方向 θ=0.5·atan2(2Jxy, Jxx-Jyy)。码边 C 高且近水平；文字字符
//      内方向散布 C 低 → 天然抑制文字。
//   2) 主方向形态学（等价）：逐行找"近水平边缘"的连续 run，只计
//      run 长度 ≥ 阈值的部分 → 长度滤波投影（滤掉文字短笔画碎片）。
//   3) 旋转矩形筛选：候选区 (xL..xR)×(e0..e3) 长宽比 ≥ 阈值（码 23.7:1，
//      实测码仅占部分帧宽 → 实际 ≥ 8:1 即符合）。
//
// 与 LineLocator 输出兼容（IldLineLoc 同构字段），bench tensordetect
// 模式可直接复用裁剪落盘。

#include "TImage.h"

struct IldTensorLoc
{
    bool   found;
    int    yRow0, yRow1;    // 行中心（源坐标）
    int    e0, e1, e2, e3;  // 四边缘（上行上/下缘、下行上/下缘）
    double pitch;           // 搜索等间距（降采样前整数 px 估计）
    double sep, bw;         // 行距与模块宽
    int    tiltD;           // 主倾角漂移（px 跨全宽，行 y 随 x 增；结构张量
                            // 梯度方向直方图估计；0=无倾/未估出）
    int    xL, xR;          // 码 x 范围
    double conf;            // 合成置信度（相干性强度×锐度×长宽比）
    double aspect;          // 候选矩形长宽比 (xR-xL)/(e3-e0)
    double coh;             // 两行区平均相干性
    double hEdge;           // 两行区近水平边缘投影峰值
    int    sweeps;
    // ---- 候选带对（top-K，供"裁剪→解码仲裁"用：廉价特征无法区分码与
    // 文字/干扰线，唯一可靠仲裁=解码本身。K 对按分数降序，逐对试解）----
    int    nPairs;                       // 有效候选对数
    int    pairY0[8], pairY1[8];         // 每对两带中心 y
    double pairScore[8];                 // 对分数（两带较小值）
};

// 结构张量定位两条平行横线。绝不堆分配（thread_local 缓冲）。
// 返回 loc->found。loc 总是被尽可能填充（便于离线诊断）。
int ild_tensor_locate(const TImage* gray, IldTensorLoc* loc);

// 与 LineLocator 相同的裁剪规则（复用：直接调 ild_line_loc_crop 即可）。

#endif // __ILD_LINETENSOR_H__
