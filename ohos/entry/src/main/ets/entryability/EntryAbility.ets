
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { WechatPlugin } from '../wechat/WechatPlugin';
import { NetworkInfoPlugin } from '../network/NetworkInfoPlugin';
import Want from '@ohos.app.ability.Want';
import { AbilityConstant } from '@kit.AbilityKit';

export default class EntryAbility extends FlutterAbility {
  private wechatPlugin: WechatPlugin | null = null;
  private networkInfoPlugin: NetworkInfoPlugin | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 微信登录：注册 fluwx 同名单通道（com.jarvanmo/fluwx）
    this.wechatPlugin = new WechatPlugin(flutterEngine, this.context)
    // 网络信息：注册 fmlink/network_info 通道（缓存功能网络判断用）
    this.networkInfoPlugin = new NetworkInfoPlugin(flutterEngine)
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
