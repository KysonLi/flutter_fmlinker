import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';

const TAG: string = 'IapPlugin';
const CHANNEL_NAME: string = 'fmlink/iap';

/** 回传给 Dart 侧的商品信息（名称与价格均以商店为准） */
interface IapProductInfo {
  productId: string;
  name: string;
  /** 售价数值：商店 microPrice（价格 × 1,000,000）换算为元 */
  price: number;
  /** 商店本地化展示价（含货币符号） */
  displayPrice: string;
  currency: string;
}

/** 回传给 Dart 侧的错误信息（PlatformException 的 code/message/details） */
interface IapError {
  code: string;
  message: string;
  details: Object;
}

/** 支付成功后回传给 Dart 侧的结果（purchaseData 为 JSON 字符串，原样交给 Dart 解析） */
interface IapPurchaseInfo {
  productId: string;
  /** 华为返回的订单数据（JSON 字符串：purchaseToken / purchaseOrderId / purchaseState …） */
  purchaseData: string;
}

/**
 * 泛票内购商品查询 MethodChannel（fmlink/iap）
 *
 * Dart 侧 `IapService` 里按平台写死了商品 ID（fanpiao_6_6 / fanpiao_18_18 …），
 * 这里用 IAP Kit（@kit.IAPKit → iap.queryProducts）向 AGC 查询商品与本地化价格，
 * Dart 侧再按 productId 映射成充值档位。
 *
 * 前置条件：AGC 已创建应用、开通「应用内支付」服务，并配置好与 Dart 侧一致的商品 ID。
 *
 * 错误码（对应 iap.queryProducts 文档）：
 * - 401        参数错误
 * - 1001860002 应用未授权（AGC 未开通/配置有误）
 * - 1001860003 商品信息无效（商品不存在/未上架；或当前华为账号非沙盒测试账号，
 *              看不到「未上架」的商品——未上架应用/商品必须用沙盒账号登录 AppGallery 才能查到）
 * - 1001860004 调用过于频繁
 * - 1001860005 网络连接错误
 * - 1001860007 商品所属应用未在指定地区发布
 * - 1001860050 未登录华为账号
 */
export class IapPlugin implements MethodCallHandler {
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

  /** 由 EntryAbility 在 onWindowStageCreate 时注入（IAP Kit 需要 UIAbilityContext） */
  setWindowStage(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'queryProducts') {
      this.queryProducts(call, result);
    } else if (call.method === 'buyProduct') {
      this.buyProduct(call, result);
    } else if (call.method === 'queryPendingPurchases') {
      this.queryPendingPurchases(call, result);
    } else if (call.method === 'finishPurchase') {
      this.finishPurchase(call, result);
    } else {
      result.notImplemented();
    }
  }

  /** 取 IAP Kit 需要的 UIAbilityContext（优先取窗口 UIContext 的宿主上下文） */
  private resolveContext(): common.UIAbilityContext {
    try {
      const uiContext = this.windowStage?.getMainWindowSync().getUIContext();
      if (uiContext !== undefined) {
        const hostContext = uiContext.getHostContext();
        if (hostContext !== undefined) {
          return hostContext as common.UIAbilityContext;
        }
      }
    } catch (e) {
      console.error(`${TAG} getUIContext failed: ${e}`);
    }
    return this.context;
  }

  /** 查询 AGC 配置的泛票商品（消耗型） */
  private queryProducts(call: MethodCall, result: MethodResult): void {
    const ids = call.argument('productIds') as string[] | undefined;
    const productIds: string[] = ids ?? [];
    if (productIds.length === 0) {
      result.error('INVALID_ARGUMENT', '商品参数为空', 'productIds');
      return;
    }

    const parameter: iap.QueryProductsParameter = {
      // 泛票为消耗型商品
      productType: iap.ProductType.CONSUMABLE,
      productIds: productIds,
    };

    console.info(`${TAG} queryProducts request, productIds=${JSON.stringify(productIds)}`);

    iap.queryProducts(this.resolveContext(), parameter)
      .then((products: iap.Product[]) => {
        const list: IapProductInfo[] = [];
        products.forEach((product: iap.Product) => {
          list.push({
            productId: product.id,
            name: product.name,
            price: product.microPrice / 1000000,
            displayPrice: product.localPrice ?? product.price,
            currency: product.currency,
          });
        });
        // 打印返回的 ID，便于和请求 ID 对比排查「哪个商品在 AGC 查不到」
        console.info(
          `${TAG} queryProducts success, count=${list.length}, ids=${list.map((p: IapProductInfo) => p.productId).join(',')}`,
        );
        // 统一包一层 data，与 Dart 侧 IapService 的读取结构对齐
        result.success({ 'data': list });
      })
      .catch((e: BusinessError) => {
        console.error(`${TAG} queryProducts failed: code=${e.code} message=${e.message}`);
        const info: IapError = this.mapError(e, '获取充值商品失败，请稍后重试');
        result.error(info.code, info.message, info.details);
      });
  }

  /**
   * 拉起华为应用内支付（泛票为消耗型商品）
   *
   * 成功后把 `purchaseData`（JSON 字符串）交给 Dart 侧，由 Dart 解析出
   * purchaseToken / purchaseOrderId 再调服务端 `/pos/v1/prepay/prepay_huawei` 验证入账；
   * 入账成功后 Dart 侧再调 [finishPurchase] 结束交易（消耗型商品不结束将无法重复购买）。
   */
  private buyProduct(call: MethodCall, result: MethodResult): void {
    const id = call.argument('productId') as string | undefined;
    const productId: string = id ?? '';
    if (productId.length === 0) {
      result.error('INVALID_ARGUMENT', '商品参数为空', 'productId');
      return;
    }

    const parameter: iap.PurchaseParameter = {
      productType: iap.ProductType.CONSUMABLE,
      productId: productId,
    };

    iap.createPurchase(this.resolveContext(), parameter)
      .then((createResult: iap.CreatePurchaseResult) => {
        console.info(`${TAG} createPurchase success, productId=${productId}`);
        const info: IapPurchaseInfo = {
          productId: productId,
          purchaseData: createResult.purchaseData,
        };
        result.success(info);
      })
      .catch((e: BusinessError) => {
        console.error(`${TAG} createPurchase failed: code=${e.code} message=${e.message}`);
        const info: IapError = this.mapError(e);
        result.error(info.code, info.message, info.details);
      });
  }

  /**
   * 查询华为侧的已购订单——充值补发用，防丢单
   *
   * `iap.queryPurchases`，`queryType` 由 Dart 侧传入：
   * - `1` UNFINISHED（默认）：已支付但未发货/未完成的订单（常规补发）
   * - `0` ALL：全部已购订单（兜底，用于华为侧状态与预期不一致、或订单已被确认发货的场景）
   *
   * purchaseDataList 为签名的订单 JSON 字符串（含 purchaseToken / purchaseOrderId），
   * Dart 侧解析后重新调服务端 `/pos/v1/prepay/prepay_huawei` 入账（服务端按订单号幂等）。
   */
  private queryPendingPurchases(call: MethodCall, result: MethodResult): void {
    const typeArg = call.argument('queryType') as number | undefined;
    const queryType: iap.PurchaseQueryType =
      typeArg === 0 ? iap.PurchaseQueryType.ALL : iap.PurchaseQueryType.UNFINISHED;

    const parameter: iap.QueryPurchasesParameter = {
      productType: iap.ProductType.CONSUMABLE,
      queryType: queryType,
    };

    iap.queryPurchases(this.resolveContext(), parameter)
      .then((res: iap.QueryPurchaseResult) => {
        console.info(`${TAG} queryPurchases success, queryType=${queryType}, count=${res.purchaseDataList.length}`);
        result.success({ 'data': res.purchaseDataList });
      })
      .catch((e: BusinessError) => {
        console.error(`${TAG} queryPurchases failed: code=${e.code} message=${e.message}`);
        const info: IapError = this.mapError(e, '查询未完成订单失败，请稍后重试');
        result.error(info.code, info.message, info.details);
      });
  }

  /**
   * 结束交易（消耗型商品发货确认）
   *
   * 服务端入账成功后调用：华为侧才会把该笔订单标记为已发放，否则用户无法重复购买同一商品。
   */
  private finishPurchase(call: MethodCall, result: MethodResult): void {
    const tokenArg = call.argument('purchaseToken') as string | undefined;
    const orderArg = call.argument('purchaseOrderId') as string | undefined;
    const purchaseToken: string = tokenArg ?? '';
    const purchaseOrderId: string = orderArg ?? '';
    if (purchaseToken.length === 0 || purchaseOrderId.length === 0) {
      result.error('INVALID_ARGUMENT', '缺少订单凭证', 'purchaseToken/purchaseOrderId');
      return;
    }

    const parameter: iap.FinishPurchaseParameter = {
      productType: iap.ProductType.CONSUMABLE,
      purchaseToken: purchaseToken,
      purchaseOrderId: purchaseOrderId,
    };

    iap.finishPurchase(this.resolveContext(), parameter)
      .then(() => {
        console.info(`${TAG} finishPurchase success, orderId=${purchaseOrderId}`);
        result.success(true);
      })
      .catch((e: BusinessError) => {
        console.error(`${TAG} finishPurchase failed: code=${e.code} message=${e.message}`);
        const info: IapError = this.mapError(e, '充值商品确认失败，请稍后在充值记录中查看');
        result.error(info.code, info.message, info.details);
      });
  }

  /**
   * 把 IAP Kit 的错误码翻译成 Dart 侧可直接展示的文案
   * （用户可见文案为友好提示，原始错误码只写到 hilog 与 PlatformException.details）
   *
   * @param fallback 未匹配到已知错误码时的兜底文案（查询商品与支付流程的兜底不同）
   */
  private mapError(err: BusinessError, fallback: string = '充值失败，请稍后重试'): IapError {
    const code: number = err.code;
    if (code === 1001860050) {
      return { code: 'HUAWEI_ID_NOT_SIGNED_IN', message: '请先登录华为账号后重试', details: code };
    } else if (code === 1001860005) {
      return { code: 'NETWORK_ERROR', message: '网络异常，请检查网络后重试', details: code };
    } else if (code === 1001860002) {
      return { code: 'APP_NOT_AUTHORIZED', message: '充值服务暂不可用，请稍后重试', details: code };
    } else if (code === 1001860003) {
      // 商品不存在/未上架；联调期最常见的原因是当前账号不是 AGC 配置的沙盒测试账号，
      // 看不到未上架的商品（真实账号能看到的只有已上架商品）
      return { code: 'INVALID_PRODUCT', message: '充值商品暂不可用，请稍后重试', details: code };
    } else if (code === 1001860007) {
      return { code: 'APP_NOT_PUBLISHED', message: '当前地区暂不支持充值，请稍后重试', details: code };
    } else if (code === 1001860004) {
      return { code: 'TOO_FREQUENT', message: '操作过于频繁，请稍后再试', details: code };
    } else if (code === 401) {
      return { code: 'INVALID_ARGUMENT', message: '请求参数有误', details: code };
    } else if (code === 1001860000) {
      // 用户主动取消：Dart 侧据此静默处理（不弹错误提示）
      return { code: 'USER_CANCELED', message: '已取消支付', details: code };
    } else if (code === 1001860051) {
      return { code: 'ALREADY_OWNED', message: '该商品已购买，请勿重复购买', details: code };
    } else if (code === 1001860054) {
      return { code: 'REGION_NOT_SUPPORTED', message: '当前账号所在地区暂不支持充值', details: code };
    } else if (code === 1001860056) {
      return { code: 'USER_NOT_ALLOWED', message: '当前账号暂无法完成支付，请稍后重试', details: code };
    } else if (code === 1001860001) {
      return { code: 'IAP_INTERNAL_ERROR', message: '充值失败，请稍后重试', details: code };
    }
    return { code: 'IAP_PURCHASE_FAILED', message: fallback, details: code };
  }
}
