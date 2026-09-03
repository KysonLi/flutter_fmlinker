import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/user_service.dart';

/// 资源模块路由路径（供各页面/入口跳转使用）
const String kResourceListRoute = '/resource/list';
const String kResourcePlayRoute = '/resource/play';
const String kResourceSourceDetailRoute = '/resource/source-detail';
const String kResourceModel3dRoute = '/resource/model3d';
const String kIsliCopyrightRoute = '/isli/copyright';
/// 购买页（既有路由，extra 为 Map<String, dynamic> 参数）
const String kPurchaseRoute = '/purchase';
/// 通用 webview（既有路由，query: url/title）
const String kWebviewRoute = '/webview';

/// 资源播放模块统一入口
///
/// 职责：isliCode → 刷新 token → 统一 loading → 拉取链码资源数据
/// → 空态提示 → 按状态分发（需购买→购买页 / 多资源→资源列表页 / 单资源→播放页）。
///
/// hasScanUse 约定：由扫码界面进入传 true（请求 hasScanUse='false'），
/// 其它入口传 false（hasScanUse='true'）。
class ResourceEntry {
  ResourceEntry._();

  /// 由链码（isliCode，可带连字符）进入资源模块
  static Future<void> openFromCode(
    BuildContext context, {
    required String isliCode,
    required bool fromScan,
    String? versionCode,
  }) async {
    await UserService().refreshToken();

    EasyLoading.show(status: '加载中...');
    Map<String, dynamic> res;
    try {
      res = await ResourceService().fetchSourceScan(
        isliCode,
        pageIndex: 1,
        pageSize: 20,
        fromScan: fromScan,
        versionCode: versionCode,
      );
    } catch (e) {
      EasyLoading.dismiss();
      if (context.mounted) EasyLoading.showToast('查询资源失败，请重试');
      return;
    }
    EasyLoading.dismiss();
    if (context.mounted) {
      _dispatch(context, res, isliCode, fromScan);
    }
  }

  /// 拉取结果分发（同步方法，避免跨 async 间隙使用 context）
  static void _dispatch(
    BuildContext context,
    Map<String, dynamic> res,
    String isliCode,
    bool fromScan,
  ) {
    if (res['status'] != true || res['data'] == null) {
      EasyLoading.showToast(res['msg']?.toString() ?? '查询资源失败，请重试');
      return;
    }

    final SourceScanData data = SourceScanData.fromJson(res['data'] as Map<String, dynamic>);
    final String digits = ResourceService().isliDigits(isliCode);

    final int resourceTotal = data.resourceCount ??
        (data.currentTarget?.resourceCount ?? 0);
    final bool hasResource = data.currentResources.isNotEmpty || resourceTotal > 0;
    if (!hasResource) {
      EasyLoading.showToast('未获取到关联资源');
      return;
    }

    // 收费且当前源未购买 → 购买页（购买后重新进入即可查看）
    if (data.needPurchase) {
      _pushPurchase(context, data);
      return;
    }

    // 仅当前源实际资源数 > 1 才进资源列表页；
    // 单资源直接进播放页，需购买（needPurchase）已在上方分流到购买页
    final bool multi = data.currentResources.length > 1;
    if (multi) {
      _pushList(context,
          isliCode: digits, fromScan: fromScan, versionCode: data.versionCode?.toString());
    } else {
      _pushPlay(context,
          isliCode: digits,
          fromScan: fromScan,
          versionCode: data.versionCode?.toString(),
          startIndex: 0);
    }
  }

  // ==================== 页面跳转 ====================

  static void _pushPlay(
    BuildContext context, {
    required String isliCode,
    required bool fromScan,
    String? versionCode,
    int startIndex = 0,
  }) {
    context.push(kResourcePlayRoute, extra: <String, dynamic>{
      'isliCode': isliCode,
      'fromScan': fromScan,
      'versionCode': versionCode ?? '',
      'startIndex': startIndex,
    });
  }

  static void _pushList(
    BuildContext context, {
    required String isliCode,
    required bool fromScan,
    String? versionCode,
  }) {
    context.push(kResourceListRoute, extra: <String, dynamic>{
      'isliCode': isliCode,
      'fromScan': fromScan,
      'versionCode': versionCode ?? '',
    });
  }

  /// 播放页（从资源列表页点击某资源进入，指定起始下标）
  static void pushPlay(BuildContext context,
      {required String isliCode,
      required bool fromScan,
      String? versionCode,
      int startIndex = 0}) {
    _pushPlay(context,
        isliCode: isliCode,
        fromScan: fromScan,
        versionCode: versionCode,
        startIndex: startIndex);
  }

  /// 购买页（购买参数与既有 PurchaseScreen.params 保持一致）
  static void _pushPurchase(BuildContext context, SourceScanData data) {
    final Map<String, dynamic> params = buildPurchaseParams(data);
    context.push(kPurchaseRoute, extra: params);
  }

  /// 资源播放/列表页内点击未解锁资源 → 购买页
  static void pushPurchaseForData(BuildContext context, SourceScanData data,
      {String? sourceName}) {
    final Map<String, dynamic> params = buildPurchaseParams(data);
    if (sourceName != null && sourceName.isNotEmpty) {
      params['sourceName'] = sourceName;
    }
    context.push(kPurchaseRoute, extra: params);
  }

  /// 组装购买页参数（字段含义见 PurchaseScreen.params 注释）
  static Map<String, dynamic> buildPurchaseParams(SourceScanData data,
      {String? sourceName}) {
    final ChainSourceInfo? s = data.source;
    return <String, dynamic>{
      'goodsId': data.goodsId,
      'goodsName': data.goodsName ?? '',
      'cover': data.goodsImage ?? '',
      'shopId': data.shopId ?? '',
      'serviceCode': data.serviceCode ?? (s?.serviceCode ?? ''),
      'prefixCode': data.prefixCode ?? (s?.prefixCode ?? ''),
      'versionCode': data.versionCode,
      'pricingStrategy': data.strategyType ?? '',
      'sourceIdentifier': s?.sourceIdentifier ?? '',
      'sourceName': sourceName ?? '',
      'sourcePrice': s?.price,
      'sourceFree': s?.free,
      'sourcePay': s?.pay,
      'sourceNo': s?.sourceNo,
      'totalPrice': data.totalPrice,
      'benefitPrice': data.benefitPrice,
      'isBenefit': data.isBenefit,
    };
  }

  /// 标志码版权详情页（扫码 2D 标志码 / 链码 ISBN/ISSN 解析 markCode 后进入）
  static void openIsliCopyright(BuildContext context, String mprCode) {
    context.push('$kIsliCopyrightRoute?mprCode=${Uri.encodeComponent(mprCode)}');
  }
}
