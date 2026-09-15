import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/error_handler.dart';

/// 购买记录页
///
/// 数据接口：GET /pos/v1/order/target
/// 参数：userId（登录后的 unificationId）、page、pageCount
///
/// 购买单位（orderBuyType）：
/// - WHOLE_PUBLICATION：整书购买（buy_type_book 图标，进入链码列表页）
/// - SINGLE：单个源购买（buy_type_source 图标，按 ISLI 编码进入资源播放页）
class PurchaseRecordScreen extends StatefulWidget {
  const PurchaseRecordScreen({super.key});

  @override
  State<PurchaseRecordScreen> createState() => _PurchaseRecordScreenState();
}

class _PurchaseRecordScreenState extends State<PurchaseRecordScreen> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  static const int _pageSize = 20;

  List<dynamic> _list = [];
  int _pageIndex = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoad();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  /// 检查登录态：未登录显示登录引导空态，已登录拉取购买记录
  Future<void> _checkLoginAndLoad() async {
    final bool loggedIn = await _userService.checkLoginStatus();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
    if (loggedIn) {
      await _loadOrders(isRefresh: true);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOrders({bool isRefresh = false}) async {
    if (!isRefresh && (!_hasMore || _loadingMore)) {
      _refreshController.finishLoad(IndicatorResult.noMore);
      return;
    }
    if (isRefresh) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      await _userService.refreshToken();
      final String userId = await _userService.getUnificationId();
      if (userId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
          _loadingMore = false;
        });
        return;
      }

      final Map<String, dynamic> response =
          await _publishService.getPurchaseOrders(
        userId: userId,
        page: isRefresh ? 1 : _pageIndex,
        pageCount: _pageSize,
      );

      if (!mounted) return;
      if (response['status'] && response['data'] != null) {
        final List<dynamic> items = _extractList(response['data']);
        setState(() {
          if (isRefresh) {
            _list = items;
            _pageIndex = 2;
          } else {
            _list.addAll(items);
            _pageIndex++;
          }
          _hasMore = items.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        EasyLoading.showError(
            ErrorHandler().fromError(e, fallback: '获取购买记录失败'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMore = false;
        });
        if (isRefresh) {
          _refreshController.finishRefresh();
          _refreshController.resetFooter();
        } else {
          _refreshController.finishLoad(
            _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
          );
        }
      }
    }
  }

  /// 兼容接口返回数组或 {list: [...]} 两种结构
  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final dynamic list = data['list'];
      if (list is List) return list;
    }
    return [];
  }

  // ==================== 展示辅助 ====================

  /// 购买单位标签：整书 / 单个源
  String _buyTypeTag(String t) {
    if (t == 'WHOLE_PUBLICATION') return '整书';
    if (t == 'SINGLE') return '单个源';
    return '购买';
  }

  /// 记录标题：整书显示出版物名；单个源优先 goodsName，为空则用 sourceIdentifier
  String _recordTitle(dynamic item) {
    final String buyType = item['orderBuyType']?.toString() ?? '';
    if (buyType == 'WHOLE_PUBLICATION') {
      return item['wholePublicationName']?.toString() ?? '未知出版物';
    }
    final String goodsName = item['goodsName']?.toString() ?? '';
    final String sourceIdentifier = item['sourceIdentifier']?.toString() ?? '';
    return goodsName.isNotEmpty
        ? goodsName
        : (sourceIdentifier.isNotEmpty ? sourceIdentifier : '未知出版物');
  }

  /// 记录副标题：单个源时显示其所属整书名（如有）
  String _recordSubTitle(dynamic item) {
    final String buyType = item['orderBuyType']?.toString() ?? '';
    final String wholeName = item['wholePublicationName']?.toString() ?? '';
    if (buyType != 'WHOLE_PUBLICATION' && wholeName.isNotEmpty) {
      return wholeName;
    }
    return '共 ${_formatCount(item['sourceCount'])} 个源 · '
        '${_formatCount(item['resourceCount'])} 个资源';
  }

  /// 是否为非正常状态出版物（sell=false 或 goodsStatus≠1）
  bool _isAbnormal(dynamic item) {
    final bool sell = item['sell'] == true;
    final int goodsStatus =
        int.tryParse(item['goodsStatus']?.toString() ?? '1') ?? 1;
    return !sell || goodsStatus != 1;
  }

  /// 非正常状态文案：2/3=已被发布者删除，其余=已下架
  String _statusText(dynamic item) {
    final int goodsStatus =
        int.tryParse(item['goodsStatus']?.toString() ?? '1') ?? 1;
    if (goodsStatus == 2 || goodsStatus == 3) return '已删除';
    return '已下架';
  }

  String _formatPrice(dynamic price) {
    final double p = price is num
        ? price.toDouble()
        : double.tryParse(price?.toString() ?? '') ?? 0;
    if (p.isNaN || p < 0) return '0.00';
    return p.toStringAsFixed(2);
  }

  /// 数量展示：无值时显示 -
  String _formatCount(dynamic v) {
    if (v == null) return '-';
    return v.toString();
  }

  // ==================== 交互 ====================

  Future<void> _goLogin() async {
    await context.push('/login');
    if (!mounted) return;
    await _checkLoginAndLoad();
  }

  void _goHome() {
    context.go('/');
  }

  void _showTip(String content) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('温馨提示', style: TextStyle(fontSize: 16)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 点击购买记录：先校验出版物状态（下架/删除拦截），再按购买单位进入对应页面
  void _goResourcePlayer(dynamic item) {
    final int goodsStatus =
        int.tryParse(item['goodsStatus']?.toString() ?? '1') ?? 1;
    final bool sell = item['sell'] == true;
    if (goodsStatus == 0) {
      _showTip('出版物已下架');
      return;
    }
    if (goodsStatus == 2 || goodsStatus == 3) {
      _showTip('sorry，出版物已经被发布者删除了');
      return;
    }
    if (!sell) {
      _showTip('出版物已下架');
      return;
    }

    final String buyType = item['orderBuyType']?.toString() ?? '';
    if (buyType == 'WHOLE_PUBLICATION') {
      // 整书购买：进入链码列表页（源列表）
      context.push('/publication-source-list', extra: <String, dynamic>{
        'goodsId': item['goodsId']?.toString() ?? '',
        'goodsName': item['wholePublicationName']?.toString() ??
            item['goodsName']?.toString() ??
            '',
        'goodsImage': '',
        'serviceCode': item['serviceCode']?.toString() ?? '',
        'prefixCode': item['prefixCode']?.toString() ?? '',
        'versionCode': 1,
        'resourceFormats': <dynamic>[],
      });
      return;
    }

    // 单个源购买：按 ISLI 编码进入资源播放页
    final String isliCode = item['isliCode']?.toString() ?? '';
    if (isliCode.isEmpty) {
      EasyLoading.showToast('暂无链码信息');
      return;
    }
    context.push('/resource/play', extra: <String, dynamic>{
      'isliCode': isliCode.replaceAll('-', ''),
      'fromScan': false,
      'versionCode': '',
      'startIndex': 0,
    });
  }

  // ==================== UI ====================

  Widget _buildTag(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: textColor),
      ),
    );
  }

  Widget _buildRecordCard(dynamic item) {
    final String buyType = item['orderBuyType']?.toString() ?? '';
    final bool isWhole = buyType == 'WHOLE_PUBLICATION';
    final String iconPath = isWhole
        ? 'assets/icons/buy_type_book.png'
        : 'assets/icons/buy_type_source.png';
    final bool abnormal = _isAbnormal(item);

    // 非正常状态（下架/删除）：整行灰色弱化 + 标题中划线，与正常条目区分
    final Color titleColor =
        abnormal ? const Color(0xFFBFBFBF) : const Color(0xFF1A1A1A);
    final Color subColor =
        abnormal ? const Color(0xFFC8C8C8) : const Color(0xFF8C8C8C);
    final Color priceColor =
        abnormal ? const Color(0xFFBFBFBF) : const Color(0xFF2F7BFF);
    final TextDecoration? titleDecoration =
        abnormal ? TextDecoration.lineThrough : null;

    return GestureDetector(
      onTap: () => _goResourcePlayer(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 购买类型图标（非正常状态降低透明度，弱化视觉）
            Opacity(
              opacity: abnormal ? 0.4 : 1.0,
              child: Image.asset(iconPath, width: 24, height: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _recordTitle(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: titleColor,
                            height: 1.4,
                            decoration: titleDecoration,
                            decorationColor: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTag(
                        _buyTypeTag(buyType),
                        const Color(0xFF2F7BFF),
                        const Color(0xFFF0F5FF),
                      ),
                      if (abnormal) ...[
                        const SizedBox(width: 6),
                        _buildTag(
                          _statusText(item),
                          const Color(0xFFFF4D4F),
                          const Color(0xFFFFF1F0),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _recordSubTitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['payTime']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, color: subColor),
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '¥',
                              style: TextStyle(
                                fontSize: 11,
                                color: priceColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: _formatPrice(item['orderAmount']),
                              style: TextStyle(
                                fontSize: 16,
                                color: priceColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Opacity(
                opacity: abnormal ? 0.4 : 1.0,
                child: Image.asset(
                  'assets/icons/right_arrow.png',
                  width: 12,
                  height: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 未登录引导空态
  Widget _buildLoginEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 80, color: Color(0xFFBFBFBF)),
          const SizedBox(height: 16),
          const Text(
            '请先登录查看购买记录',
            style: TextStyle(
                fontSize: 15,
                color: Color(0xFF595959),
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            '登录后可查看已购买的付费资源',
            style: TextStyle(fontSize: 12, color: Color(0xFFBFBFBF)),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _goLogin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2F7BFF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                '去登录',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 空列表空态
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 80, color: Color(0xFFBFBFBF)),
          const SizedBox(height: 16),
          const Text(
            '暂无购买记录',
            style: TextStyle(
                fontSize: 15,
                color: Color(0xFF595959),
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            '去逛逛，发现精彩内容',
            style: TextStyle(fontSize: 12, color: Color(0xFFBFBFBF)),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _goHome,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2F7BFF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                '去浏览',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('购买记录', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        color: const Color(0xFFF5F7FA),
        child: !_isLoggedIn
            ? _buildLoginEmpty()
            : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? _buildEmpty()
                    : EasyRefresh(
                        controller: _refreshController,
                        onRefresh: () => _loadOrders(isRefresh: true),
                        onLoad: () => _loadOrders(isRefresh: false),
                        header: RefreshConfig.buildHeader(),
                        footer: RefreshConfig.buildFooter(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _list.length,
                          itemBuilder: (context, index) =>
                              _buildRecordCard(_list[index]),
                        ),
                      ),
      ),
    );
  }
}
