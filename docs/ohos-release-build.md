# 鸿蒙（OHOS）发布构建说明

> 目标：**仓库不出现任何签名私钥/密码**，换机器或 CI 只需提供签名材料即可构建发布包。

## 1. 签名材料放哪

所有签名文件放在 `signature/`（该目录已被 `.gitignore` 忽略，禁止入库）：

| 文件 | 说明 |
|---|---|
| `*.p12` | 密钥库（debug 联调用 `fmlinker-debug.p12`，上架用 AGC 的发布证书） |
| `*.p7b` | Profile（debug 联调 `type=debug`；上架必须是 AGC 签发的 `type=release`） |
| `*.cer` | 证书链 |
| `signing.env` | 本机签名参数（下节），同样不入库 |

### signing.env 格式

```dotenv
# 路径可写相对仓库根目录，也可写绝对路径
SIGNING_STORE_FILE=signature/fmlinker-debug.p12
# ⚠️ 必须是 DevEco 加密后的密文（十六进制、长度≥32），不能填明文
SIGNING_STORE_PASSWORD=00000018xxxxxxxx...
SIGNING_KEY_ALIAS=fmlinker
SIGNING_KEY_PASSWORD=000000189xxxxxxx...
SIGNING_PROFILE=signature/fmlinker-debug.p7b
SIGNING_CERT_PATH=signature/fmlinker-debug.cer
```

**关于密码为什么是密文**：hvigor 会调用 `DecipherUtil` 用 `signature/material/{fd,ac,ce}`
解密 `storePassword` / `keyPassword`，传明文会直接报 `INVALID_DATA`（构建退出码 255）。
拿到密文的方式：在 DevEco Studio 里配一次签名（Project Structure → Signing Configs），
DevEco 会同时生成 `signature/material/` 与加密后的密码串。

> 组件签名材料（`*.p12` / `*.p7b` / `*.cer` / `material/`）必须与密文配套使用；
> 换机器/CI 时把整个 `signature/` 目录一起带过去即可（该目录不入库）。

CI 环境可直接用同名环境变量传入（环境变量优先级最高）。

## 2. 生成 build-profile 并构建

```bash
# 生成 ohos/build-profile.json5（每次改动签名材料后执行一次）
dart run tool/gen_ohos_build_profile.dart

# 发布包（附带 Dart 符号表）
tool/build_ohos_release.sh

# 需要开启 Dart 混淆时（务必保留符号表并做回归）
OBFUSCATE=1 tool/build_ohos_release.sh
```

产物：`ohos/entry/build/default/outputs/default/entry-default-signed.hap`

日常 `flutter run -d <ohos-device>` 前也需要保证 `ohos/build-profile.json5` 存在（脚本生成后长期有效）。

> 提示：每次 `flutter build hap` 后，Flutter 工具会把插件模块追加进
> `ohos/build-profile.json5`；重新执行生成脚本会把它还原成模板（插件模块会在下次构建时自动补回），属正常现象。

## 3. 当前签名状态与证书轮换

**当前 `signature/signing.env` 已指向 AGC 发布证书**：

| 配置 | 文件 | 说明 |
|---|---|---|
| 密钥库 | `signature/fmlinker.p12` | 别名 `fmlinker`，私钥公钥指纹 `f7:fc:d0:f7…:6a:89` |
| 证书链 | `signature/Fmlinker.cer` | Root → 中间 CA → `深圳市泛媒网络有限公司(2040743587271955201), Release`（2026-09-16 ~ 2029-09-16） |
| Profile | `signature/fmlinker.p7b` | `type=release`、`bundle-name=com.mpr.chaincode`、`app-identifier=6917616558575214481` |
| 密码密文 | `SIGNING_STORE_PASSWORD` / `SIGNING_KEY_PASSWORD` | 由 `signature/material/` 解密，明文为 `fm123456` |

> ── 已用 `hap-sign-tool verify-app` 校验发布产物：签名校验通过，Profile `type=release`，
> 证书链包含上述 Release 证书，与私钥配对一致。

**换证书（3 年到期或换主体）时**：

1. AGC → 证书管理：用新的 `.csr` 申请发布证书，导出 `.p12`
2. AGC → Profile 管理：新建 **release** Profile，绑定 `bundle-name=com.mpr.chaincode`、
   `app-identifier=6917616558575214481`（必须与微信开放平台登记一致，否则微信登录 `errCode=-1`）
3. 用 DevEco Studio 配一次签名拿到新的密码密文，更新 `signature/signing.env` 并重新执行生成脚本
4. 换签名后必须卸载旧包再安装：`hdc uninstall com.mpr.chaincode`

## 4. 真机自测 vs 发布包（重要）

鸿蒙签名分两类，**发布签名的包装不进普通开发设备**：

| 场景 | 签名 | 产物 | 安装/分发方式 |
|---|---|---|---|
| 真机功能自测 | debug 证书 + debug Profile（绑定设备） | `.hap` | `hdc install` / `flutter run -d <device>` |
| AppGallery 上架/版本管理 | AGC 发布证书 + release Profile | **`.app`**（App Pack） | AGC 上传 `.app` |
| 单模块安装包 | AGC 发布证书 + release Profile | `.hap` | 只能走应用市场，`hdc install` 会报 9568322 |

> **上架一定要传 `.app`**：AGC 的「版本管理 → 上传软件包」只接受 HarmonyOS App Pack（`.app`），
> 选 `.hap` 时文件选择框会置灰。`.app` 内部就是 `entry-default.hap` + `pack.info` + `pac.json`。
>
> 构建：
> ```bash
> tool/build_ohos_release.sh --app     # 产出 build/dist/fmlink-<ver>-<code>-release.app
> tool/build_ohos_release.sh           # 产出 .hap（真机/内部调试）
> ```

直接用 `hdc install` 装发布签名的 HAP 会报：
```
code:9568322 error: signature verification failed due to not trusted app source
```
这是系统策略（设备只信任与其绑定的调试证书），不是打包问题。已经用
`hap-sign-tool verify-app` 确认发布包签名正确。

### 常用命令

```bash
export PATH="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains:$PATH"

# 1) 真机自测：切到调试签名 + 构建安装
dart run tool/gen_ohos_build_profile.dart --debug
flutter run -d <device-id>            # 或 flutter build hap --debug + hdc install

# 2) 出正式包：切回发布签名再构建
dart run tool/gen_ohos_build_profile.dart
tool/build_ohos_release.sh
```

> ⚠️ 切换签名后必须卸载旧包再安装（签名不一致会安装失败）：
> `hdc uninstall com.mpr.chaincode`
>
> ⚠️ 上传 AppGallery 前请确认当前 `ohos/build-profile.json5` 是用**不带 `--debug`** 生成的，
> 并复核产物：`hap-sign-tool verify-app` 输出 Profile `type=release`。

## 5. 其他发布相关

- 版本号：`ohos/AppScope/app.json5` 的 `versionCode` / `versionName` 需与 `pubspec.yaml` 的 `version` 同步递增（AppGallery 以 versionCode 判断升级）
- ArkTS 混淆（arkGuard）：配置在**模块级** `ohos/entry/build-profile.json5`（项目级 schema 不支持该项），规则文件 `ohos/entry/obfuscation-rules.txt`；默认 `enable: false`，开启后必须做一次完整回归
- 崩溃排查：`tool/build_ohos_release.sh` 会把 Dart 符号表输出到 `build/ohos-symbols`，用
  `flutter symbolize -i <堆栈文件> -d build/ohos-symbols` 还原

## 6. 第三方平台签名登记（重要）

换签名后，**依赖签名校验的第三方平台都要同步更新**，否则正式包上对应功能会失败。

随时查看当前证书指纹：

```bash
tool/print_signing_fingerprints.sh                        # 发布证书（默认）
tool/print_signing_fingerprints.sh signature/fmlinker-debug.cer   # 调试证书
```

当前（2026-11，AGC 发布证书 `…,Release`）：

| 指纹 | 值 |
|---|---|
| MD5（32 位） | `16b630d72eacc0151ef6298c0aeed782` |
| SHA1（40 位） | `0cb036fe93ffc3e5707026d8a50ebb13aa71db2d` |
| SHA256（64 位） | `564d4dcfd6f44725024b33bb94b122ef09e93a003890bb85e2405048331bdb8e` |

需要核对/更新的地方：

| 平台 | 字段 | 说明 |
|---|---|---|
| **QQ 互联** | 应用签名（MD5） | 正式包签名变了必须改，否则 QQ 登录/分享签名校验失败 |
| **AGC** | 应用信息 → 证书指纹（SHA256） | 上传 `.app` 时校验，需与发布证书一致 |
| 微信开放平台 | appIdentifier | 鸿蒙登录只校验 `appIdentifier`（`6917616558575214481`），**签名不用改** |
| 华为账号 / IAP | client_id、商品 | 与证书无关，无需改 |
| Android 各商店 | 正式 keystore 的 MD5/SHA256 | 若 Android 也发布，需单独按 Android 正式 keystore 登记 |

> 注意：登记成发布证书指纹后，**debug 证书打的包**在 QQ 侧可能就不再通过校验；
> 建议 QQ 登录以 AppGallery 内部测试的正式包为准做回归。
