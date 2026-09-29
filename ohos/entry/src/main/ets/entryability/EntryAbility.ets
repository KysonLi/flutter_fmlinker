
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { WechatPlugin } from '../wechat/WechatPlugin';
import { NetworkInfoPlugin } from '../network/NetworkInfoPlugin';
import { HuaweiAccountPlugin } from '../huawei/HuaweiAccountPlugin';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { AbilityConstant } from '@kit.AbilityKit';

export default class EntryAbility extends FlutterAbility {
  private wechatPlugin: WechatPlugin | null = null;
  private networkInfoPlugin: NetworkInfoPlugin | null = null;
  private huaweiAccountPlugin: HuaweiAccountPlugin | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 微信登录：注册 fluwx 同名单通道（com.jarvanmo/fluwx）
    this.wechatPlugin = new WechatPlugin(flutterEngine, this.context)
    // 网络信息：注册 fmlink/network_info 通道（缓存功能网络判断用）
    this.networkInfoPlugin = new NetworkInfoPlugin(flutterEngine)
    // 华为账号一键登录：注册 fmlink/huawei_account 通道（@kit.AccountKit）
    this.huaweiAccountPlugin = new HuaweiAccountPlugin(flutterEngine, this.context)
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    // 华为账号 Kit 的登录请求需运行在 ArkUI 页面上下文中，此处把窗口交给插件
    this.huaweiAccountPlugin?.setWindowStage(windowStage)
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    await super.onCreate(want, launchParam)
    // 冷启动被微信拉起时，处理授权回调
    this.wechatPlugin?.handleWant(want)
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam) {
    super.onNewWant(want, launchParams)
    // 微信授权后跳回本应用，处理登录结果
    this.wechatPlugin?.handleWant(want)
  }
}
