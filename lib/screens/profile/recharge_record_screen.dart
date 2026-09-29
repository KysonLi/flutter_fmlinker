import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:fmlink/widgets/default_state_view.dart';

/// 充值记录页
///
/// 数据接口：GET /chain-server/api/link_code_system/prepay/prepay_record
/// 参数：user_id（登录后的 unificationId）、page、page_size
///
/// ⚠️ 该接口的返回字段名客户端尚未确认（文档只写了「充值ID、金额、时间、状态」），
/// 取值一律做多命名兼容；联调时看 `print('充值记录: ...')` 的原始返回，确认后收敛。
class RechargeRecordScreen extends StatefulWidget {
  const RechargeRecordScreen({super.key});

  @override
  State<RechargeRecordScreen> createState() => _RechargeRecordScreenState();
}

class _RechargeRecordScreenState extends State<RechargeRecordScreen> {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  static const int _pageSize = 20;

  List<dynamic> _list = <dynamic>[];
  int _pageIndex = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _isLoggedIn = false;

  /// 加载失败原因（为空表示未失败），用于展示统一失败占位
  String? _error;

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

  /// 检查登录态：未登录显示登录引导空态，已登录拉取充值记录
  Future<void> _checkLoginAndLoad() async {
    final bool loggedIn = await _userService.checkLoginStatus();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
    if (loggedIn) {
      await _loadRecords(isRefresh: true);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecords({bool isRefresh = false}) async {
    if (!isRefresh && (!_hasMore || _loadingMore)) {
      _refreshController.finishLoad(IndicatorResult.noMore);
      return;
    }
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
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

      final Map<String, dynamic> response = await _apiService.get(
        '/chain-server/api/link_code_system/prepay/prepay_record',
        queryParameters: <String, dynamic>{
          'user_id': userId,
          'page': isRefresh ? 1 : _pageIndex,
          'page_size': _pageSize,
        },
      );
      print('充值记录: $response');

      if (!mounted) return;
      if (response['status'] == true && response['data'] != null) {
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
      } else {
        _error = response['msg']?.toString() ?? '';
      }
    } catch (e) {
      if (mounted) {
        final String msg = ErrorHandler().fromError(e, fallback: '获取充值记录失败');
        _error = msg;
        EasyLoading.showError(msg);
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

  /// 兼容接口返回数组或 {list/records/rows: [...]} 多种结构
  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final String key in const <String>['list', 'records', 'rows']) {
        final dynamic value = data[key];
        if (value is List) return value;
      }
    }
    return <dynamic>[];
  }

  // ==================== 展示辅助（字段名做多命名兼容） ====================

  String _pickStr(dynamic item, List<String> keys) {
    if (item is! Map) return '';
    for (final String key in keys) {
      final dynamic value = item[key];
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  num _pickNum(dynamic item, List<String> keys) {
    if (item is! Map) return 0;
    for (final String key in keys) {
      final dynamic value = item[key];
      if (value is num) return value;
      final num? parsed = num.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  /// 泛票数：接口若单独返回数量用它，否则按 1元=1泛票 用金额兜底
  num _tickets(dynamic item) {
    final num num0 = _pickNum(item, const <String>[
      'num',
      'ticketNum',
      'fanPiaoNum',
      'coinNum',
      'count',
      'quantity',
      'prepayNum',
    ]);
    if (num0 != 0) return num0;
    return _amount(item);
  }

  /// 充值金额（元）
  num _amount(dynamic item) {
    return _pickNum(item, const <String>[
      'amount',
      'money',
      'price',
      'payAmount',
      'totalAmount',
      'prepayAmount',
      'rechargeAmount',
    ]);
  }

  /// 数量展示：整数不显示小数位
  String _formatNum(num value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }

  String _timeText(dynamic item) {
    return _pickStr(item, const <String>[
      'createTime',
      'create_time',
      'createDate',
      'payTime',
      'pay_time',
      'orderTime',
      'updateTime',
      'time',
    ]);
  }

  String _titleText(dynamic item) {
    return _pickStr(item, const <String>[
      'productName',
      'goodsName',
      'remark',
      'title',
      'productId',
    ]);
  }

  /// 状态文案：字段名与取值未确认，常见值做映射，其余原样展示
  String _statusText(dynamic item) {
    final String raw = _pickStr(item, const <String>[
      'status',
      'state',
      'orderStatus',
      'payStatus',
      'tradeStatus',
    ]);
    switch (raw.toUpperCase()) {
      case '1':
      case 'SUCCESS':
      case 'TRADE_SUCCESS':
      case 'PAID':
      case '已支付':
      case '充值成功':
        return '充值成功';
      case '0':
      case 'WAIT':
      case 'WAIT_BUYER_PAY':
      case '待支付':
        return '待支付';
      case '2':
      case 'CANCEL':
      case 'CANCELED':
      case '已取消':
        return '已取消';
      case '3':
      case 'FAIL':
      case 'FAILED':
      case '充值失败':
        return '充值失败';
    }
    // 未知状态原样返回（英文/数字过长时交给 ErrorHandler 判断可否展示）
    return ErrorHandler().isDisplayable(raw) ? raw : '';
  }

  // ==================== 交互 ====================

  Future<void> _goLogin() async {
    await context.push('/login');
    if (!mounted) return;
    await _checkLoginAndLoad();
  }

  // ==================== UI ====================

  Widget _buildRecordCard(dynamic item) {
    final String title = _titleText(item);
    final String time = _timeText(item);
    final String status = _statusText(item);
    final num tickets = _tickets(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.currency_yuan,
              size: 18,
              color: Color(0xFF2376E3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.isEmpty ? '充值泛票' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  time.isEmpty ? '-' : time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8C8C8C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '+${_formatNum(tickets)}泛票',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2F7BFF),
                ),
              ),
              if (status.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 未登录引导空态
  Widget _buildLoginEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 80, color: Color(0xFFBFBFBF)),
          const SizedBox(height: 16),
          const Text(
            '请先登录查看充值记录',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF595959),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '登录后可查看泛票充值明细',
            style: TextStyle(fontSize: 12, color: Color(0xFFBFBFBF)),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
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
                  fontWeight: FontWeight.w500,
                ),
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
        title: const Text('充值记录', style: TextStyle(fontSize: 14)),
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
                : _error != null && _list.isEmpty
                    ? DefaultStateView.fromError(
                        message: _error,
                        onRetry: () => _loadRecords(isRefresh: true),
                      )
                    : _list.isEmpty
                        ? DefaultStateView.empty(
                            text: '暂无充值记录',
                            subText: '充值泛票后可在此查看明细',
                          )
                        : EasyRefresh(
                            controller: _refreshController,
                            onRefresh: () => _loadRecords(isRefresh: true),
                            onLoad: () => _loadRecords(isRefresh: false),
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
