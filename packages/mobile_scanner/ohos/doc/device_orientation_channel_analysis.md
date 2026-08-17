# deviceOrientationChannel 完整实现分析

> 本文档详细分析了 Android 端 `deviceOrientationChannel` 的作用、架构与实现细节，为鸿蒙（OHOS）平台的对应实现提供参考。

---

## 1. 功能概述

`deviceOrientationChannel` 是一个 Flutter **EventChannel**，用于将 Android 设备的**屏幕方向（UI Orientation）变化**实时、持续地推送给 Flutter（Dart）层。

**核心用途有两个：**

1. **相机预览画面旋转矫正** —— 当底层 `SurfaceProducer` 不支持自动裁剪旋转（`handlesCropAndRotation = false`）时，Flutter 侧需要根据设备方向手动旋转 `Texture` 预览，确保画面始终正向。
2. **状态同步** —— `MobileScannerController` 将当前设备方向存入 `MobileScannerState.deviceOrientation`，供上层业务读取。

---

## 2. 涉及文件一览

| 层级 | 文件路径 | 角色 |
|------|---------|------|
| Android | `MobileScannerHandler.kt` | 桥接层：创建 EventChannel，注册 StreamHandler |
| Android | `DeviceOrientationListener.kt` | **核心类**：同时充当 `BroadcastReceiver`（监听系统方向变化）和 `EventChannel.StreamHandler`（管理 Flutter 事件流 sink） |
| Android | `MobileScanner.kt` | 调用层：在 `start()` / `stop()` 时控制方向监听的启停 |
| Android | `utils/DeviceOrientationExtension.kt` | 工具：枚举→字符串序列化 |
| Android | `objects/MobileScannerStartParameters.kt` | 启动参数数据类，包含 `naturalDeviceOrientation` |
| Flutter | `mobile_scanner_method_channel.dart` | Dart 侧：声明 EventChannel 并消费事件流 |
| Flutter | `parse_device_orientation_extension.dart` | Dart 侧：字符串→枚举反序列化 |
| Flutter | `rotated_preview.dart` | Flutter 侧：根据方向流旋转相机预览 Texture |
| Flutter | `mobile_scanner_controller.dart` | 控制器层：监听方向流并更新 state |
| Flutter | `mobile_scanner_state.dart` | 状态类：持有当前 `deviceOrientation` |

---

## 3. Android 端实现细节

### 3.1 通道名称

```kotlin
const val CHANNEL_NAME = "dev.steenbakker.mobile_scanner/scanner/deviceOrientation"
```

此为 **EventChannel**（而非 MethodChannel），特点是从 Native 端向 Flutter 端**持续推送事件**。

### 3.2 初始化（`MobileScannerHandler.init`）

```kotlin
// MobileScannerHandler.kt:81, 94-107

private var deviceOrientationChannel: EventChannel? = null

init {
    // 1. 创建监听器实例，传入 Activity
    val deviceOrientationListener = DeviceOrientationListener(activity)

    // 2. 创建 EventChannel
    deviceOrientationChannel = EventChannel(
        binaryMessenger,
        "dev.steenbakker.mobile_scanner/scanner/deviceOrientation"
    )

    // 3. 将 DeviceOrientationListener 注册为 StreamHandler
    deviceOrientationChannel!!.setStreamHandler(deviceOrientationListener)

    // 4. 将同一个监听器实例传给 MobileScanner，供其控制 start/stop
    mobileScanner = MobileScanner(
        activity, textureRegistry, callback, errorCallback,
        deviceOrientationListener  // ← 关键：同一个实例
    )
}
```

**关键设计**：`DeviceOrientationListener` 的**同一个实例**同时被 `EventChannel` 和 `MobileScanner` 持有。
- EventChannel 只负责管理 Flutter 侧的 sink（`onListen` / `onCancel`）
- MobileScanner 负责控制系统 BroadcastReceiver 的注册与注销（`start()` / `stop()`）

### 3.3 DeviceOrientationListener 类详解

```kotlin
// DeviceOrientationListener.kt

class DeviceOrientationListener(
    private val activity: Activity,
) : BroadcastReceiver(), EventChannel.StreamHandler {
```

这是一个**双重身份**的类：

| 接口 | 职责 | 调用时机 |
|------|------|---------|
| `BroadcastReceiver` | 监听 Android 系统 `ACTION_CONFIGURATION_CHANGED` 广播 | 系统配置变化（含屏幕旋转） |
| `EventChannel.StreamHandler` | 管理 Flutter 端事件流的订阅与取消 | Flutter 侧调用 `receiveBroadcastStream()` 或取消订阅 |

#### 3.3.1 成员变量

```kotlin
// 事件接收器，由 Flutter 侧的 onListen 回调提供
private var deviceOrientationEventSink: EventChannel.EventSink? = null

// 缓存上一次方向，用于去重
private var lastOrientation: PlatformChannel.DeviceOrientation? = null

// 是否正在监听系统广播
private var listening = false
```

#### 3.3.2 StreamHandler 回调（Flutter 侧订阅管理）

```kotlin
// Flutter 侧开始监听时调用
override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
    deviceOrientationEventSink = eventSink
}

// Flutter 侧取消监听时调用
override fun onCancel(event: Any?) {
    deviceOrientationEventSink = null
}
```

**注意**：这两个回调**只管理 sink 引用**，不控制 BroadcastReceiver 的注册。BroadcastReceiver 的生命周期由 `MobileScanner` 控制。

#### 3.3.3 BroadcastReceiver 回调（系统方向变化处理）

```kotlin
override fun onReceive(context: Context?, intent: Intent?) {
    // 1. 获取当前 UI 方向
    val orientation: PlatformChannel.DeviceOrientation = getUIOrientation()

    // 2. 与上次方向比较，仅在变化时推送（去重）
    if (orientation != lastOrientation) {
        // 3. 在主线程推送事件给 Flutter
        Handler(Looper.getMainLooper()).post {
            deviceOrientationEventSink?.success(orientation.serialize())
        }
    }

    // 4. 更新缓存
    lastOrientation = orientation
}
```

**去重机制**：`lastOrientation` 确保同一方向不会重复发送事件，避免 Flutter 侧不必要的重建。

**线程安全**：`EventSink.success()` 必须在主线程调用，因此通过 `Handler(Looper.getMainLooper())` 切换到主线程。

#### 3.3.4 方向判定逻辑（`getUIOrientation()`）

```kotlin
fun getUIOrientation(): PlatformChannel.DeviceOrientation {
    val rotation: Int = getDisplay().rotation          // 屏幕物理旋转角度
    val orientation: Int = activity.resources.configuration.orientation  // 竖屏/横屏

    return when(orientation) {
        Configuration.ORIENTATION_PORTRAIT -> {
            if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                PlatformChannel.DeviceOrientation.PORTRAIT_UP
            } else {
                PlatformChannel.DeviceOrientation.PORTRAIT_DOWN
            }
        }
        Configuration.ORIENTATION_LANDSCAPE -> {
            if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                PlatformChannel.DeviceOrientation.LANDSCAPE_LEFT
            } else {
                PlatformChannel.DeviceOrientation.LANDSCAPE_RIGHT
            }
        }
        // 未定义或其他情况，默认竖屏向上
        else -> PlatformChannel.DeviceOrientation.PORTRAIT_UP
    }
}
```

**判定逻辑说明：**

| Configuration 方向 | Display Rotation | 结果 |
|--------------------|-----------------|------|
| `ORIENTATION_PORTRAIT` | `ROTATION_0` 或 `ROTATION_90` | `PORTRAIT_UP` |
| `ORIENTATION_PORTRAIT` | `ROTATION_180` 或 `ROTATION_270` | `PORTRAIT_DOWN` |
| `ORIENTATION_LANDSCAPE` | `ROTATION_0` 或 `ROTATION_90` | `LANDSCAPE_LEFT` |
| `ORIENTATION_LANDSCAPE` | `ROTATION_180` 或 `ROTATION_270` | `LANDSCAPE_RIGHT` |
| 其他 | - | `PORTRAIT_UP`（默认） |

`getDisplay()` 兼容处理：

```kotlin
private fun getDisplay(): Display {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        activity.display!!                          // API 30+
    } else {
        (activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
    }
}
```

#### 3.3.5 监听的启停

```kotlin
// 开始监听
fun start() {
    if (listening) return            // 防止重复注册
    listening = true
    activity.registerReceiver(this, orientationIntentFilter)
    onReceive(activity, null)        // 立即触发一次，推送当前方向
}

// 停止监听
fun stop() {
    if (!listening) return           // 防止重复注销
    activity.unregisterReceiver(this)
    listening = false
}
```

**`orientationIntentFilter`** 定义在伴生对象中：

```kotlin
companion object {
    private val orientationIntentFilter = IntentFilter(Intent.ACTION_CONFIGURATION_CHANGED)
}
```

`Intent.ACTION_CONFIGURATION_CHANGED` 的常量值为 `"android.intent.action.CONFIGURATION_CHANGED"`，当设备旋转、语言切换等配置变化时都会触发。

### 3.4 序列化工具（`DeviceOrientationExtension.kt`）

```kotlin
fun PlatformChannel.DeviceOrientation.serialize(): String {
    return when(this) {
        PlatformChannel.DeviceOrientation.PORTRAIT_UP    -> "PORTRAIT_UP"
        PlatformChannel.DeviceOrientation.PORTRAIT_DOWN  -> "PORTRAIT_DOWN"
        PlatformChannel.DeviceOrientation.LANDSCAPE_LEFT -> "LANDSCAPE_LEFT"
        PlatformChannel.DeviceOrientation.LANDSCAPE_RIGHT -> "LANDSCAPE_RIGHT"
    }
}
```

枚举值 → 字符串的映射，通过 EventChannel 传给 Flutter 层。

### 3.5 MobileScanner 中的调用时机

```kotlin
// MobileScanner.kt:494 — 扫描启动时
deviceOrientationListener.start()

// 启动成功回调中，将当前方向作为启动参数传给 Flutter（MobileScanner.kt:500）
MobileScannerStartParameters(
    ...
    deviceOrientationListener.getUIOrientation().serialize(),  // naturalDeviceOrientation
    ...
)

// MobileScanner.kt:525 — 暂停扫描时
deviceOrientationListener.stop()

// MobileScanner.kt:539 — 停止扫描时
deviceOrientationListener.stop()
```

### 3.6 销毁（`MobileScannerHandler.dispose`）

```kotlin
fun dispose(activityPluginBinding: ActivityPluginBinding) {
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    deviceOrientationChannel?.setStreamHandler(null)   // 清除 StreamHandler
    deviceOrientationChannel = null                     // 释放 EventChannel 引用
    barcodeHandler.dispose()
    mobileScanner?.dispose()                            // 内部会调用 deviceOrientationListener.stop()
    mobileScanner = null
    ...
}
```

### 3.7 启动返回参数中的方向信息

`MobileScannerStartParameters` 数据类：

```kotlin
class MobileScannerStartParameters(
    val width: Double = 0.0,
    val height: Double,
    val naturalDeviceOrientation: String,   // ← 设备自然方向，如 "PORTRAIT_UP"
    val sensorOrientation: Int,             // ← 传感器方向角度（如 90）
    val handlesCropAndRotation: Boolean,    // ← 是否自动处理裁剪旋转
    val currentTorchState: Int,
    val id: Long,
    val numberOfCameras: Int,
    val cameraDirection: Int?,
)
```

`MobileScannerHandler.start()` 将其转为 Map 返回给 Flutter：

```kotlin
result.success(mapOf(
    "textureId" to it.id,
    "size" to mapOf("width" to it.width, "height" to it.height),
    "naturalDeviceOrientation" to it.naturalDeviceOrientation,
    "handlesCropAndRotation" to it.handlesCropAndRotation,
    "sensorOrientation" to it.sensorOrientation,
    "currentTorchState" to it.currentTorchState,
    "numberOfCameras" to it.numberOfCameras,
    "cameraDirection" to it.cameraDirection
))
```

---

## 4. Flutter/Dart 端实现细节

### 4.1 EventChannel 声明与事件流获取

```dart
// mobile_scanner_method_channel.dart:45-67

final deviceOrientationEventChannel = const EventChannel(
    'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
);

Stream<DeviceOrientation>? _deviceOrientationStream;

Stream<DeviceOrientation> get deviceOrientationChangedStream {
    _deviceOrientationStream ??= deviceOrientationEventChannel
        .receiveBroadcastStream()    // 触发 Native 端的 onListen
        .cast<String>()              // 原始事件为字符串
        .map((String orientation) =>
            orientation.parseDeviceOrientation());  // 字符串 → DeviceOrientation 枚举
    return _deviceOrientationStream!;
}
```

**懒加载**：`_deviceOrientationStream` 使用 `??=` 确保只创建一次。

### 4.2 反序列化（`parse_device_orientation_extension.dart`）

```dart
extension ParseDeviceOrientation on String {
    DeviceOrientation parseDeviceOrientation() {
        return switch (this) {
            'PORTRAIT_UP'    => DeviceOrientation.portraitUp,
            'PORTRAIT_DOWN'  => DeviceOrientation.portraitDown,
            'LANDSCAPE_LEFT' => DeviceOrientation.landscapeLeft,
            'LANDSCAPE_RIGHT' => DeviceOrientation.landscapeRight,
            _ => throw ArgumentError.value(
                this, 'deviceOrientation', 'Received an invalid device orientation'),
        };
    }
}
```

### 4.3 控制器中的监听（`mobile_scanner_controller.dart`）

```dart
// mobile_scanner_controller.dart:188-200

if (MobileScannerPlatform.instance
    case final MethodChannelMobileScanner implementation
    when defaultTargetPlatform != TargetPlatform.macOS) {
    _deviceOrientationSubscription = implementation
        .deviceOrientationChangedStream
        .listen((DeviceOrientation orientation) {
            if (_isDisposed) return;
            value = value.copyWith(deviceOrientation: orientation);
        });
}
```

**条件监听**：仅在非 macOS 平台（Android、iOS、ohos）时才订阅方向流。

### 4.4 状态存储（`MobileScannerState`）

```dart
class MobileScannerState {
    final DeviceOrientation deviceOrientation;  // 当前设备 UI 方向

    const MobileScannerState.uninitialized()
        : ...
          deviceOrientation: DeviceOrientation.portraitUp,  // 默认竖屏
          ...;

    MobileScannerState copyWith({
        ...
        DeviceOrientation? deviceOrientation,
        ...
    }) { ... }
}
```

### 4.5 相机预览旋转矫正（`RotatedPreview`）

这是方向流的**核心消费端**。当底层 `handlesCropAndRotation = false` 时启用：

```dart
// mobile_scanner_method_channel.dart:254-267

if (_surfaceProducerDelegate
    case final AndroidSurfaceProducerDelegate delegate
    when !delegate.handlesCropAndRotation) {
    return RotatedPreview.fromCameraDirection(
        delegate.cameraFacingDirection,
        deviceOrientationStream: deviceOrientationChangedStream,  // ← 方向事件流
        initialDeviceOrientation: delegate.initialDeviceOrientation,
        sensorOrientationDegrees: delegate.sensorOrientationDegrees,
        child: texture,
    );
}
```

**旋转计算逻辑**（`RotatedPreview._computeRotationDegrees`）：

```dart
double _computeRotationDegrees(
    DeviceOrientation orientation, {
    required double sensorOrientationDegrees,
    required int sign,          // front=1, back=-1
}) {
    final double deviceOrientationDegrees = switch (orientation) {
        DeviceOrientation.portraitUp    => 0,
        DeviceOrientation.landscapeRight => 90,
        DeviceOrientation.portraitDown  => 180,
        DeviceOrientation.landscapeLeft => 270,
    };

    // 参考: https://developer.android.com/media/camera/camera2/camera-preview#orientation_calculation
    double rotationDegrees =
        (sensorOrientationDegrees - deviceOrientationDegrees * sign + 360) % 360;

    // 减去系统已经应用的旋转
    return rotationDegrees -= deviceOrientationDegrees;
}
```

最终通过 `RotatedBox` 应用旋转：

```dart
Widget build(BuildContext context) {
    final double rotationDegrees = _computeRotationDegrees(...);
    return RotatedBox(quarterTurns: rotationDegrees ~/ 90, child: widget.child);
}
```

---

## 5. 完整数据流时序图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        初始化阶段                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  MobileScannerHandler.init()                                        │
│       │                                                             │
│       ├── new DeviceOrientationListener(activity)                   │
│       │        implements BroadcastReceiver                          │
│       │        implements EventChannel.StreamHandler                 │
│       │                                                             │
│       ├── new EventChannel("dev.steenbakker.mobile_scanner/         │
│       │                     scanner/deviceOrientation")              │
│       │        .setStreamHandler(deviceOrientationListener)          │
│       │                                                             │
│       └── new MobileScanner(..., deviceOrientationListener)         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       扫描启动阶段                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Flutter: methodChannel.invokeMethod('start', ...)                  │
│       │                                                             │
│       ▼                                                             │
│  Android: MobileScannerHandler.start()                              │
│       │                                                             │
│       └── MobileScanner.start()                                     │
│              │                                                      │
│              ├── deviceOrientationListener.start()                  │
│              │      ├── activity.registerReceiver(this, filter)     │
│              │      └── onReceive() → 推送初始方向                   │
│              │                                                      │
│              └── mobileScannerStartedCallback(params)               │
│                     └── result.success({                            │
│                           "naturalDeviceOrientation": "PORTRAIT_UP",│
│                           "sensorOrientation": 90,                  │
│                           "handlesCropAndRotation": false,          │
│                           ...                                       │
│                        })                                           │
│                                                                     │
│  Flutter: start() 返回后                                            │
│       ├── state.copyWith(deviceOrientation: initialDeviceOrientation)│
│       └── 开始订阅 deviceOrientationChangedStream                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     方向变化事件推送                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  系统配置变化 (旋转设备)                                              │
│       │                                                             │
│       ▼                                                             │
│  Android: BroadcastReceiver.onReceive()                             │
│       │                                                             │
│       ├── getUIOrientation()                                        │
│       │      ├── getDisplay().rotation → rotation (0/90/180/270)    │
│       │      ├── configuration.orientation → portrait/landscape     │
│       │      └── return DeviceOrientation.PORTRAIT_UP 等            │
│       │                                                             │
│       ├── 比较 lastOrientation (去重)                                │
│       │                                                             │
│       └── 不同时: Handler(主线程).post {                             │
│               eventSink.success("PORTRAIT_UP")                      │
│           }                                                         │
│               │                                                     │
│               ▼                                                     │
│  Flutter: EventChannel.receiveBroadcastStream                       │
│       │                                                             │
│       ├── .cast<String>()                                           │
│       ├── .map(parseDeviceOrientation)                              │
│       │                                                             │
│       ├──→ MobileScannerController:                                 │
│       │      value = value.copyWith(deviceOrientation: orientation) │
│       │                                                             │
│       └──→ RotatedPreview:                                          │
│              setState(() { deviceOrientation = event })             │
│              → _computeRotationDegrees() → RotatedBox               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     暂停 / 停止 / 销毁                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  MobileScanner.stop() / pause()                                     │
│       └── deviceOrientationListener.stop()                          │
│              └── activity.unregisterReceiver(this)                  │
│                                                                     │
│  MobileScannerHandler.dispose()                                     │
│       ├── deviceOrientationChannel.setStreamHandler(null)           │
│       ├── deviceOrientationChannel = null                           │
│       └── mobileScanner.dispose()                                   │
│              └── deviceOrientationListener.stop()                   │
│                                                                     │
│  Flutter: Controller._disposeListeners()                            │
│       └── _deviceOrientationSubscription?.cancel()                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. 鸿蒙（OHOS）平台实现要点

### 6.1 需要对标的接口契约

鸿蒙端需要提供以下三个能力，与 Android 端保持完全一致：

| # | 能力 | Android 实现方式 | 鸿蒙需对标的方式 |
|---|------|-----------------|----------------|
| 1 | **EventChannel 推送设备方向变化** | `BroadcastReceiver` + `EventChannel.StreamHandler` | 鸿蒙侧方向监听回调 + Flutter EventChannel |
| 2 | **启动时返回初始方向** | `MobileScannerStartParameters.naturalDeviceOrientation` | `start()` 返回值中包含 `"naturalDeviceOrientation"` 字段 |
| 3 | **启动时返回传感器方向** | `MobileScannerStartParameters.sensorOrientation` | `start()` 返回值中包含 `"sensorOrientation"` 字段 |
| 4 | **启动时返回是否自动处理旋转** | `MobileScannerStartParameters.handlesCropAndRotation` | `start()` 返回值中包含 `"handlesCropAndRotation"` 字段 |

### 6.2 EventChannel 协议

**通道名称**：
```
dev.steenbakker.mobile_scanner/scanner/deviceOrientation
```

**事件数据格式**：
```
字符串: "PORTRAIT_UP" | "PORTRAIT_DOWN" | "LANDSCAPE_LEFT" | "LANDSCAPE_RIGHT"
```

### 6.3 start() 返回值中的方向相关字段

```json
{
    "textureId": 1,
    "size": { "width": 1920.0, "height": 1080.0 },
    "naturalDeviceOrientation": "PORTRAIT_UP",
    "sensorOrientation": 90,
    "handlesCropAndRotation": false,
    "currentTorchState": 0,
    "numberOfCameras": 2,
    "cameraDirection": 1
}
```

### 6.4 鸿蒙方向监听建议方案

鸿蒙端需要解决以下核心问题：

1. **获取当前设备 UI 方向**：
   - 鸿蒙对应 API：`@ohos.display` 模块的 `display.getDefaultDisplaySync().rotation`
   - 或监听 `@ohos.emitter` / `@ohos.app.ability.ConfigurationConstant` 的方向变化回调

2. **获取传感器方向（sensorOrientation）**：
   - 鸿蒙对应 API：`@ohos.multimedia.camera` 的 `CameraInput` / `CameraManager` 获取传感器方向角度
   - 通常后置摄像头为 90°，前置摄像头为 270°

3. **方向变化监听**：
   - 方案 A：监听 `AbilityStage` / `UIAbility` 的 `onConfigurationUpdate` 回调
   - 方案 B：使用 `@ohos.display` 的 `display.on('change')` 事件
   - 方案 C：定时轮询 `display.getDefaultDisplaySync().rotation`

4. **去重**：与 Android 一致，缓存 `lastOrientation`，仅在变化时推送

5. **线程**：确保 EventSink 回调在主线程执行

### 6.5 鸿蒙端实现类参考结构

```
鸿蒙端建议的类结构（对标 Android）：

DeviceOrientationListener
├── 成员
│   ├── eventSink: EventChannel.EventSink?
│   ├── lastOrientation: String?
│   └── listening: boolean
├── 方法
│   ├── getUIOrientation(): String         // 返回 "PORTRAIT_UP" 等
│   ├── start(): void                      // 开始监听方向变化
│   ├── stop(): void                       // 停止监听
│   ├── onListen(eventSink): void          // Flutter 侧订阅
│   ├── onCancel(): void                   // Flutter 侧取消
│   └── onOrientationChanged(): void       // 方向变化回调（内部）
└── 实现接口
    ├── Flutter EventChannel.StreamHandler
    └── 鸿蒙方向变化监听器
```

### 6.6 Flutter 侧已有的适配点

Flutter 侧已经预留了 `TargetPlatform.ohos` 分支：

```dart
// mobile_scanner_method_channel.dart:100-101
if (defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.ohos) {  // ← 已包含
```

因此鸿蒙端只需正确实现 Native 侧的 EventChannel 推送即可，Flutter 侧的订阅逻辑无需修改。

### 6.7 方向值映射参考

| 鸿蒙 display.rotation | 鸿蒙 Configuration 方向 | 对标 Android 方向 | 推送字符串 |
|----------------------|------------------------|-----------------|-----------|
| 0 | PORTRAIT | PORTRAIT_UP | `"PORTRAIT_UP"` |
| 1 (顺时针 90°) | LANDSCAPE | LANDSCAPE_LEFT | `"LANDSCAPE_LEFT"` |
| 2 (顺时针 180°) | PORTRAIT (反向) | PORTRAIT_DOWN | `"PORTRAIT_DOWN"` |
| 3 (顺时针 270°) | LANDSCAPE (反向) | LANDSCAPE_RIGHT | `"LANDSCAPE_RIGHT"` |

> **注意**：鸿蒙 `display.rotation` 的值定义需要以实际 API 文档为准（0/1/2/3 分别对应 ROTATION_0/ROTATION_90/ROTATION_180/ROTATION_270）。

---

## 7. 关键实现注意事项

1. **EventSink 空安全**：推送前必须检查 `eventSink != null`，因为 Flutter 侧可能尚未订阅或已取消
2. **去重必须保留**：避免每次配置变化（不一定是旋转）都推送相同方向
3. **主线程回调**：Flutter EventChannel 的 `success()` 需要在平台主线程调用
4. **生命周期绑定**：方向监听应跟随扫描的 start/stop/pause 而非 Activity 生命周期
5. **初始方向**：`start()` 时必须立即获取并推送一次当前方向（Android 的做法是 `start()` 末尾调用 `onReceive(activity, null)`）
6. **sensorOrientation 与 naturalDeviceOrientation**：这两个值在启动时一次性返回，用于 Flutter 端计算预览旋转角度，不需要持续推送
