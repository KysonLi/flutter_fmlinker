cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================
# FL 系列 —— 灰度双横线检测器级联（LineLocator）。
# ILD_FL2: 置信紧裁剪级联（检测→紧裁剪→共用尾段，失败回落旧路径）
# ILD_FL3: 检测几何直接播种，跳过 vertical_locating 纹理匹配
# PC 台架 1798 图 A/B 已过线（mis=0 / 真回归=0 / rescue +9）；
# 真机 A/B（2026-08-19 两轮）净负：置信路径 0 次解码成功（种子 avgW 偏差
# 致边界 BCH 翻转）+ 检测器失败帧税 25-100ms → 默认关闭。
# ⚠️ 改回 ON 做真机试验后必须清 CMake 缓存（flutter clean / 删 .cxx），
#    否则缓存里的旧值会盖过本行的 OFF，构建仍是 FL 开启态。
# ============================================================
set(ILD_FL_ENABLED, ON)
option(ILD_FL_ENABLED "ISLI line: FL-T 张量独立解码（真机试验开关，失败即终不回落）" ON)



# ============================================================
# Force Release build — default on Android NDK is Debug which
# disables all compiler optimizations (5-10x slower).
# This alone explains why the same algorithm takes 652-1595ms
# on mobile vs 13.7ms on PC.
# ============================================================
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_library(log-lib log)

# ============================================================
# ISLI icon (2D) decoder
# ============================================================
add_library(isli_icon_decoder SHARED
    ISLIDecoderBridge.cpp
    isli/ISLIIconDecoder.cpp
    isli/bch.cpp
    isli/Binarization.cpp
    isli/BSPatternMatch.cpp
    isli/CircleArea.cpp
    isli/CornerFinetuner.cpp
    isli/CornerFinder.cpp
    isli/CurveFit.cpp
    isli/FrameTracer.cpp
    isli/CurveSampler.cpp
    isli/Filter.cpp
    isli/ISLIIconLocator.cpp
    isli/LineSampler.cpp
    isli/LineScanner.cpp
    isli/MatrixSolver.cpp
    isli/Wave2Bits.cpp
)

target_include_directories(isli_icon_decoder PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/isli
)

target_link_libraries(isli_icon_decoder ${log-lib})

# ============================================================
# ISLI line (1D) decoder — optimized
# ============================================================
add_library(isli_line_decoder SHARED
    LineCodeDecoderBridge.cpp
    linecode/ISLILineDecoder.cpp
    linecode/BarLocator.cpp
    linecode/bch.cpp
    linecode/BchHelper.cpp
    linecode/BSPatternMatch.cpp
    linecode/Common.cpp
    linecode/CurveFit.cpp
    linecode/CurveSampler.cpp
    linecode/Filter.cpp
    linecode/GaussianBinarization.cpp
    linecode/LineLocator.cpp
    linecode/LineTensor.cpp
#   linecode/kiss_fft.cpp              # REMOVED: FFT blur rejects valid barcodes
    linecode/MatrixSolver.cpp
    linecode/TImage.cpp
    linecode/Wave2Bits.cpp
)

target_include_directories(isli_line_decoder PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/linecode
)

target_link_libraries(isli_line_decoder ${log-lib})

# ============================================================
# Optimization: Gaussian binarization is compute-bound (60-75%
# of decode time). -O3 enables auto-vectorization and loop
# unrolling which are critical on ARM Cortex CPUs.
# Expected speedup: 3-5x vs default Debug, 2-3x vs -O2.
# ============================================================
if(ANDROID)
    target_compile_options(isli_line_decoder PRIVATE -O3)
    # Gaussian blur is already hand-vectorized (ILD_NEON path, 8px/iter via
    # arm_neon.h; arm64-v8a has NEON by default, no -mfpu needed).
endif()

# FL-T 独立解码（用户决定 2026-08-20）：LineTensor 结构张量 + top-3 候对
# 紧裁剪仲裁，失败即终不回落旧路径。PC bench 1798 图：456 vs 旧 375（净+81，
# FP4/mis2，代价 -35 GT 帧）；零码守卫内置。⚠️ 试验后清 CMake 缓存再改回 OFF。
if(ILD_FL_ENABLED)
    target_compile_definitions(isli_line_decoder PRIVATE ILD_FLT)
endif()
