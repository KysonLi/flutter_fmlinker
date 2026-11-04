#!/usr/bin/env bash
# 打印签名证书指纹（用于 QQ 互联 / 微信 / AGC 等平台登记）
#
# 用法：tool/print_signing_fingerprints.sh            # 默认打印发布证书（signature/Fmlinker.cer）
#       tool/print_signing_fingerprints.sh <cer 路径>
set -euo pipefail
cd "$(dirname "$0")/.."

CER="${1:-signature/Fmlinker.cer}"
TMP_DIR=$(mktemp -d /tmp/fp.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/certs"

awk -v dir="$TMP_DIR/certs" '
  /BEGIN CERTIFICATE/ { n++; f = dir "/cert_" n ".pem" }
  f { print > f }
  /END CERTIFICATE/ { close(f); f = "" }
' "$CER"

# 叶子证书：subject 里带 Release/Development 的那张；否则取最后一张
LEAF=""
for f in "$TMP_DIR"/certs/*.pem; do
  if openssl x509 -in "$f" -noout -subject | grep -Eq 'Release|Development'; then
    LEAF="$f"
  fi
done
[[ -n "$LEAF" ]] || LEAF=$(ls "$TMP_DIR"/certs/*.pem | sort -V | tail -1)

echo "证书：$(basename "$CER")"
openssl x509 -in "$LEAF" -noout -subject -dates | sed 's/^/  /'
DER="$TMP_DIR/leaf.der"
openssl x509 -in "$LEAF" -outform DER -out "$DER"

echo
echo "MD5    (32 位，QQ 互联常用)：$(openssl dgst -md5    "$DER" | sed 's/.*= //')"
echo "SHA1   (40 位)：             $(openssl dgst -sha1   "$DER" | sed 's/.*= //')"
echo "SHA256 (64 位，AGC 常用)：    $(openssl dgst -sha256 "$DER" | sed 's/.*= //')"
