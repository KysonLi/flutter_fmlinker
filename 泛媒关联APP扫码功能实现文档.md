# 泛媒关联APP 扫码功能实现文档

> 版本：1.0　日期：2026-08-17　涉及分支：main

## 1. 功能概述

本次实现完成「扫码」tab 及 `/scan` 路由的完整扫码功能，支持三类码制的识别与解析：

| 码制 | 说明 | 识别方式 |
|---|---|---|
| **ISLI 线码（链码）** | 嵌在书页文本行间隙、外观类似"双下划线"的码 | 自研 native 解码器（C++）逐帧识别 |
| **ISLI 图标码（标志码）** | 书籍封底方形 ISLI 标志码 | 自研 native 解码器（C++）逐帧识别 |
| **普通二维码/条码** | QR、EAN-13 等标准格式 | Android MLKit / OHOS ScanKit |

扫到 ISLI 码后调用后端接口解析其关联的数字资源（图文、音视频、3D、HTML 等）并跳转结果页展示。

## 2. 总体架构

扫码能力由本地 vendored 的 `packages/mobile_scanner`（基于 mobile_scanner 7.0.1，含 OHOS 适配与自研 ISLI 解码扩展）提供：

```
┌─ Dart 层（App）──────────────────────────────────────────┐
│ ScanScreen ──onDetect──► 分流/去重 ──► LinkService V2 API │
│      │                                                    │
│ MobileScannerController（formats 留空 = 全格式）           │
└──────┬───────────────────────────────────────────────────┘
       │ MethodChannel / EventChannel（标准化 Barcode 数据）
┌──────┴─ Native 层（Android Kotlin / OHOS ArkTS）─────────┐
│ ① 普通条码：MLKit（Android）/ ScanKit（OHOS）             │
│ ② ISLI 解码：cpp/isli（C++，BCH 纠错 + 波形采样 + 级联）  │
│    ├─ ISLILineDecoder（线码）                             │
│    └─ ISLIIconDecoder（图标码）                           │
│ 帧回调 → Y 平面灰度图 → TaskPool/异步解码 → 命中即回抛    │
└──────────────────────────────────────────────────────────┘
```

### 2.1 关键机制

- **格式门控**：native 侧按 Dart 传入的 `formats` 决定是否启用 ISLI 解码 —— **留空（或含 `all`）时两种 ISLI 解码全部启用**。业务侧 `MobileScannerController()` 不传 `formats`，即同时支持 ISLI 线码、图标码与普通码。
- **识别结果契约**：ISLI 命中以标准 `Barcode` 结构回抛 —— `format` 为自定义枚举值（`isli_line_code` = 16384，`isli` = 8192），`rawValue` 即 ISLI 码字符串（11 或 19 位数字），`corners` 为特征点。
- **串行解码保护**：native 侧同一时刻仅允许一帧 ISLI 解码（busy 标记），线码单帧解码耗时约 2s，期间新帧丢弃。
- **扫描窗口**：传入 `scanWindow` 后 native 仅解码取景框内区域（旋转感知裁剪），提高命中率并降低 CPU。

## 3. App 侧实现

### 3.1 扫码页 `lib/screens/scan/scan_screen.dart`

全屏深色扫描界面（作为 MainScreen 第 3 个 tab，亦可经 `/scan` 路由独立访问）：

- **扫描窗口**：宽 0.8 屏宽 × 高 0.62 倍宽的居中矩形（线码扁长、图标码近方形，折中取偏扁），配四角括号 + 往返扫描线遮罩（`_ScannerOverlayPainter`）
- **顶部**：帮助入口 → `/scan/help`
- **底部操作**：手电筒（状态联动 controller.torchState）/ 相册识码 / 手动输入链码
- **相册识码**：`image_picker` 选图 → `controller.analyzeImage(path, scanWindow: 整图)`，显式传 `(0,0,1,1)` 全图窗口，避免复用实时扫描窗口把相册图裁掉；native 侧 ISLI 解码本身走整图
- **手动输入**：校验 stripping 后 10~20 位纯数字

**识别分流（`_handleValue`）**：

1. `format == isli / isli_line_code` → 直接按 ISLI 码解析
2. 普通码内容为 10~20 位数字（可含连字符）→ 视为 ISLI 码解析
3. `http/https` 链接 → 弹窗确认后经 `/webview` 打开
4. 其余内容 → toast 提示

**稳定性处理**：同一码值 3 秒去重；解析期间 `_isHandling` 屏蔽新回调；跳转结果页前 `controller.stop()`、返回后 `start()`（扫码 tab 在导航栈底保持挂载，必须手动停相机）。

### 3.2 解析与跳转流程

```
扫码命中
  └─ UserService.refreshToken()        // 冷启动后恢复内存 token（Constants.token）
      └─ LinkService.getTargetsWithIsliCodeV2(code)   // GET /target-goods/app/v1/source/scan?isli_code=…
          ├─ status == true → context.push('/scan/result', extra: {isliCode, data})
          └─ status == false → EasyLoading.showError(msg)
```

### 3.3 结果页 `lib/screens/scan/scan_result_screen.dart`（新增）

- 顶部码卡片（ISLI 码 + 资源数），若返回含 `goodsName/goodsImage` 则展示书籍信息卡
- 资源列表：类型图标 + 名称 + 类型标签；点击打开
  - 有 URL → `/webview`（网页/音视频/图片统一承载，webview_flutter 含 OHOS 适配）
  - 无 URL 有文本 → 文本查看页（`SelectableText`）
- **响应结构容错**：`/source/scan` 接口无文档，`_parseResult` 依次尝试 `targetList/targets/resourceList/…` 等常见列表键名，字段取 `targetName/url/content/targetType` 等并集；类型判定优先 `targetType`（ISLITargetType 编码：1 文本/2 图片/3 音频/4 视频/5 网页/6 3D），缺省按 URL 后缀推断
- 空结果态：提示「该码暂未关联资源」并展示码值

### 3.4 路由

`lib/routes/app_router.dart` 新增 `/scan/result`，入参经 `state.extra`（`{isliCode, data}` map），遵循项目「富对象走 extra」的路由约定。

## 4. 平台适配

### 4.1 Android

| 事项 | 说明 |
|---|---|
| `compileSdkVersion` 33 → **34** | mobile_scanner Kotlin 源使用 CameraX 1.3.0+ API（`ExperimentalLensFacing`/`ResolutionSelector`），而 CameraX 1.3.x、MLKit 17.3.x 的 AAR 均声明 `minCompileSdk=34`（实测 1.3.1/1.3.4 皆然，降级依赖则编译失败）。AGP 7.2 对 compileSdk 34 仅"未测试"警告，可正常构建。**targetSdk 仍为 33，运行时行为不变** |
| `applicationId` 补全迁移 | `com.isli.fmlink` → `com.mpr.chaincode`（manifest/MainActivity 在前次提交已完成迁移，build.gradle 漏改；不补全会作为第二个 app 安装） |
| native 构建 | NDK 27.0.12077973 + CMake 3.22.1 编译 `cpp/isli` 解码器；`old_isli_decoder/` 参考实现已被包内 .gitignore 排除、不参与编译 |
| 依赖锁定 | mlkit barcode-scanning 17.3.0 / CameraX 1.3.4 / kotlinx-coroutines 1.7.3（kotlinx 保持向下兼容元数据，Kotlin 1.7.10 可编译） |

### 4.2 OHOS（HarmonyOS）

- `ohos/entry/src/main/module.json5`：`requestPermissions` 新增 **`ohos.permission.CAMERA`**（原先仅有 INTERNET，扫码在鸿蒙上必失败），`usedScene` 限 `inuse`
- `resources/base|zh_CN/element/string.json`：新增 `camera_reason`（权限用途说明，user_grant 权限必填）
- 插件 har 由 `flutter pub get` 挂载（`ohos/entry/oh-package.json5` → `../har/mobile_scanner.har`）；`*.har` 引擎二进制不入库，缺失时由 OHOS 工具链重新生成

## 5. 变更文件清单

| 文件 | 变更 |
|---|---|
| `pubspec.yaml` / `pubspec.lock` | 新增 `mobile_scanner`（path: packages/mobile_scanner）依赖 |
| `lib/screens/scan/scan_screen.dart` | 重写占位页为完整扫码页 |
| `lib/screens/scan/scan_result_screen.dart` | **新增** 扫码结果页 |
| `lib/routes/app_router.dart` | 新增 `/scan/result` 路由 |
| `android/app/build.gradle` | compileSdk 34、applicationId 补全迁移 |
| `ohos/entry/src/main/module.json5` | CAMERA 权限 |
| `ohos/entry/src/main/resources/{base,zh_CN}/element/string.json` | camera_reason |
| `macos/Flutter/GeneratedPluginRegistrant.swift`、`ohos/entry/oh-package.json5` | pub get 自动注册 |
| `packages/mobile_scanner/` | **新增整目录**（vendored 扫码库，514 文件；构建产物与 `*.har`、`old_isli_decoder/` 已被包内 .gitignore 排除） |

## 6. 验证情况与已知事项

- `flutter analyze`：新增/改动 Dart 文件 0 告警（全仓存量 160 条均为原有 `avoid_print` 等，与本次无关）
- `flutter build apk --debug`：构建通过；已在 Android 真机（MIA AL00 / Android 12）安装启动，相机权限弹窗正常
- **待办**：
  - 真机对准实际书页链码/封底图标码验证识别率与结果页字段（`/source/scan` 返回结构无文档，字段对不上时仅需调整 `ScanResultScreen._parseResult` 的键名列表）
  - OHOS 真机/HAP 构建验证（`flutter build hap`）
  - 视频/音频目前统一经 WebView HTML5 播放，如需原生播放（video_player 已在依赖中）可后续迭代
