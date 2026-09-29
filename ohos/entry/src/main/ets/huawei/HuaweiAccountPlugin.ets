import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';

const TAG: string = 'HuaweiAccountPlugin';
const CHANNEL_NAME: string = 'fmlink/huawei_account';

/** 回传给 Dart 侧的错误信息（PlatformException 的 code/message/details） */
interface HuaweiLoginError {
  code: string;
  message: string;
  details: Object;
}

/**
 * 华为账号一键登录 MethodChannel（fmlink/huawei_account）
 *
 * 底层使用 HarmonyOS 华为账号 Kit（@kit.AccountKit → authentication）：
 * HuaweiIDProvider.createLoginWithHuaweiIDRequest()
 *   → AuthenticationController.executeRequest()
 *   → LoginWithHuaweiIDResponse.data（authorizationCode / idToken / openID / unionID）
 *
 * 前置条件：
 * 1. 在 AppGallery Connect 创建应用并开通「华为账号」服务；
 * 2. module.json5 的 metadata 中配置 AGC 应用的 client_id；
 * 3. 签名证书的包名与指纹需与 AGC 登记一致（否则返回 1001502002）。
 *
 * 错误码对照（authentication.AuthenticationErrorCode）：
 * - 1001500001 应用签名指纹校验失败（AGC 未配置公钥指纹）
 * - 1001502001 用户未登录华为账号
 * - 1001502002 应用未授权（AGC 未开通/证书指纹不匹配）
 * - 1001502005 网络异常
 * - 1001502012 用户取消授权
 * - 1001500002 请求重复（连续点击）
 */
export class HuaweiAccountPlugin implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;
  private windowStage: window.WindowStage | null = null;

  constructor(flutterEngine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  /** 由 EntryAbility 在 onWindowStageCreate 时注入，用于取 ArkUI 页面上下文 */
  setWindowStage(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'login') {
      this.login(call, result);
    } else {
      result.notImplemented();
    }
  }

  /**
   * 取发起登录用的上下文。
   *
   * forceLogin 为 true 时华为账号 Kit 要求请求运行在 ArkUI 页面上下文中，
   * 因此优先取窗口 UIContext 的宿主上下文（即本 Ability 的 UIAbilityContext），
   * 取不到时退回 Ability 自身的 context。
   */
  private resolveContext(): common.Context {
    try {
      const uiContext = this.windowStage?.getMainWindowSync().getUIContext();
      if (uiContext !== undefined) {
        const hostContext = uiContext.getHostContext();
        if (hostContext !== undefined) {
          return hostContext;
        }
      }
    } catch (e) {
      console.error(`${TAG} getUIContext failed: ${e}`);
    }
    return this.context;
  }

  private async login(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const forceLogin: boolean = (call.argument('forceLogin') as boolean) ?? true;

      const request: authentication.LoginWithHuaweiIDRequest =
        new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      request.forceLogin = forceLogin;
      // state 用于防跳站攻击，必须在响应中回显并校验一致（官方示例要求）
      const requestState: string = util.generateRandomUUID();
      request.state = requestState;

      const controller = new authentication.AuthenticationController(this.resolveContext());
      const response: authentication.LoginWithHuaweiIDResponse =
        (await controller.executeRequest(request)) as authentication.LoginWithHuaweiIDResponse;

      const responseState: string = response.state ?? '';
      if (responseState !== requestState) {
        console.error(`${TAG} state mismatch, request=${requestState} response=${responseState}`);
        result.error('STATE_MISMATCH', '登录校验失败，请重试', 'state');
        return;
      }

      const credential = response.data;
      if (credential === undefined) {
        console.error(`${TAG} login success but credential is empty`);
        result.error('EMPTY_CREDENTIAL', '未获取到华为账号授权信息，请重试', 'empty');
        return;
      }

      console.info(`${TAG} login success, openID=${credential.openID}`);
      // 统一包一层 data，与 Dart 侧 HuaweiAccountService 的读取结构对齐
      result.success({
        'data': {
          'authorizationCode': credential.authorizationCode ?? '',
          'idToken': credential.idToken ?? '',
          'openID': credential.openID,
          'unionID': credential.unionID,
        },
      });
    } catch (e) {
      const err = e as BusinessError;
      console.error(`${TAG} login error: code=${err.code} message=${err.message}`);
      const info: HuaweiLoginError = this.mapError(err);
      result.error(info.code, info.message, info.details);
    }
  }

  /**
   * 把华为账号 Kit 的错误码翻译成 Dart 侧可直接展示的文案。
   *
   * 按华为《HUAWEI ID 登录体验设计规范》要求，**不对用户透传原始错误码**：
   * 用户可见文案为可操作的友好提示，错误码只写到 hilog 与 PlatformException.details。
   */
  private mapError(err: BusinessError): HuaweiLoginError {
    const code: number = err.code;
    if (code === 1001500001) {
      return {
        code: 'PACKAGE_FINGERPRINT_CHECK_ERROR',
        message: '华为账号登录暂不可用，请稍后重试或使用其他方式登录',
        details: code
      };
    } else if (code === 1001502001) {
      return { code: 'ACCOUNT_NOT_LOGGED_IN', message: '请先登录华为账号后重试', details: code };
    } else if (code === 1001502002) {
      return {
        code: 'APP_NOT_AUTHORIZED',
        message: '华为账号登录暂不可用，请稍后重试或使用其他方式登录',
        details: code
      };
    } else if (code === 1001502005) {
      return { code: 'NETWORK_ERROR', message: '网络异常，请检查网络后重试', details: code };
    } else if (code === 1001502012) {
      return { code: 'USER_CANCELED', message: '已取消华为账号登录', details: code };
    } else if (code === 1001500002) {
      return { code: 'DUPLICATE_REQUEST', message: '登录请求正在处理中，请稍候', details: code };
    } else if (code === 1001500003 || code === 1001500004) {
      return {
        code: 'UNSUPPORTED',
        message: '当前华为账号暂不支持该登录方式，请使用其他方式登录',
        details: code
      };
    } else if (code === 12300001) {
      return { code: 'SYSTEM_SERVICE_ERROR', message: '华为账号服务异常，请稍后重试', details: code };
    }
    return { code: 'HUAWEI_LOGIN_FAILED', message: '华为账号登录失败，请重试', details: code };
  }
}
