import 'package:fmlink/cache/cache_record.dart';
import 'package:fmlink/common/isli_constants.dart';
import 'package:fmlink/resource/source_detail.dart';

/// 离线数据构建：把本地已缓存记录还原成与接口一致的 [SourceScanData]
///
/// 背景：播放页原本必须先请求 `/source/scan` 拿到资源列表才能渲染，
/// 飞行模式/无网络时接口失败会直接报「网络请求失败」，即使资源已缓存也无法播放。
///
/// 处理方式：用缓存记录（含链码、资源 ID、资源下标、地址、类型）拼出与接口同构的数据，
/// 页面逻辑与各资源视图完全复用（文本/图片/视频/音频视图本身已「本地优先」），
/// 从而实现真正的离线播放。
///
/// 注意：
/// - `free/pay` 标记为已解锁，避免离线时误判为待购买
/// - `strategyType` 用免费策略，使 `isSourceAccessible` 为真
/// - `id/resourceId` 必须与缓存记录对齐，页面才能通过 `CacheService.recordFor`
///   匹配到本地文件
SourceScanData? buildOfflineScanData(
  List<CacheRecord> records, {
  required String isliCode,
  String? versionCode,
}) {
  if (records.isEmpty) return null;

  final CacheRecord first = records.first;
  final int? version = int.tryParse((versionCode == null || versionCode.isEmpty)
      ? (first.versionCode ?? '')
      : versionCode);

  final List<Map<String, dynamic>> resources = <Map<String, dynamic>>[];
  for (int i = 0; i < records.length; i++) {
    final CacheRecord r = records[i];
    resources.add(<String, dynamic>{
      // 资源主键：保持与缓存记录一致，页面据此定位本地文件
      'id': int.tryParse(r.resourceId) ?? r.resourceId,
      'resourceId': r.resourceOldId,
      'resourceName': r.resourceName,
      'resourceType': r.resourceType,
      'resourceNo': r.resourceIndex > 0 ? r.resourceIndex + 1 : i + 1,
      'resourceAddress': r.url,
      'resourceSuffix': r.resourceSuffix,
      'free': true,
      // HLS 为分片资源，标识出来便于后续扩展
      'segment': r.isHlsLocal,
    });
  }

  return SourceScanData(<String, dynamic>{
    'goodsId': first.goodsId,
    'goodsName': first.goodsName,
    'goodsImage': first.goodsImage,
    'versionCode': version,
    'strategyType': PricingStrategy.allFree,
    'resourceCount': records.length,
    'source': <String, dynamic>{
      'sourceIdentifier': first.isliCode.isNotEmpty ? first.isliCode : isliCode,
      'resourceCount': records.length,
      'free': true,
      'pay': true,
      'sell': true,
    },
    'targetList': <Map<String, dynamic>>[
      <String, dynamic>{
        'resourceCount': records.length,
        'versionCode': version,
        'sourceIdentifier':
            first.isliCode.isNotEmpty ? first.isliCode : isliCode,
        'resources': resources,
      },
    ],
  });
}
