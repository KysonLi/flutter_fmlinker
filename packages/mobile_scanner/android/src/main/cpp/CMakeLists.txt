cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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
