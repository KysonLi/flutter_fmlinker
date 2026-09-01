import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import { WXAPIFactory, WXApi, WXApiEventHandler, SendAuthReq, SendAuthResp, BaseReq, BaseResp } from '@tencent/wechat_open_sdk';

const TAG: string = 'WechatPlugin';
const CHANNEL_NAME: string = 'com.jarvanmo/fluwx';
const APP_ID: string = 'wxdcb4f64316ee1d04';

/**
 * 微信事件回调：SDK 的 handleWant 会把微信回传数据分发到 onReq/onResp。
 */
class WechatEventHandler implements WXApiEventHandler {
  private channel: MethodChannel;

  constructor(channel: MethodChannel) {
    this.channel = channel;
  }

  onReq(req: BaseReq): void {
    console.info(`${TAG} onReq type=${req.type}`);
  }

  onResp(resp: BaseResp): void {
    console.info(`${TAG} onResp type=${resp.type} errCode=${resp.errCode}`);
    // 登录授权结果：通过 fluwx 同名单通道回传 onAuthResponse
    // Dart 侧 WeChatAuthResponse.fromMap 需要字段：errCode/errStr/type/country/lang/code/state
    if (resp instanceof SendAuthResp) {
      this.channel.invokeMethod('onAuthResponse', {
        'errCode': resp.errCode,
        'errStr': resp.errStr ?? '',
        'type': 1,
        'country': resp.country ?? '',
        'lang': resp.lang ?? '',
        'code': resp.code ?? '',
        'state': resp.state ?? '',
      });
    }
  }
}

/**
 * 在鸿蒙侧实现 fluwx 的 MethodChannel（com.jarvanmo/fluwx），
 * 底层使用微信官方 OpenSDK for HarmonyOS Next（@tencent/wechat_open_sdk）。
 * Dart 侧 fluwx 代码无需任何改动即可复用：isWeChatInstalled / registerApp / sendAuth。
 */
export class WechatPlugin implements MethodCallHandler {
  private channel: MethodChannel;
  private eventHandler: WechatEventHandler;
  private wxApi: WXApi | null = null;
  private context: common.UIAbilityContext;

  constructor(flutterEngine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), CHANNEL_NAME);
    this.eventHandler = new WechatEventHandler(this.channel);
    this.channel.setMethodCallHandler(this);
    try {
      this.wxApi = WXAPIFactory.createWXAPI(APP_ID, context);
    } catch (e) {
      console.error(`${TAG} createWXAPI error: ${e}`);
    }
  }

  /** 处理微信跳回本应用的 want（登录授权回调等） */
  handleWant(want: Want): void {
    try {
      if (this.wxApi == null) {
        return;
      }
      this.wxApi.handleWant(want, this.eventHandler);
    } catch (e) {
      console.error(`${TAG} handleWant error: ${e}`);
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (call.method === 'registerApp') {
        // 已在构造函数中 createWXAPI 完成注册
        result.success(true);
      } else if (call.method === 'isWeChatInstalled') {
        result.success(this.wxApi?.isWXAppInstalled() ?? false);
      } else if (call.method === 'sendAuth') {
        this.sendAuth(call, result);
      } else {
        result.notImplemented();
      }
    } catch (e) {
      result.error('WechatError', `${e}`, null);
    }
  }

  private sendAuth(call: MethodCall, result: MethodResult): void {
    if (this.wxApi == null) {
      result.success(false);
      return;
    }
    const scope: string = (call.argument('scope') as string) ?? 'snsapi_userinfo';
    const state: string = (call.argument('state') as string) ?? 'state';
    const nonAutomatic: boolean = (call.argument('nonAutomatic') as boolean) ?? false;

    const req = new SendAuthReq();
    req.isOption1 = false;
    req.nonAutomatic = nonAutomatic;
    req.scope = scope;
    req.state = state;

    const wrap = this.wxApi.sendReq(this.context, req);
    if (typeof wrap === 'boolean') {
      result.success(wrap);
    } else {
      wrap.then((ok: boolean) => {
        result.success(ok);
      }).catch((e: Error) => {
        console.error(`${TAG} sendReq error: ${e}`);
        result.success(false);
      });
    }
  }
}
