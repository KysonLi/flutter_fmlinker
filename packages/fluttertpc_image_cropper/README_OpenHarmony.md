

<p align="center">
  <h1 align="center"> <code>image_cropper</code> </h1>
</p>



This project is based on [image_cropper@2.0.0](https://pub.dev/packages/image_cropper/versions/2.0.0).

## 1. Installation and Usage

### 1.1 Installation

Go to the project directory and add the following dependencies in pubspec.yaml

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

Execute Command

```bash
flutter pub get
```

| Flutter Framework Version | TAG Name  | Branch Name |
| ---------------- | ----------------------- | ---- |
| 3.7              | 6.0.0-ohos-1.0.0-beta.1 | master |
| 3.22             | 8.0.2-ohos-1.0.0-beta.1 |br_v8.0.2_ohos |
| 3.27             | 9.1.0-ohos-1.0.0-beta.1 |br_v9.1.0_ohos |
| 3.35             | 11.0.0-ohos-1.0.0-beta.1 | br_v11.0.0_ohos |
<!-- tabs:end -->

### 1.2 Usage

For use cases [ohos/example](./image_cropper/ohos/example)

## 2. Constraints

### 2.1 Compatibility

This document is verified based on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 **Permission Requirements**

The following permissions include the `system_basic` permission, but the default application permission is `normal`. Only the `normal` permission can be used. Therefore, the error **9568289** may be reported during the installation of the HAP package. For details, see [Document](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/bm-tool-V5#EN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) Change the application level to `system_basic`.

####  2.2.1 **Add permissions to the module.json5 file in the entry directory**

Open  `entry/src/main/module.json5` and add the following information:

```yaml
"requestPermissions": [
      {
        "name": "ohos.permission.INTERNET",
        "reason": "$string:network_reason",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      },
    ]
```

#### 2.2.2 **Add the reason for applying for the preceding permission to the entry directory**

Open  `entry/src/main/resources/base/element/string.json` and add the following information:

```yaml
{
  "string": [
    {
      "name": "network_reason",
      "value": "use network"
    }
  ]
}
```


## 3. API

> [!TIP] If the value of **ohos Support** is **yes**, it means that the ohos platform supports this property; **no** means the opposite; **partially** means some capabilities of this property are supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name                | return value                        |  Description               | Type       | ohos Support |
|---------------------|-------------------------------------------------------------------------------------------------------|------|-------|-------------------|
| Future<CroppedFile?> cropImage(required String sourcePath, int? maxWidth, int? maxHeight, [CropAspectRatio](#CropAspectRatio)? aspectRatio, List<[CropAspectRatioPreset](#CropAspectRatioPreset)> aspectRatioPresets, [CropStyle](#CropStyle) cropStyle = CropStyle.rectangle, [ImageCompressFormat](#ImageCompressFormat) compressFormat = ImageCompressFormat.jpg, int compressQuality = 90, List<[PlatformUiSettings](#PlatformUiSettings)>? uiSettings)  |  Future<[CroppedFile](#CroppedFile)?>             |         Crop the image and obtain the result file     | function | yes               |

## 4. Properties

### Parameters

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  sourcePath  | the absolute path of an image file |  String | yes   |
|  maxWidth  | maximum cropped image width |  int | yes   |
|  maxHeight  | maximum cropped image height |  int | yes   |
|  compressQuality  | the value [0 - 100] to control the quality of image compression |  int | yes   |

### CropAspectRatio

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropAspectRatio.ratioX  | Proportion in the horizontal direction |  double | yes   |
|  CropAspectRatio.ratioY  | Proportion in the vertical direction |  double | yes   |

### CropAspectRatioPreset

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropAspectRatioPreset.original  | Original proportion |  enum | yes   |
|  CropAspectRatioPreset.square  | Square proportion |  enum | yes   |
|  CropAspectRatioPreset.ratio3x2  | 3*2rectangular ratio |  enum | yes   |
|  CropAspectRatioPreset.ratio5x3  | 5*3rectangular ratio |  enum | yes   |
|  CropAspectRatioPreset.ratio4x3  | 4*3rectangular ratio |  enum | yes   |
|  CropAspectRatioPreset.ratio5x4  | 5*4rectangular ratio |  enum | yes   |
|  CropAspectRatioPreset.ratio7x5  | 7*5rectangular ratio |  enum | yes   |
|  CropAspectRatioPreset.ratio16x9  | 16*9rectangular ratio |  enum | yes   |

### CropStyle

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CropStyle.rectangle  | rectangle |  enum | yes   |
|  CropStyle.circle  | circle |  enum | yes   |

### ImageCompressFormat

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  ImageCompressFormat.jpg  | Lossy compression of JPG type |  enum | yes   |
|  ImageCompressFormat.png  | Lossless compression of PNG type |  enum | yes   |

### CroppedFile

| Name              | Description                                                | Type                                        | ohos Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  CroppedFile.path  | The complete path of the cropped file |  string | yes   |
|  CroppedFile._initBytes  | The byte data of the original image before the cropping operation |  Unit8List | yes   |

### PlatformUiSettings

## 5. Known Issues

## 6. Others

## 7. License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/fluttertpc_image_cropper/blob/master/LICENSE)

