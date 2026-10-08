import Flutter
import UIKit
import Network
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// 内购商品查询器（需持有强引用，SKProductsRequest 不能被提前释放）
  private var iapFetcher: IapProductsFetcher?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "fmlink/network_info",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getNetworkType" {
          self.getNetworkType { type in
            result(type)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // 泛票内购：商品 ID 由 Dart 侧 IapService 写死传入
      // - queryProducts：StoreKit 查询商品与本地化价格
      // - buyProduct：拉起 StoreKit 支付，成功后回传交易号与收据（供服务端验证入账）
      let iapChannel = FlutterMethodChannel(
        name: "fmlink/iap",
        binaryMessenger: controller.binaryMessenger
      )
      iapChannel.setMethodCallHandler { [weak self] (call, result) in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "queryProducts":
          let productIds = args?["productIds"] as? [String] ?? []
          guard !productIds.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "商品参数为空", details: nil))
            return
          }
          self?.iapFetcher?.fetch(productIds: productIds) { products, error in
            if let error = error {
              result(FlutterError(
                code: "IAP_QUERY_FAILED",
                message: "获取充值商品失败，请稍后重试",
                details: error.localizedDescription
              ))
            } else {
              result(products ?? [])
            }
          }
        case "buyProduct":
          let productId = args?["productId"] as? String ?? ""
          guard !productId.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "商品参数为空", details: nil))
            return
          }
          IapPurchaseManager.shared.buy(productId: productId, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      self.iapFetcher = IapProductsFetcher()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 获取当前网络类型：wifi / cellular / none / unknown（异步回调）
  private func getNetworkType(completion: @escaping (String) -> Void) {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      var type = "unknown"
      if path.status == .satisfied {
        if path.usesInterfaceType(.wifi) {
          type = "wifi"
        } else if path.usesInterfaceType(.cellular) {
          type = "cellular"
        }
      } else {
        type = "none"
      }
      monitor.cancel()
      completion(type)
    }
    monitor.start(queue: DispatchQueue(label: "network_monitor"))
  }
}

/// 泛票内购商品查询（StoreKit 1：SKProductsRequest，兼容工程当前的 iOS 12 部署目标）
///
/// 返回给 Dart 侧：`[{productId, name, price, displayPrice, currency}]`，
/// 其中 `price` 为商店价格数值，`displayPrice` 为按商店地区格式化后的展示价。
class IapProductsFetcher: NSObject, SKProductsRequestDelegate {
  private var request: SKProductsRequest?
  private var completion: (([[String: Any]]?, Error?) -> Void)?

  func fetch(productIds: [String], completion: @escaping ([[String: Any]]?, Error?) -> Void) {
    self.completion = completion
    let request = SKProductsRequest(productIdentifiers: Set(productIds))
    request.delegate = self
    self.request = request
    request.start()
  }

  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    var list: [[String: Any]] = []
    for product in response.products {
      let formatter = NumberFormatter()
      formatter.numberStyle = .currency
      formatter.locale = product.priceLocale
      list.append([
        "productId": product.productIdentifier,
        "name": product.localizedTitle,
        "price": product.price.doubleValue,
        "displayPrice": formatter.string(from: product.price) ?? "",
        "currency": product.priceLocale.currencyCode ?? "",
      ])
    }
    if list.isEmpty {
      print("StoreKit 未返回任何商品，请检查 App Store Connect 商品配置与协议状态")
    }
    finish(list: list, error: nil)
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    print("StoreKit 商品查询失败: \(error.localizedDescription)")
    finish(list: nil, error: error)
  }

  private func finish(list: [[String: Any]]?, error: Error?) {
    let completion = self.completion
    self.completion = nil
    self.request = nil
    // Flutter 的 result 必须在平台线程回调
    DispatchQueue.main.async { completion?(list, error) }
  }
}

/// 泛票内购支付（StoreKit 1：SKPaymentQueue，兼容工程当前的 iOS 12 部署目标）
///
/// Dart 侧 `IapService.purchase()` → 本类 `buy(productId:)`：
/// 1. 用 `SKProductsRequest` 取回 `SKProduct`（StoreKit 1 下单必须用 SKProduct 构造 SKPayment）；
/// 2. 加入 `SKPaymentQueue` 拉起系统支付面板；
/// 3. 交易完成后回调 Dart：`{productId, transactionId, receipt}`，并 `finishTransaction` 收尾。
///
/// 用户取消回 `USER_CANCELED` 错误码，Dart 侧据此静默处理（不弹错误提示）。
class IapPurchaseManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
  static let shared = IapPurchaseManager()

  /// 当前等待回调的 Dart result（同一时刻只允许一笔支付）
  private var pendingResult: FlutterResult?
  /// 商品查询请求（需持有强引用，SKProductsRequest 不能被提前释放）
  private var request: SKProductsRequest?

  private override init() {
    super.init()
    SKPaymentQueue.default().add(self)
  }

  deinit {
    SKPaymentQueue.default().remove(self)
  }

  /// 发起支付：先查商品，再走支付队列
  func buy(productId: String, result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "PURCHASE_IN_PROGRESS", message: "有未完成的支付，请稍后重试", details: nil))
      return
    }
    pendingResult = result

    let request = SKProductsRequest(productIdentifiers: Set([productId]))
    request.delegate = self
    self.request = request
    request.start()
  }

  // MARK: - SKProductsRequestDelegate

  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    self.request = nil
    guard let product = response.products.first else {
      print("StoreKit 未返回商品 \(response.invalidProductIdentifiers)，请检查 App Store Connect 商品配置")
      finishWithError(code: "INVALID_PRODUCT", message: "充值商品暂不可用，请稍后重试", details: nil)
      return
    }
    SKPaymentQueue.default().add(SKPayment(product: product))
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    self.request = nil
    finishWithError(code: "IAP_QUERY_FAILED", message: "充值失败，请稍后重试", details: error.localizedDescription)
  }

  // MARK: - SKPaymentTransactionObserver

  func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    for transaction in transactions {
      switch transaction.transactionState {
      case .purchased:
        let payload: [String: Any] = [
          "productId": transaction.payment.productIdentifier,
          "transactionId": transaction.transactionIdentifier ?? "",
          "receipt": receiptBase64() ?? "",
        ]
        queue.finishTransaction(transaction)
        finishWithSuccess(payload)
      case .failed:
        let error = transaction.error as NSError?
        queue.finishTransaction(transaction)
        if let error = error, error.domain == SKErrorDomain, error.code == SKError.paymentCancelled.rawValue {
          finishWithError(code: "USER_CANCELED", message: "已取消支付", details: error.localizedDescription)
        } else {
          finishWithError(code: "IAP_PURCHASE_FAILED", message: "充值失败，请稍后重试", details: error?.localizedDescription)
        }
      case .restored:
        // 泛票为消耗型商品，不支持恢复购买，直接结束这笔残留交易
        queue.finishTransaction(transaction)
      case .purchasing, .deferred:
        // 支付中 / 等待系统确认：保持 pendingResult，等后续回调
        break
      @unknown default:
        break
      }
    }
  }

  // MARK: - 回调收尾

  private func finishWithSuccess(_ payload: [String: Any]) {
    guard let result = consumePendingResult() else { return }
    DispatchQueue.main.async { result(payload) }
  }

  private func finishWithError(code: String, message: String, details: String?) {
    guard let result = consumePendingResult() else { return }
    DispatchQueue.main.async { result(FlutterError(code: code, message: message, details: details)) }
  }

  private func consumePendingResult() -> FlutterResult? {
    let result = pendingResult
    pendingResult = nil
    return result
  }

  /// 读取 App Store 收据（base64）供服务端校验；取不到时返回 nil（不阻断支付）
  private func receiptBase64() -> String? {
    guard let url = Bundle.main.appStoreReceiptURL,
          let data = try? Data(contentsOf: url) else {
      print("未取到 App Store 收据（未登录沙盒账号 / 未开通内购时可能为空）")
      return nil
    }
    return data.base64EncodedString()
  }
}
