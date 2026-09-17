# Xcode 26 兼容性检查清单（fmlink / 泛媒关联）

> 用途：把当前代码拿到一台 **macOS 26 + Xcode 26** 的新机器上编译时，按本清单逐项验证与排障。
> 生成日期：2026-09-16　｜　基线环境：macOS 12.7.6 + Xcode 14.0 + Flutter 3.27.5-ohos-1.0.4 + CocoaPods 1.14.3
>
> **本清单是纯静态体检结论 + 排障手册，未在 Xcode 26 上实测过。**

---

## 0. TL;DR

| 判断 | 结论 |
|---|---|
| 能否编译通过 | **大概率可以**（工具链层无已知硬伤，详见第 2 节） |
| 能否直接归档上架 | **不能**——部署目标 `iOS 12.0` 超出 Xcode 26 支持的 `iOS 15–26` 范围 |
| 需要改代码吗 | 不改代码（Dart 层）；只需调整 iOS 部署目标 + 可能升级 CocoaPods |
| 最大不确定项 | Flutter SDK 是鸿蒙分支 `3.27.5-ohos-1.0.4`，官方未对 Xcode 26 做过适配声明 |

---

## 1. 环境基线（Apple 官方数据）

来源：[SDKs and system requirements](https://developer.apple.com/support/xcode/)

| Xcode | 支持的 macOS | SDK | Deployment Target | Swift |
|---|---|---|---|---|
| Xcode 26 | Sequoia 15.6 – Tahoe 26.x | iOS 26 | **iOS 15–26** | 6.2（语言模式 6 / 5 / 4.2 / 4） |
| Xcode 26.6 | Tahoe 26.2 – Tahoe 26.x | iOS 26.5 | iOS 15–26.5 | 6.3 |

要点：

- macOS 26（Tahoe）满足 Xcode 26 的系统要求 ✅
- **Deployment Target 最低为 iOS 15**，而本项目是 `12.0` ⚠️
- Swift 语言模式仍支持 5，本项目 `SWIFT_VERSION = 5.0` 不受 Swift 6 严格并发影响 ✅

---

## 2. 代码 / 工程体检结果（本轮已核查）

### 2.1 已确认安全的项目（在新机器上若出现同类报错，说明是**环境问题**而非代码问题）

| 检查项 | 结果 | 证据 |
|---|---|---|
| `xcode_backend.sh` 是否调用 Xcode 已移除的工具（`bitcode_strip` 等） | ✅ 无 | grep `Flutter/packages/flutter_tools/bin/xcode_backend.sh` 为空 |
| `podhelper.rb` 是否使用 `DT_TOOLCHAIN_DIR` | ✅ 无 | grep 结果为空 |
| Pods 产物是否含 `DT_TOOLCHAIN_DIR`（Xcode 16+ 会**直接报错**） | ✅ 无 | `grep -rn DT_TOOLCHAIN_DIR ios/Pods --include="*.xcconfig"` 为空 |
| `ENABLE_USER_SCRIPT_SANDBOXING` | ✅ 已设 `NO`（3 个配置） | `ios/Runner.xcodeproj/project.pbxproj` |
| Xcode 15+ 最常见的 Flutter 构建失败原因即此项，已规避 | | |
| 本地 native C++/ObjC++ 是否使用 Xcode 26 已移除的 libc++ 设施 | ✅ 无 | grep `<ciso646>`/`<ccomplex>`/`<cstdalign>`/`<cstdbool>`/`<ctgmath>`/`uncaught_exception`/`std::barrier`/`<latch>`/`atomic::wait`/`allocator<const>` → 空 |
| 本地 native 编译标准 | ✅ `c++11` + `libc++`，向下兼容 | `packages/mobile_scanner/ios/ISLIWrappers/*.podspec` |
| Swift 语言模式 | ✅ 工程与 `mobile_scanner` 均为 `5.0` | `SWIFT_VERSION` / `s.swift_version` |
| `ENABLE_BITCODE` | ✅ `NO`（Xcode 16 起已彻底移除 bitcode，该设置无害） | pbxproj |
| 工程文件格式 | ✅ `objectVersion = 54`，Xcode 26 可直接打开（会提示可升级，不影响编译） | pbxproj |
| 依赖成熟度 | ✅ `WechatOpenSDK-XCFramework 2.0.7`（含 `ios-arm64` + `ios-arm64_x86_64-simulator` 切片）、`FMDB 2.7.12`、`TOCropViewController 2.6.1` | `ios/Podfile.lock` |
| iOS 平台代码逻辑（Dart） | ✅ 与 Xcode 版本无关，引擎为预编译产物 | — |

### 2.2 待在新机器上验证的项目

| # | 待验证项 | 风险 | 判定方式 |
|---|---|---|---|
| 1 | **部署目标 12.0 超出支持范围** | 中（编译期通常仅 warning；归档上传会被拒） | 见第 4 节 R1 |
| 2 | **CocoaPods 1.14.3 偏旧** | 中 | 见第 4 节 R2 |
| 3 | **Xcode 26 默认开启 Swift explicit modules** | 中 | 见第 4 节 R3 |
| 4 | **Flutter 鸿蒙分支 3.27 的 `flutter_tools` 解析 `xcodebuild` 输出** | 中（历史上最脆弱环节） | 见第 5 节步骤 5 |
| 5 | 老 ObjC 库（TOCropViewController 2.6.1）在新 clang 下编译 | 低 | 观察 pod 编译输出 |

---

## 3. 新机器准备

```bash
# 1) Xcode 26 安装并激活（要求 macOS Sequoia 15.6+ / Tahoe 26.x）
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -runFirstLaunch          # 安装组件、同意许可
xcodebuild -version                      # 应为 Xcode 26.x

# 2) Ruby / CocoaPods（建议 ≥ 1.16）
ruby -v                                  # 建议 3.x
sudo gem install cocoapods               # 或 brew install cocoapods
pod --version

# 3) Flutter（本项目使用 ohos 分支）
flutter --version                        # 需为 3.27.5-ohos-1.0.4 或该分支更新版本
flutter doctor -v
flutter precache --ios
```

> ⚠️ 若 `flutter doctor` 报 Xcode 版本相关告警，先确认是「版本过低」还是「未授权/未首次运行」，后者可用 `sudo xcodebuild -runFirstLaunch` 解决。

---

## 4. 风险速查表（报错 → 病因 → 处置）

### R1 · 部署目标

**症状**
```
warning: The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 12.0,
but the range of supported deployment target versions is 15.0 to 26.0.
```
**病因**：Xcode 26 的 Deployment Target 支持范围为 iOS 15–26。
**影响**：本地编译一般**不阻断**（仅 warning）；但 `flutter build ipa` / 归档上传到 App Store Connect **会被拒**。
**处置（按需选一）**：

- 方案 A（推荐，配合 Xcode 26 上架）：把部署目标统一提到 `15.0`
- 方案 B（需保留 iOS 12–14 支持）：改用 **Xcode 16.x** 构建（Xcode 26 无法降级支持）

需要同步修改的位置（**本次未改动，仅预案**）：

| 文件 | 现值 | 需改为 |
|---|---|---|
| `ios/Podfile` | `platform :ios, '12.0'` | `15.0` |
| `ios/Runner.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 12.0` ×3（项目级 Debug/Release/Profile；Runner target 继承该值，未单独设置） | `15.0` |
| `ios/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion = 12.0` | `15.0` |
| `packages/mobile_scanner/ios/ISLIWrappers/isli_icon_native.podspec` | `s.ios.deployment_target = '12.0'` | `15.0` |
| `packages/mobile_scanner/ios/ISLIWrappers/isli_line_native.podspec` | 同上 | `15.0` |
| `packages/mobile_scanner/ios/mobile_scanner.podspec` | 同上 | `15.0` |

> ⚠️ 业务代价：提到 15.0 后 iOS 12–14 设备将无法安装本 App。

### R2 · CocoaPods 过旧

**症状**
```
DT_TOOLCHAIN_DIR cannot be used to evaluate LIBRARY_SEARCH_PATHS, use TOOLCHAIN_DIR instead
```
或 pod 脚本阶段异常。
**病因**：Xcode 16 起改变了该变量的求值方式，CocoaPods 在 1.15.2 才修复；本项目 lock 文件记录为 `1.14.3`。
**备注**：本轮实测**当前 Pods 产物中并不含该变量**，所以此风险只在"新机器上重新 `pod install`"时可能出现。
**处置**：升级到 CocoaPods ≥ 1.16 后 `cd ios && rm -rf Pods Podfile.lock && pod install`。

### R3 · Swift explicit modules

**症状**：Swift 编译期出现 `missing required module` / `module map` / 找不到依赖模块类错误。
**病因**：Xcode 26 起 Swift explicit modules 成为所有 Swift target 的默认构建模式（Apple release notes 明确说明）。
**处置**：在 `ios/Runner.xcodeproj` 的 Build Settings 或 Podfile `post_install` 中加：

```ruby
config.build_settings['SWIFT_ENABLE_EXPLICIT_MODULES'] = 'NO'
```

### R4 · 其他

| 症状 | 病因 | 处置 |
|---|---|---|
| `Sandbox: bash(...) deny file-write-create` / `Operation not permitted` | `ENABLE_USER_SCRIPT_SANDBOXING = YES` | ✅ 本项目已设 `NO`；若仍出现，检查 pod 生成的 xcconfig 是否覆盖 |
| `Sandbox: rsync ... deny` | 同上 | 同上 |
| `errCode` 类微信问题（非编译） | Universal Link / 签名不匹配 | 见 `docs/微信UniversalLink配置说明.md` |
| `xcrun: error: unable to find utility "bitcode_strip"` | 老 Flutter 脚本调用已移除工具 | ✅ 本项目脚本无此调用；若出现说明 Flutter SDK 被替换过 |
| 链接期 `Undefined symbol` 且与 Swift 运行时相关 | Flutter 引擎与 Xcode 链接器版本差异 | 优先升级 Flutter 到官方支持 Xcode 26 的版本 |

---

## 5. 验证步骤（可直接逐条执行）

```bash
# ① 环境自检
flutter doctor -v

# ② 依赖解析
flutter clean && flutter pub get

# ③ 重建 Pods（关键：验证 R2，务必用 ≥1.16 的 CocoaPods）
cd ios && rm -rf Pods Podfile.lock ~/Library/Developer/Xcode/DerivedData && pod install && cd ..

# ④ Debug 构建（先跑这个，最快暴露问题）
flutter build ios --no-codesign --debug

# ⑤ Release 构建（验证优化与链接）
flutter build ios --no-codesign --release

# ⑥ 模拟器构建（验证 arm64-sim 切片）
flutter build ios --simulator

# ⑦ 归档验证（验证 R1 —— 部署目标超范围会在这里被拒）
flutter build ipa --no-codesign        # 或 flutter build ipa（需签名）
```

**判定标准**：

- ④⑤⑥ 全绿 → 编译链路通过，仅剩 R1 的上架限制；
- 只有 R1 的 warning → 可正常运行，但归档会被 App Store Connect 拒绝；
- ③ 失败 → 多为 CocoaPods 版本/环境问题（R2）；
- ⑤ 失败而 ④ 成功 → 多为优化相关的 libc++/链接器问题，优先查 native 代码与 pod 编译日志。

---

## 6. 兜底方案

| 场景 | 方案 |
|---|---|
| 必须保留 iOS 12–14 支持 | 在 **Xcode 16.x** 上构建（Xcode 16 支持更低部署目标），不使用 Xcode 26 |
| 必须用 Xcode 26 但编译持续失败 | 升级 Flutter 到官方支持 Xcode 26 的版本（官方在 3.35+ 一代开始适配，3.38 引入 iOS 侧 `UISceneDelegate` 迁移）。注意本项目为 ohos 分支，升级需同步确认 `ohos/` 目录适配 |
| 只想先看到界面跑起来 | 用 Android / HarmonyOS 侧构建验证业务逻辑，iOS 侧单独排障 |

---

## 7. 一句话总结

> 代码本身对 Xcode 26 没有明显硬伤；**唯一的确定性问题是部署目标 `12.0` 低于 Xcode 26 支持的 `15.0` 下限**——
> 本地编译大概率只报 warning，但**归档上架必须改到 15.0**。其余风险集中在 CocoaPods 版本、Swift explicit modules 和 Flutter 鸿蒙分支的工具链适配，按第 4 节对照处置即可。
