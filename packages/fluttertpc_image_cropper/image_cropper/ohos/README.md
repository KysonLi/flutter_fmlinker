# Image Cropper

[![pub package](https://img.shields.io/pub/v/image_cropper.svg)](https://pub.dartlang.org/packages/image_cropper)


A Flutter plugin for ohos supports cropping images. This plugin is based on three different native libraries so it comes with different UI between these platforms.

### Required parameters

* **sourcePath**: the absolute path of an image file.

## Usage

```
  yaml
    dependencies:
      image_cropper: 2.0.0
      imagecropper_ohos: 1.0.0
 ```

## Example

````dart

import 'package:image_cropper/image_cropper.dart';


    
````

## Options

| Name                 | Android | iOS  | OpenHarmony |   Default   |
|:---------------------|:-------:|:----:|:-----------:|:-----------:|
| cropImage            |    ✅    |  ✅   |      ✅      |   `File`    |

