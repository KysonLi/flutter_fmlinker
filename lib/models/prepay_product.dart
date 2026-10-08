/// 泛票充值商品（由平台商店查询得到，productId 在 `IapService` 里按平台写死）
///
/// 档位与价格均以商店返回为准：
/// - iOS：StoreKit `SKProductsRequest` → 本地化商品名/价格
/// - 鸿蒙：IAP Kit `iap.queryProducts` → AGC 配置的商品
class PrepayProduct {
  const PrepayProduct({
    required this.productId,
    this.name = '',
    this.tickets = 0,
    this.price = 0,
    this.displayPrice = '',
  });

  /// 商店商品 ID（StoreKit / IAP Kit 下单用）
  final String productId;

  /// 商品名（商店商品标题）
  final String name;

  /// 泛票数量
  final num tickets;

  /// 售价数值（元，商店返回）
  final num price;

  /// 商店本地化展示价（如「¥6.00」，优先展示）
  final String displayPrice;

  /// 档位主文案：优先显示泛票数，取不到时退回商品名
  String get ticketsLabel => tickets > 0 ? '${formatNum(tickets)}泛票' : name;

  /// 售价文案：优先用商店本地化价格（App Store / AGC 价格可能与后台金额不一致）
  String get priceLabel {
    if (displayPrice.isNotEmpty) return '售价$displayPrice';
    return price > 0 ? '售价${formatNum(price)}元' : '';
  }

  /// 数字展示：整数不带小数位（6.00 → 6，6.5 → 6.50）
  static String formatNum(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);
}
