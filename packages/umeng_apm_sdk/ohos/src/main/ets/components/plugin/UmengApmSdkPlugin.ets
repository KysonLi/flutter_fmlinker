import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { HarmonyNative } from '@umeng/apm';

/** UmengApmSdkPlugin **/
export default class UmengApmSdkPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  FlutterNative: HarmonyNative = HarmonyNative.getInstance()

  constructor() {
  }

  getUniqueClassName(): string {
    return "UmengApmSdkPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "umeng_apm_sdk");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

   onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "getNativeParams": {
        let NativeMap = this.FlutterNative.getNativeEquipmentInfo();
        result.success(NativeMap);
        break
      }
      case "getCloudConfig": {
        let cloudConfig = this.FlutterNative.getCloudConfig()
        result.success(cloudConfig);
        break
      }
      case "putIntValue": {
        let key: string = call.argument("key") as string;
        let value: number = Number(call.argument("value"));
        let success =  this.FlutterNative.putIntValue(key, value);
        result.success(success);
        break
      }
      case "getIntValue": {
        let key: string = call.args as string;
        let value = this.FlutterNative.getIntValue(key);
        result.success(value);
          break
      }
      case "getSdkVersion": {
        let sdkVersion = this.FlutterNative.getSdkVersion()
        result.success(sdkVersion);
        break
      }
      case "getNativeFPS": {
        let fps = this.FlutterNative.getNativeFPS()
        result.success(fps);
        break
      }
      default: {
        result.notImplemented()
        break
      }
    }
  }
}