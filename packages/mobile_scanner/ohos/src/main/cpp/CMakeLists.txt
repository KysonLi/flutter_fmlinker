cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Force Release build for consistent performance
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# OHOS NDK libraries
find_library(napi-lib ace_napi.z)
find_library(hilog-lib hilog_ndk.z)

# ============================================================
# ISLI icon (2D) decoder
# ============================================================
add_library(isli_icon_decoder SHARED
    ISLIDecoderNapi.cpp
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

# ISLI_PLATFORM_OHOS: routes the shared IldLog.h logging macros to hilog
# (instead of stderr) and keeps them emitting under Release/NDEBUG so real-
# device decode diagnostics are visible. No effect on Android copies.
target_compile_definitions(isli_icon_decoder PRIVATE ISLI_PLATFORM_OHOS=1)

target_link_libraries(isli_icon_decoder ${napi-lib} ${hilog-lib})

# ============================================================
# ISLI line (1D) decoder — optimized
# ============================================================
add_library(isli_line_decoder SHARED
    ISLILineDecoderNapi.cpp
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

target_compile_definitions(isli_line_decoder PRIVATE ISLI_PLATFORM_OHOS=1)

target_link_libraries(isli_line_decoder ${napi-lib} ${hilog-lib})

# ============================================================
# Optimization: Gaussian binarization is compute-bound (60-75%
# of decode time). -O3 enables auto-vectorization and loop
# unrolling which are critical on ARM Cortex CPUs.
# ARM64 has NEON by default (used via arm_neon.h guarded by
# #if defined(__aarch64__)).
# ============================================================
target_compile_options(isli_line_decoder PRIVATE -O3)
