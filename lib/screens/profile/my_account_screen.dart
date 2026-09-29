import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';

/// 充值档位（与 iOS 客户端一致：1 元 = 1 泛票，故售价金额与泛票数同值）
class _RechargeOption {
  const _RechargeOption(this.tickets);

  /// 泛票数量
  final int tickets;

  /// 售价（元）
  int get price => tickets;
}

/// 我的账户（充值泛票）
///
/// 参照 iOS 客户端「我的账户」页还原：当前余额 → 充值档位 → 支付金额 → 确认支付 → 温馨提示，
/// 布局按 Flutter 端习惯重排，内容与功能保持一致。
///
/// - 余额：`GET /chain-server/api/link_code_system/prepay/total_balance`（参数 `user_id`）
/// - 充值下单（待接入）：iOS 用 `/chain-server/api/link_code_system/prepay/prepay_ios_v2`
/// - 支付通道：iOS 走 App Store 内购（StoreKit）、鸿蒙走华为 IAP Kit，
///   目前均为占位（同 `purchase_screen` 的 `_startIapCoinPay`），接入后再打通并刷新余额
class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  /// 充值档位（与 iOS 客户端页面上的 6/18/30/50/98/188 一致）
  static const List<_RechargeOption> _options = <_RechargeOption>[
    _RechargeOption(6),
    _RechargeOption(18),
    _RechargeOption(30),
    _RechargeOption(50),
    _RechargeOption(98),
    _RechargeOption(188),
  ];

  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();

  double _balance = 0;
  bool _loadingBalance = true;
  int _selectedIndex = 0;

  _RechargeOption get _selected => _options[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  // ==================== 数据 ====================

  Future<void> _loadBalance() async {
    try {
      // 冷启动 / 长时间闲置后 Constants.token 可能为空，先重新水合
      await _userService.refreshToken();
      final String userId = await _userService.getUnificationId();
      if (userId.isEmpty) {
        if (mounted) setState(() => _loadingBalance = false);
        return;
      }

      final Map<String, dynamic> response = await _apiService.get(
        '/chain-server/api/link_code_system/prepay/total_balance',
        queryParameters: {'user_id': userId},
      );
      print('余额查询结果: $response');

      if (!mounted) return;
      setState(() {
        _loadingBalance = false;
        if (response['status'] == true) {
          _balance = _parseBalance(response['data']);
        }
      });
    } catch (e) {
      print('余额查询失败: $e');
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  /// 余额取值：字段名未最终确认，兼容「直接返回数字」与多种 key，取不到按 0 处理
  double _parseBalance(dynamic data) {
    if (data is num) return data.toDouble();
    if (data is String) return double.tryParse(data) ?? 0;
    if (data is Map) {
      const List<String> keys = <String>[
        'totalBalance',
        'balance',
        'total_balance',
        'availableBalance',
        'available_balance',
        'totalAmount',
        'amount',
        'money',
      ];
      for (final String key in keys) {
        final dynamic value = data[key];
        if (value is num) return value.toDouble();
        final double? parsed = double.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  // ==================== 交互 ====================

  void _openRechargeRecord() {
    context.push('/profile/recharge-record');
  }

  /// 确认支付（占位）
  ///
  /// 接入后流程：调充值下单接口（iOS `/prepay/prepay_ios_v2`）→ 拉起平台内购
  /// （iOS StoreKit / 鸿蒙 IAP Kit）→ 服务端记账成功 → 重新拉取余额。
  void _handlePay() {
    EasyLoading.showToast('充值功能开发中，敬请期待');
  }

  /// 底部规则文案：iOS 与鸿蒙的充值渠道不同，需分别适配
  List<String> get _tipLines {
    if (Platform.isOhos) {
      return const <String>[
        '1.泛票充值规则：1元=1泛票；',
        '2.鸿蒙设备上充值的泛票不能在其他平台的设备上进行使用；',
        '3.通过华为应用市场充值时泛票将记入当前账号。',
      ];
    }
    if (Platform.isIOS) {
      return const <String>[
        '1.泛票充值规则：1元=1泛票；',
        '2.苹果设备上充值的泛票不能在其他平台的设备上进行使用；',
        '3.通过AppStore充值泛票时可绑定不同支付方式。',
      ];
    }
    // Android 暂无该页入口，兜底用与平台无关的文案
    return const <String>[
      '1.泛票充值规则：1元=1泛票；',
      '2.当前设备上充值的泛票不能在其他平台的设备上进行使用；',
      '3.充值结果以服务端账单为准。',
    ];
  }

  // ==================== UI ====================

  /// 余额图标：蓝色票券 + 白色 ¥（参照 iOS 页面的票券图形，纯代码绘制，不新增素材）
  Widget _buildTicketIcon() {
    return SizedBox(
      width: 60,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 60,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF29A3F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(Icons.currency_yuan, color: Colors.white, size: 22),
            ),
          ),
          // 左右半圆缺口（与卡片白底同色），做出票券锯齿效果
          Positioned(left: -7, child: _buildNotch()),
          Positioned(right: -7, child: _buildNotch()),
        ],
      ),
    );
  }

  Widget _buildNotch() {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: <Widget>[
          _buildTicketIcon(),
          const SizedBox(height: 14),
          Text(
            _loadingBalance ? '--' : _balance.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '当前余额',
            style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(int index) {
    final _RechargeOption option = _options[index];
    final bool selected = index == _selectedIndex;
    const Color accent = Color(0xFF2376E3);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF2F8FF) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? accent : const Color(0xFFEEEEEE),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${option.tickets}泛票',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: selected ? accent : const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '售价${option.price}元',
              style: TextStyle(
                fontSize: 12,
                color: selected ? accent : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRechargeSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '充值泛票',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _options.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
            ),
            itemBuilder: (context, index) => _buildOptionTile(index),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Text(
                '支付金额：',
                style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
              Text(
                '${_selected.price}元',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2376E3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handlePay,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2376E3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '确认支付',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '温馨提示：',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          for (final String line in _tipLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF999999),
                  height: 1.6,
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('我的账户', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _openRechargeRecord,
            child: const Text(
              '充值记录',
              style: TextStyle(fontSize: 13, color: Color(0xFF333333)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _buildBalanceCard(),
          _buildRechargeSection(),
          _buildTips(),
        ],
      ),
    );
  }
}
