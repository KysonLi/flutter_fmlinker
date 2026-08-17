#ifndef __ISLIICONDECODER_H__
#define __ISLIICONDECODER_H__

#include "ImageType.h"

//解码器初始化
//成功返回1
//失败返回0，原因是已经被初始化了
int isli_icon_decoder_init();

//解码器反初始化
//成功返回1
//失败返回0，原因是还未被初始化过或已经被反初始化了
int isli_icon_decoder_uninit();

//从ISLI标志码图标中解码读取标志码编码
//成功返回1，结果在出参中
//失败返回0
int isli_icon_decoder_do_image_decode(

        //IN,  包含ISLI标志码的图像数据，外框宽度至少5 pxiel
        IMAGE* image,

        //OUT, ISLI编码，11位十进制数（1位服务编码+10位前置码）
        //     或19位十进制数（编码结构参考ISLI应用指引），以字符'0'结尾
        //     全'0'结果仅用于算法测试之目的，App应丢弃之
        //     isli_code的内存长度必须大于等于20字节，否则栈内存会因为内存写溢出而被破坏！
        char isli_code[20],

        //OUT, 返回6个特征点坐标,
        //     无论解码成功与否，只要坐标值不为0均为有效特征点
        //     建议以坐标点为中心画小圆，以指导用户对准目标
        short feax[6], short feay[6]

        );

// 最近一次 do_image_decode 的失败阶段（用于量化分析）
//   0 = 成功
//   1 = locate 失败（未检测到盾牌标记 → 图中无可解码盾牌）
//   2 = trace 失败（定位成功但外框追踪脱轨 → 盾牌存在，stage-3 可救）
//   3 = curve/corner 失败（曲线拟合失败）
//   4 = wave2bits 失败（几何OK但波形解码失败）
//   5 = BCH 失败（纠错不通过）
int islii_get_last_fail_stage();

// 追踪 fallback 开关（默认1=启用）：
//   1 = 先 mode 0(质心) 追踪解码，失败再试 mode 2(stage-3 角点跳跃) —— 保证 HIT 零回归
//   0 = 只用 islii_set_trace_mode 指定的模式（供 A/B 隔离测试）
void islii_set_trace_fallback(int enable);

// 快速模式（默认0=关闭）：激进性能优化，容许准确度下降
//   - 定位扫描步长加倍、BS 容差放宽到 ±12%
//   - 追踪迭代减半、部分弧阈值降低
//   - 跳过 112-bit 回退 + mode-2 重试
void islii_set_fast_mode(int enable);
int  islii_get_fast_mode();

//图像预处理（默认1=对比度拉伸+锐化，改善低对比度盾牌）
void islii_set_preprocess(int enable);
int  islii_get_preprocess();

//Chase 软判决 BCH（逐位翻转重试，A/B隔离）
void islii_set_chase_enable(int enable);
int  islii_get_chase_enable();
void islii_set_chase112_enable(int enable);  // 112-bit Chase（默认0禁用，FP 风险）

// 模型角点预测（默认0=仅对称性修正，1=始终从标记+几何推导4角）
//   P1: 使用 locate 得到的标记位置 + frame_size 直接计算预测角点
//   替代 trace→corner_finder 的角点，消除追踪脱轨对角点的影响
void islii_set_model_corners(int enable);
int  islii_get_model_corners();

// 直接采样（默认0=曲线拟合+弧长采样，1=直接从trace点线性插值采样）
//   P2: 跳过三次多项式曲线拟合，使用 trace 点的分段线性弧长参数化
void islii_set_direct_sample(int enable);
int  islii_get_direct_sample();

// === 诊断接口（仅用于批量分析瓶颈，不影响解码逻辑）===
// 63bit BCH: decode_bch 返回的 err_num。-1=未跑或 wave2bits 未产出bits，0..5=可纠错数
int islii_get_last_bch_err63();
// 112bit BCH: err_num。-1=未跑或 wave2bits 未产出bits，0..7
int islii_get_last_bch_err112();
// do_wave2bits63 / do_wave2bits112 的返回值（0/1，1=成功产出bits）
int islii_get_last_wave63_ret();
int islii_get_last_wave112_ret();
// 最近一次 trace 的 dot_num（追踪质量）
int islii_get_last_dot_num();
// 拷贝最近一次 compact_bits 后的 9 字节 received 码字（63bit）/ 17 字节（112bit）
void islii_get_last_received63(unsigned char out[9]);
void islii_get_last_received112(unsigned char out[17]);
// 拷贝最近一次 do_wave2bits63 提取的原始 63 bits（未 compact，按 curve0/1/2/3 顺序）
// wave63 失败时仅前若干 curve 有效
void islii_get_last_bits63_raw(unsigned char out[63]);

// BCH 纠错接受上限（默认 63bit=3 / 112bit=7，保守防误纠）
// 诊断用：可放宽到 5/7 测量解码上限；shipped 应保持默认
void islii_set_max_bch_err63(int n);
void islii_set_max_bch_err112(int n);
int  islii_get_max_bch_err63();
int  islii_get_max_bch_err112();

// 曲线采样 try-both（默认1=启用）：direct(P2) 失败后回退多项式拟合重试
void islii_set_curve_try_both(int e);
int  islii_get_curve_try_both();

// c3 长弧同步极性重试（默认1=启用）：63-bit BCH 失败时，尝试 c3 的 4 种强制极性组合，
// 由 BCH err<=3 + re-encode 校验裁决（结构上零回归：仅在自动极性失败时触发）
void islii_set_c3_retry(int e);
int  islii_get_c3_retry();

// c2+c3 联合同步极性重试（默认1=启用）：c3_retry 失败后，枚举 c2×c3 共 16 组极性，
// 取 BCH err 最小的合格组合。救 c2+c3 dominant（两长弧极性均误）。零回归（仅在 c3_retry 失败后触发）
void islii_set_c2_retry(int e);
int  islii_get_c2_retry();

// 同步位置偏移重试（默认1=启用）：c2+c3 同步极性重试失败后，对长弧同步位施 ±1 比特偏移联合重试
void islii_set_pos_retry(int e);
int  islii_get_pos_retry();
// pos_retry 接受阈值（默认2=err<=2）：多重比较下收紧阈值防伪 BCH 可解 FP
void islii_set_pos_retry_max_err(int e);
int  islii_get_pos_retry_max_err();
// pos_retry 单弧偏移扩展（默认1=启用，追加 c2-only/c3-only 各6单弧组合）：
// 联合组合要求两弧均非零偏移，漏掉"仅一弧偏移"的漏救情形（cache2 73 帧 c3=(0,-1) 单弧可修）
void islii_set_pos_retry_single(int e);
int  islii_get_pos_retry_single();

// span 放宽重试（默认1=启用）：g_min_span 下解码失败时，放宽同步跨度到 0.70 fallback 重试
void islii_set_span_retry(int e);
int  islii_get_span_retry();

//退化码字过滤（全1/全0 数据字），默认开启
void islii_set_reject_degenerate(int e);
int  islii_get_reject_degenerate();
int  islii_selftest_degenerate_guard(void);  //返回1=guard 逻辑正确（ON拒全1/全0，OFF放行）

//阶段计时（微秒）：[1]trace [2]corner [3]curve [4]wave [5]bch
void islii_set_timing_enable(int e);
void islii_reset_stage_timing(void);
void islii_get_stage_timing(long long out[6]);

#endif

