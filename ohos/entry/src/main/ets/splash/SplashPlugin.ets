import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { common } from '@kit.AbilityKit';

const TAG: string = 'SplashPlugin';
const CHANNEL_NAME: string = 'fmlink/splash';
/** Flutter 首帧渲染完成后通知原生隐藏启动页 */
export const SPLASH_HIDE_EVENT: string = 'fmlink/splash/hide';

/**
 * 启动页控制 MethodChannel（fmlink/splash）
 *
 * 鸿蒙的系统启动窗口（startWindowIcon + startWindowBackground）无法展示文字，
 * 因此 Index 页用原生叠层展示「图标 + 应用名称」，Flutter 首帧后调用 hide 通知其淡出。
 */
export class SplashPlugin implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;

  constructor(flutterEngine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'hide') {
      try {
        this.context.eventHub.emit(SPLASH_HIDE_EVENT);
        result.success(true);
      } catch (e) {
        console.error(`${TAG} emit ${SPLASH_HIDE_EVENT} failed: ${e}`);
        result.success(false);
      }
    } else {
      result.notImplemented();
    }
  }
}
