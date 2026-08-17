

<p align="center">
  <h1 align="center"> <code>image_cropper</code> </h1>
</p>



本项目基于 [image_cropper@2.0.0](https://pub.dev/packages/image_cropper/versions/2.0.0) 开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
...

dependencies:
  image_cropper:
    git: 
      url: https://gitcode.com/CPF-Flutter/fluttertpc_image_cropper.git
      path: ./image_cropper
      ref: master

dev_dependencies:
  imagecropper_ohos:
    git: 
      url: https://gitcode.com/CPF-Flutter/fluttertpc_image_cropper.git
      path: ./image_cropper/ohos
      ref: master

...
```

执行命令

```bash
flutter pub get
```

| Flutter 框架版本  | TAG 名称                | 分支名 |
| ---------------- | ----------------------- | ---- |
| 3.7              | 6.0.0-ohos-1.0.0-beta.1 | master |
| 3.22             | 8.0.2-ohos-1.0.0-beta.1 |br_v8.0.2_ohos |
| 3.27             | 9.1.0-ohos-1.0.0-beta.1 |br_v9.1.0_ohos |
| 3.35             | 11.0.0-ohos-1.0.0-beta.1 | br_v11.0.0_ohos |

<!-- tabs:end -->

### 1.2 使用案例

使用案例详见 [ohos/example](./image_cropper/ohos/example)

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 权限要求

以下权限中有`system_basic` 权限，而默认的应用权限是 `normal` ，只能使用 `normal` 等级的权限，所以可能会在安装hap包时报错**9568289**，请参考 [文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/bm-tool-V5#ZH-CN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) 修改应用等级为 `system_basic`

####  2.2.1在 entry 目录下的module.json5中添加权限

打开 `entry/src/main/module.json5`，添加：

```yaml
"requestPermissions": [
  {
   "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

####  2.2.2在 entry 目录下添加申请以上权限的原因

打开 `entry/src/main/resources/base/element/string.json`，添加：

```yaml
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name                | return value                        |  Description               | Type       | ohos Support |
|---------------------|-------------------------------------------------------------------------------------------------------|------|-------|-------------------|
| Future<CroppedFile?> cropImage(required String sourcePath, int? maxWidth, int? maxHeight, [CropAspectRatio](#CropAspectRatio)? aspectRatio, List<[CropAspectRatioPreset](#CropAspectRatioPreset)> aspectRatioPresets, [CropStyle](#CropStyle) cropStyle = CropStyle.rectangle, [ImageCompressFormat](#ImageCompressFormat) compressFormat = ImageCompressFormat.jpg, int compressQuality = 90, List<[PlatformUiSettings](#PlatformUiSettings)>? uiSettings)  |  Future<[CroppedFile](#CroppedFile)?>             |         裁剪图像并获取结果文件     | function | yes               |

## 4. 属性

### Parameters

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  sourcePath  | 镜像文件的绝对路径 |  String | yes   |
|  maxWidth  | 最大裁剪图像宽度 |  int | yes   |
|  maxHeight  | 最大裁剪图像高度 |  int | yes   |
|  compressQuality  | 值[0 - 100]用于控制图像压缩的质量 |  int | yes   |

### CropAspectRatio

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropAspectRatio.ratioX  | 水平方向的比例 |  double | yes   |
|  CropAspectRatio.ratioY  | 竖直方向的比例 |  double | yes   |

### CropAspectRatioPreset

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropAspectRatioPreset.original  | 原始比例 |  enum | yes   |
|  CropAspectRatioPreset.square  | 正方形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio3x2  | 3*2矩形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio5x3  | 5*3矩形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio4x3  | 4*3矩形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio5x4  | 5*4矩形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio7x5  | 7*5矩形比例 |  enum | yes   |
|  CropAspectRatioPreset.ratio16x9  | 16*9矩形比例 |  enum | yes   |

### CropStyle

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropStyle.rectangle  | 矩形 |  enum | yes   |
|  CropStyle.circle  | 圆形 |  enum | yes   |

### ImageCompressFormat

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  ImageCompressFormat.jpg  | JPG类型有损压缩 |  enum | yes   |
|  ImageCompressFormat.png  | PNG类型无损压缩 |  enum | yes   |

### CroppedFile

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CroppedFile.path  | 裁剪后文件的完整路径 |  string | yes   |
|  CroppedFile._initBytes  | 裁剪操作前的原始图像字节数据 |  Unit8List | yes   |

### PlatformUiSettings


## 5. 遗留问题

## 6. 其他

## 7. 开源协议

本项目基于 [BSD-3-Clause](https://gitcode.com/CPF-Flutter/fluttertpc_image_cropper/blob/master/LICENSE) ，请自由地享受和参与开源。

