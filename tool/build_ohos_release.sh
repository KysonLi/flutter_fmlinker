#!/usr/bin/env bash
# 鸿蒙发布包构建脚本
#
# 步骤：
#   1. 由本地签名材料（signature/signing.env 或环境变量）生成 ohos/build-profile.json5
#   2. 打出 release HAP，并把 Dart 符号表单独留存（用于崩溃堆栈还原）
#
# 产物：
#   --app  → .app 应用包（AppGallery 上架/版本管理上传用）
#   (默认) → .hap 模块包（真机安装/内部调试用）
#
# 用法：
#   tool/build_ohos_release.sh                 # 生成 .hap
#   tool/build_ohos_release.sh --app           # 生成 .app（上架用）
#   OBFUSCATE=1 tool/build_ohos_release.sh     # 额外开启 Dart 混淆（需回归验证）
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="hap"
if [[ "${1:-}" == "--app" ]]; then
  MODE="app"
fi

dart run tool/gen_ohos_build_profile.dart

SYMBOL_DIR="build/ohos-symbols"
ARGS=(--release --split-debug-info="$SYMBOL_DIR")
if [[ "${OBFUSCATE:-0}" == "1" ]]; then
  ARGS+=(--obfuscate)
  echo "已开启 Dart 混淆：产物符号表在 $SYMBOL_DIR（排查崩溃务必保留）"
fi

if [[ "$MODE" == "app" ]]; then
  flutter build app "${ARGS[@]}"
else
  flutter build hap "${ARGS[@]}"
fi

# 复制到稳定的产物目录，避免后续 debug 构建把 release 包覆盖掉
VERSION_NAME=$(sed -n 's/.*"versionName": *"\([^"]*\)".*/\1/p' ohos/AppScope/app.json5 | head -1)
VERSION_CODE=$(sed -n 's/.*"versionCode": *\([0-9]*\).*/\1/p' ohos/AppScope/app.json5 | head -1)
DIST_DIR="build/dist"
mkdir -p "$DIST_DIR"
SRC=$(find ohos -name "*-signed.${MODE}" -path "*outputs/default*" -newermt '-30 minutes' 2>/dev/null | head -1)
if [[ -z "$SRC" ]]; then
  SRC=$(ls -t ohos/entry/build/default/outputs/default/*-signed.${MODE} 2>/dev/null | head -1)
fi
if [[ -z "$SRC" ]]; then
  echo "未找到构建产物（*-signed.${MODE}）" >&2
  exit 1
fi
OUT="$DIST_DIR/fmlink-${VERSION_NAME}-${VERSION_CODE}-release.${MODE}"
cp "$SRC" "$OUT"

echo
echo "发布包：$OUT"
echo "大小：$(du -h "$OUT" | cut -f1)"
echo "SHA256：$(shasum -a 256 "$OUT" | cut -d' ' -f1)"
echo "符号表：$SYMBOL_DIR"
echo "还原堆栈：flutter symbolize -i <堆栈文件> -d $SYMBOL_DIR"

# 自动校验签名（有 DevEco 工具链时）
JAVA_BIN="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java"
SIGN_TOOL="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
if [[ -x "$JAVA_BIN" && -f "$SIGN_TOOL" ]]; then
  TMP_DIR=$(mktemp -d /tmp/hapverify.XXXXXX)
  if "$JAVA_BIN" -jar "$SIGN_TOOL" verify-app -inFile "$OUT" \
      -outCertChain "$TMP_DIR/chain.cer" -outProfile "$TMP_DIR/profile.p7b" >/dev/null 2>&1; then
    PROFILE_TYPE=$(strings "$TMP_DIR/profile.p7b" | grep -o '"type":"[^"]*"' | head -1)
    echo "签名校验：通过，Profile ${PROFILE_TYPE}"
  else
    echo "签名校验：失败（请检查签名材料）"
  fi
  rm -rf "$TMP_DIR"
fi
