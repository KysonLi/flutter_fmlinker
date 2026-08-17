/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos';
import image from '@ohos.multimedia.image';
import { BusinessError } from '@ohos.base';
import fs from '@ohos.file.fs';
import { HashMap } from '@kit.ArkTS';

import { photoAccessHelper } from '@kit.MediaLibraryKit';

class ImageOptions {
  private width: number = 0;
  private height: number = 0;
  private degrees: number = 0;

  constructor(width: number, height: number, degrees: number) {
    this.width = width;
    this.height = height;
    this.degrees = degrees;
  }

  getHeight(): number {
    return (this.isFlippedDimensions() && this.degrees != 180) ? this.width : this.height;
  }

  getWidth(): number {
    return (this.isFlippedDimensions() && this.degrees != 180) ? this.height : this.width;
  }

  getDegrees(): number {
    return this.degrees;
  }

  isFlippedDimensions(): boolean {
    return this.degrees == 90 || this.degrees == 270 || this.degrees == 180;
  }

  isRotated(): boolean {
    return this.degrees != 0;
  }
}

export default class ImagecropPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel = undefined;
  private abilityBinding?: AbilityPluginBinding = undefined;

  constructor() {
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
  }

  onDetachedFromAbility(): void {

  }

  getUniqueClassName(): string {
    return "ImagecropPlugin1"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "imagecropper");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if ("cropImage" == call.method) {
      let path: string = call.argument("path");
      let scale: number = call.argument("scale");
      let left: number = call.argument("left");
      let top: number = call.argument("top");
      let right: number = call.argument("right");
      let bottom: number = call.argument("bottom");
      let angle: number = call.argument("angle");
      let cx: number = call.argument("cx");
      let cy: number = call.argument("cy");
      try {
        this.cropImage(result, path, scale, left, top, right, bottom,angle,cx,cy);
      } catch (e) {
        result.error("INVALID", "Image source cannot be opened", null);
      }
    } else if ("sampleImage" == call.method) {
      let path: string = call.argument("path");
      let maximumWidth: number = call.argument("maximumWidth");
      let maximumHeight: number = call.argument("maximumHeight");
      try {
        this.sampleImage(result, path, maximumWidth, maximumHeight);
      } catch (e) {
        result.error("INVALID", "SampleImage error", null);
      }
    } else if ("getImageOptions" == call.method) {
      let path: string = call.argument("path");
      this.getImageOptions(path, result);
    } else if ("requestPermissions" == call.method) {
      this.requestPermissions(result);
    } else {
      result.notImplemented();
    }
  }

  private async cropImage(result: MethodResult, path: string, scale: number, left: number, top: number, right: number, bottom: number,angle: number,cx: number,cy:number) {
    try {
      let imageSource = image.createImageSource(path);
      let pixelMapData = await imageSource.createPixelMap();
      let options = await this.decodeImageOptions(imageSource);
      await pixelMapData.rotate(angle);

      let width = options.getWidth() * (right - left) * scale;
      let height = options.getHeight() * (bottom - top) * scale;
      let rAngle = 2 * Math.PI - angle/180*Math.PI;
      let originX = options.getWidth() * left;
      let originY = -options.getHeight() * top;

      //第三象限旋转中心坐标
      let x0 = (options.getWidth() * left + width/2);
      let y0 = - (options.getHeight() * top + height/2);

      //获取图片4个角旋转后的坐标
      let leftTopX = 0;
      let leftTopY = 0;
      let leftTopX2 = (leftTopX - x0) * Math.cos(rAngle) - (leftTopY - y0) * Math.sin(rAngle) + x0;
      let leftTopY2 = (leftTopX - x0) * Math.sin(rAngle) + (leftTopY - y0) * Math.cos(rAngle) + y0;

      let leftBottomX = 0;
      let leftBottomY = -options.getHeight();
      let leftBottomX2 = (leftBottomX - x0) * Math.cos(rAngle) - (leftBottomY - y0) * Math.sin(rAngle) + x0;
      let leftBottomY2 = (leftBottomX - x0) * Math.sin(rAngle) + (leftBottomY - y0) * Math.cos(rAngle) + y0;

      let rightTopX = options.getWidth();
      let rightTopY = 0;
      let rightTopX2 = (rightTopX - x0) * Math.cos(rAngle) - (rightTopY - y0) * Math.sin(rAngle) + x0;
      let rightTopY2 = (rightTopX - x0) * Math.sin(rAngle) + (rightTopY - y0) * Math.cos(rAngle) + y0;

      let rightBottomX = options.getWidth();
      let rightBottomY = -options.getHeight();
      let rightBottomX2 = (rightBottomX - x0) * Math.cos(rAngle) - (rightBottomY - y0) * Math.sin(rAngle) + x0;
      let rightBottomY2 = (rightBottomX - x0) * Math.sin(rAngle) + (rightBottomY - y0) * Math.cos(rAngle) + y0;

      //比较旋转后的4个角的坐标，取出x轴上的最小值和y轴上的最大值，用来做初始点的偏移量
      let verifyX = Math.min(leftTopX2,leftBottomX2,rightTopX2,rightBottomX2);
      let verifyY = Math.max(leftTopY2,leftBottomY2,rightTopY2,rightBottomY2);

      let region: image.Region = {
        x: originX - verifyX, y:  Math.abs(originY - verifyY), size: {
          height: height, width: width
        }
      };

      await pixelMapData.crop(region)
      let dstFile = this.createTemporaryImageFilePath();
      await this.savaPixelMap(pixelMapData, dstFile);
      result.success(dstFile);
    } catch (e) {
    }
  }

  private async sampleImage(result: MethodResult, path: string, maximumWidth: number, maximumHeight: number) {
    let imageSource = image.createImageSource(path);
    let options = await this.decodeImageOptions(imageSource);
    // 缩略图采样大小，当前只能取1。
    let inSampleSize = 1;//this.calculateInSampleSize(options.getWidth(), options.getHeight(), maximumWidth, maximumHeight);
    let pixelMapData = await imageSource.createPixelMap({sampleSize: inSampleSize});
    if (options.getWidth() > maximumWidth && options.getHeight() > maximumHeight) {
      let ratio = Math.max(maximumWidth / options.getWidth(), maximumHeight / options.getHeight());
      await pixelMapData.scale(ratio, ratio);
    }
    let dstFile = this.createTemporaryImageFilePath();
    await this.savaPixelMap(pixelMapData, dstFile);
    await this.copyExif(path, dstFile);
    result.success(dstFile);
  }

  private async getImageOptions(path: string, result: MethodResult) {
    let options = await this.decodeImageOptions(image.createImageSource(path));
    let properties = new HashMap<string, number>();
    properties.set("width", options.getWidth());
    properties.set("height", options.getHeight());
    result.success(properties);
  }

  private requestPermissions(result: MethodResult) {
    result.success(true);
  }

  private decodeImageOptions(imageSource: image.ImageSource): Promise<ImageOptions> {
    return new Promise<ImageOptions>((resolve, reject) => {
      let imageInfo: image.ImageInfo;
      imageSource.getImageInfo().then((info: image.ImageInfo) => {
        imageInfo = info
        return imageSource.getImageProperty(image.PropertyKey.ORIENTATION)
      }).then((result: string) => {
        let value = Number.parseInt(result)
        resolve(new ImageOptions(imageInfo.size.width, imageInfo.size.height, value ? value : 0));
      }).catch((err: BusinessError) => {
        resolve(new ImageOptions(imageInfo.size.width, imageInfo.size.height, 0));
      })
    })
  }

  private createTemporaryImageFilePath(): string {
    let directory = this.abilityBinding?.getAbility().context.cacheDir
    let name = "/image_crop_" + new Date().getTime().toString() + ".jpg";
    return directory + name
  }

  private async savaPixelMap(pixelMap: image.PixelMap, path: string) {
    let options: image.PackingOption = {
      format: 'image/jpeg',
      quality: 100
    };
    let packer = image.createImagePacker();
    let imageBuffer = await packer.packing(pixelMap, options);
    let stream = fs.createStreamSync(path, "a+");
    stream.writeSync(imageBuffer);
    stream.closeSync();
    await pixelMap.release()
    await packer.release()
  }

  private async copyExif(source: string, destination: string) {
    let tags = Array<image.PropertyKey>();
    tags.push(image.PropertyKey.F_NUMBER);
    tags.push(image.PropertyKey.EXPOSURE_TIME);
    tags.push(image.PropertyKey.FOCAL_LENGTH);
    tags.push(image.PropertyKey.GPS_DATE_STAMP);
    tags.push(image.PropertyKey.WHITE_BALANCE);
    tags.push(image.PropertyKey.GPS_TIME_STAMP);
    tags.push(image.PropertyKey.DATE_TIME);
    tags.push(image.PropertyKey.FLASH);
    tags.push(image.PropertyKey.GPS_LATITUDE);
    tags.push(image.PropertyKey.GPS_LATITUDE_REF);
    tags.push(image.PropertyKey.GPS_LONGITUDE);
    tags.push(image.PropertyKey.GPS_LONGITUDE_REF);
    tags.push(image.PropertyKey.MAKE);
    tags.push(image.PropertyKey.MODEL);
    tags.push(image.PropertyKey.ORIENTATION);

    let sourceExif = image.createImageSource(source);
    let destinationExif = image.createImageSource(destination);

    sourceExif.getImageProperty(tags[0]).then(async (data:string)=>{
      if (data != null) {
        await destinationExif.modifyImageProperty(tags[0], data);
      }
    }).catch((error: BusinessError)=>{
      console.info(`error: ${error}`);
    })
  }

  private calculateInSampleSize(width: number, height: number, maximumWidth: number, maximumHeight: number): number {
    let inSampleSize = 1;
    if (height > maximumHeight || width > maximumWidth) {
      let halfHeight = height / 2;
      let halfWidth = width / 2;
      while ((halfHeight / inSampleSize) >= maximumHeight && (halfWidth / inSampleSize) >= maximumWidth) {
        inSampleSize *= 2;
      }
    }
    return inSampleSize;
  }
}
