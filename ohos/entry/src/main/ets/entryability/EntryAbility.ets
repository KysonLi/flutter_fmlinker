
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { WechatPlugin } from '../wechat/WechatPlugin';
import { NetworkInfoPlugin } from '../network/NetworkInfoPlugin';
import { HuaweiAccountPlugin } from '../huawei/HuaweiAccountPlugin';
import { IapPlugin } from '../iap/IapPlugin';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { AbilityConstant, bundleManager } from '@kit.AbilityKit';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends FlutterAbility {
  private wechatPlugin: WechatPlugin | null = null;
  private networkInfoPlugin: NetworkInfoPlugin | null = null;
  private huaweiAccountPlugin: HuaweiAccountPlugin | null = null;
  private iapPlugin: IapPlugin | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 微信登录：注册 fluwx 同名单通道（com.jarvanmo/fluwx）
    this.wechatPlugin = new WechatPlugin(flutterEngine, this.context)
    // 网络信息：注册 fmlink/network_info 通道（缓存功能网络判断用）
    this.networkInfoPlugin = new NetworkInfoPlugin(flutterEngine)
    // 华为账号一键登录：注册 fmlink/huawei_account 通道（@kit.AccountKit）
    this.huaweiAccountPlugin = new HuaweiAccountPlugin(flutterEngine, this.context)
    // 泛票内购商品查询：注册 fmlink/iap 通道（@kit.IAPKit）
    this.iapPlugin = new IapPlugin(flutterEngine, this.context)
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    // 华为账号 Kit / IAP Kit 都需运行在 ArkUI 页面上下文中，此处把窗口交给插件
    this.huaweiAccountPlugin?.setWindowStage(windowStage)
    this.iapPlugin?.setWindowStage(windowStage)
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    await super.onCreate(want, launchParam)
    // 冷启动被微信拉起时，处理授权回调
    this.wechatPlugin?.handleWant(want)
    this.logSignInfo()
  }

  /**
   * 打印应用的签名信息——QQ 互联 / App Linking 联调排查用
   *
   * QQ 互联「鸿蒙平台」登记的 BundleName / 签名 必须与这里打印的值**逐字一致**：
   * - bundleName：com.mpr.chaincode
   * - appIdentifier：AGC 的 app-identifier（App Linking 的 applinking.json 用它匹配）
   * - fingerprint：签名证书 SHA256（带冒号大写），App Linking 校验按此精确比较
   */
  private logSignInfo() {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO
      )
      console.info(`${TAG} bundleName=${info.name}`)
      console.info(`${TAG} appIdentifier=${info.signatureInfo.appIdentifier}`)
      console.info(`${TAG} fingerprint=${info.signatureInfo.fingerprint}`)
    } catch (e) {
      console.error(`${TAG} 读取签名信息失败: ${e}`)
    }
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam) {
    super.onNewWant(want, launchParams)
    // 微信授权后跳回本应用，处理登录结果
    this.wechatPlugin?.handleWant(want)
  }
}
