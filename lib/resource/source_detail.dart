import 'package:fmlink/common/isli_constants.dart';
import 'package:fmlink/resource/resource_types.dart';

/// 资源播放模块数据模型
///
/// 字段与后端 /target-goods/app/v1/source/scan/:isliCode 及
/// /pics/v1/isliContents/:mprCode 返回保持一致（参考小程序端同后端实现）。
///
/// 数据层级：goods(出版物) → source(链码，sourceIdentifier) → target(1:1 source)
/// → resource(1~N，实际播放对象)。

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? _toBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    return v.trim() == 'true' || v.trim() == '1' ? true : false;
  }
  return null;
}

String? _toStr(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

/// 当前链码（source）信息：/source/scan 返回 data.source
class ChainSourceInfo {
  final Map<String, dynamic> raw;

  ChainSourceInfo(this.raw);

  factory ChainSourceInfo.fromJson(Map<String, dynamic> json) =>
      ChainSourceInfo(json);

  /// 源 ID
  int? get sourceId => _toInt(raw['sourceId']);

  /// 完整 ISLI 链码（带连字符，如 000000-000026477599999）
  String? get sourceIdentifier => _toStr(raw['sourceIdentifier']);

  /// 源序号（链码序号）
  int? get sourceNo => _toInt(raw['sourceNo']);

  /// 所在图书页码
  int? get bookPageNo => _toInt(raw['bookPageNo']);

  /// 源片段/文字摘要
  String? get sourceFragment => _toStr(raw['sourceFragment']);

  /// 章节/篇目信息
  String? get article => _toStr(raw['article']);
  String? get chapter => _toStr(raw['chapter']);
  String? get serviceCode => _toStr(raw['serviceCode']);
  String? get prefixCode => _toStr(raw['prefixCode']);
  int? get versionCode => _toInt(raw['versionCode']);

  /// 关联资源总数
  int? get resourceCount => _toInt(raw['resourceCount']);

  /// 单源售价
  num? get price => _toNum(raw['price']);

  /// 是否免费资源
  bool? get free => _toBool(raw['free']);

  /// 是否已购买
  bool? get pay => _toBool(raw['pay']);

  /// 是否在售
  bool? get sell => _toBool(raw['sell']);

  /// 当前源是否可直接访问（免费或已购）
  bool get accessible => free == true || pay == true;
}

/// 资源项：data.targetList[].resources[]
class ScanResource {
  final Map<String, dynamic> raw;

  ScanResource(this.raw);

  factory ScanResource.fromJson(Map<String, dynamic> json) =>
      ScanResource(json);

  int? get id => _toInt(raw['id']);

  String? get resourceId => _toStr(raw['resourceId']);

  /// 资源类型原始值（后端返回字符串或数字），经 ResourceType.fromRaw 归一
  ResourceType get type => ResourceType.fromRaw(raw['resourceType']);

  /// 资源序号（在当前源内的序号）
  int? get resourceNo => _toInt(raw['resourceNo']);

  String? get resourceName => _toStr(raw['resourceName']);

  /// 资源封面（图片/视频海报）
  String? get resourcePoster => _toStr(raw['resourcePoster']);

  /// 资源地址（文本/图片/音视频/网页）
  String? get resourceAddress => _toStr(raw['resourceAddress']);

  /// 资源后缀（txt/jpg/mp4/html...）
  String? get resourceSuffix => _toStr(raw['resourceSuffix']);

  /// 时长（音视频，秒）
  num? get second => _toNum(raw['second']);

  String? get resourceMD5 => _toStr(raw['resourceMD5']);

  String? get resourceSize => _toStr(raw['resourceSize']);

  int? get updateTime => _toInt(raw['updateTime']);

  /// 当前用户是否已点赞
  bool? get hasLike => _toBool(raw['hasLike']);

  /// 点赞数
  int? get likeCount => _toInt(raw['likeCount']);

  /// 是否分片资源
  bool? get segment => _toBool(raw['segment']);

  /// 清洗后的资源地址
  String get cleanAddress => cleanUrl(resourceAddress);

  /// 是否收费资源（free == false 视为收费，需要购买后才有地址）
  bool get isCharge => !(raw['free'] == true || raw['free'] == 'true');
}

/// target 项：data.targetList[]
class ScanTarget {
  final Map<String, dynamic> raw;

  ScanTarget(this.raw);

  factory ScanTarget.fromJson(Map<String, dynamic> json) => ScanTarget(json);

  int? get targetId => _toInt(raw['targetId']);

  String? get targetIdentifier => _toStr(raw['targetIdentifier']);

  String? get targetName => _toStr(raw['targetName']);

  String? get strategyType => _toStr(raw['strategyType']);

  String? get targetFormat => _toStr(raw['targetFormat']);

  int? get targetStatus => _toInt(raw['targetStatus']);

  int? get versionCode => _toInt(raw['versionCode']);

  int? get resourceCount => _toInt(raw['resourceCount']);

  String? get sourceIdentifier => _toStr(raw['sourceIdentifier']);

  /// 资源列表
  List<ScanResource> get resources {
    final List<dynamic> list =
        raw['resources'] is List ? raw['resources'] as List : const [];
    return list
        .map((dynamic e) =>
            ScanResource.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

/// /target-goods/app/v1/source/scan/:isliCode 返回 data 结构
class SourceScanData {
  final Map<String, dynamic> raw;

  SourceScanData(this.raw);

  factory SourceScanData.fromJson(Map<String, dynamic> json) =>
      SourceScanData(json);

  String? get serviceCode => _toStr(raw['serviceCode']);
  String? get prefixCode => _toStr(raw['prefixCode']);
  int? get versionCode => _toInt(raw['versionCode']);
  String? get versionInfo => _toStr(raw['versionInfo']);

  /// 整书总价（原价）
  num? get totalPrice => _toNum(raw['totalPrice']);

  /// 整书优惠价
  num? get benefitPrice => _toNum(raw['benefitPrice']);

  /// 是否开启优惠
  bool? get isBenefit => _toBool(raw['isBenefit']);

  /// 定价策略：CHAIN_ALL_FREE / CHAIN_UNIFORM_PRICE / ...
  String? get strategyType => _toStr(raw['strategyType']);

  /// 出版物信息
  num? get goodsIdNum => _toNum(raw['goodsId']);
  String get goodsId => (goodsIdNum ?? raw['goodsId'] ?? '').toString();
  String? get goodsName => _toStr(raw['goodsName']);
  String? get goodsImage => _toStr(raw['goodsImage']);
  String? get shopId => _toStr(raw['shopId']);
  String? get goodsDesc => _toStr(raw['goodsDesc']);
  String? get goodsIcon => _toStr(raw['goodsIcon']);

  /// 当前链码对应的源信息
  ChainSourceInfo? get source {
    final dynamic s = raw['source'];
    if (s is Map) return ChainSourceInfo.fromJson(s.cast<String, dynamic>());
    return null;
  }

  /// target 列表（单个 source 只对应一个 target）
  List<ScanTarget> get targetList {
    final List<dynamic> list =
        raw['targetList'] is List ? raw['targetList'] as List : const [];
    return list
        .map((dynamic e) =>
            ScanTarget.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  int? get sourceCount => _toInt(raw['sourceCount']);
  int? get resourceCount => _toInt(raw['resourceCount']);

  // ---------- 业务判定辅助 ----------

  /// 当前链码的 target（约定单个 source 只对应一个 target）
  ScanTarget? get currentTarget => targetList.isEmpty ? null : targetList.first;

  /// 当前链码资源列表（来自 currentTarget.resources）
  List<ScanResource> get currentResources =>
      currentTarget?.resources ?? const [];

  /// 是否免费策略（整书资源全部免费）
  bool get isAllFreeStrategy => strategyType == PricingStrategy.allFree;

  /// 是否整体定价（不可单源购买）
  bool get isUniformStrategy => strategyType == PricingStrategy.uniformPrice;

  /// 当前源免费（策略级免费或源标记 free）
  bool get isSourceFree => isAllFreeStrategy || source?.free == true;

  /// 当前源已购买
  bool get isSourcePaid => source?.pay == true;

  /// 当前源可直接访问（免费或已购）
  bool get isSourceAccessible => isSourceFree || isSourcePaid;

  /// 当前源需购买（收费策略下未购买且源非免费）
  bool get needPurchase =>
      !isSourceFree && !isSourcePaid && source?.sell != false;

  /// 整书展示价（isBenefit 时取优惠价，否则取 totalPrice）
  num get wholeBasePrice {
    final bool benefit = isBenefit == true && benefitPrice != null;
    final num? price = benefit ? benefitPrice : totalPrice;
    return price ?? 0;
  }
}

/// 标志码版权信息（/pics/v1/isliContents/:mprCode 返回 data）
class IsliCopyrightData {
  final Map<String, dynamic> raw;

  IsliCopyrightData(this.raw);

  factory IsliCopyrightData.fromJson(Map<String, dynamic> json) =>
      IsliCopyrightData(json);

  String? get bookName => _toStr(raw['bookName']);
  String? get isliCodeType => _toStr(raw['isliCodeType']);
  String? get isbn => _toStr(raw['isbn']);
  String? get cn => _toStr(raw['cn']);
  String? get issn => _toStr(raw['issn']);
  String? get isrc => _toStr(raw['isrc']);
  String? get mprCode => _toStr(raw['mprCode']);

  /// 完整 ISLI 编码（带连字符）
  String? get isliCode => _toStr(raw['isliCode']);
  String? get publisherName => _toStr(raw['publisherName']);
  String? get author => _toStr(raw['author']);

  /// 定价，格式 "6,CNY"
  String? get price => _toStr(raw['price']);
  String? get contentType => _toStr(raw['contentType']);
  String? get imageUrl => _toStr(raw['imageUrl']);
  String? get content => _toStr(raw['content']);
  String? get contentUrl => _toStr(raw['contentUrl']);
  String? get unificationId => _toStr(raw['unificationId']);
  int? get releaseStatus => _toInt(raw['releaseStatus']);
  String? get createTime => _toStr(raw['createTime']);
  String? get updateTime => _toStr(raw['updateTime']);
  String? get videoCover => _toStr(raw['videoCover']);

  String get cover => cleanUrl(imageUrl);
  String get contentAddress => cleanUrl(contentUrl);
}

/// 金额文本（保留两位小数）
String moneyText(num? value) {
  if (value == null) return '0.00';
  final double v = value.toDouble();
  if (v == v.roundToDouble()) return '${v.toStringAsFixed(0)}.00';
  return v.toStringAsFixed(2);
}
