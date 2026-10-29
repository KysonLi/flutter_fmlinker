import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/models/prepay_product.dart';
import 'package:fmlink/services/iap_service.dart';
import 'package:fmlink/services/prepay_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/default_state_view.dart';

/// 我的账户（充值泛票）
///
/// 参照 iOS 客户端「我的账户」页还原：当前余额 → 充值档位 → 支付金额 → 确认支付 → 温馨提示，
/// 布局按 Flutter 端习惯重排，内容与功能保持一致。
///
/// 充值档位：`productId` 按平台写死在 `IapService`，由平台商店
/// （iOS StoreKit / 鸿蒙 IAP Kit）查询商品与本地化价格后再渲染。
///
/// - 余额：`GET /pos/v1/prepay/total_balance`（按平台独立账户，platform：iOS=1、鸿蒙=3）
/// - 充值：拉起平台内购（iOS StoreKit / 鸿蒙 IAP Kit）→ 支付凭证交服务端验证入账
///   （按平台分发，见 `PrepayService.verifyPurchase`：iOS `/pos/v1/prepay/prepay_ios_v2`、
///   鸿蒙 `/pos/v1/prepay/prepay_huawei`）→ 刷新余额；鸿蒙凭据先落本地，失败可补发
class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final PrepayService _prepayService = PrepayService();
  final UserService _userService = UserService();

  /// 充值档位（服务端下发，与 AGC / App Store 配置的商品一致）
  List<PrepayProduct> _products = <PrepayProduct>[];
  bool _loadingProducts = true;
  String? _productsError;

  double _balance = 0;
  bool _loadingBalance = true;
  int _selectedIndex = 0;

  /// 支付进行中：防止重复点击、重复拉起内购
  bool _paying = false;

  PrepayProduct? get _selected {
    if (_products.isEmpty || _selectedIndex >= _products.length) return null;
    return _products[_selectedIndex];
  }

  @override
  void initState() {
    super.initState();
    // 先补发「已付款未入账」的华为订单（本地暂存 + 华为侧未完成订单，防丢单），再拉数据
    _recoverPending();
    _loadBalance();
    _loadProducts();
  }

  /// 进入页面即检查并补验证未入账的华为订单
  ///
  /// 覆盖：上次验证失败留下的本地凭据、以及华为侧「已支付未发货」的订单
  /// （本地没存下记录也能找回）。补发成功后刷新余额并提示。
  Future<void> _recoverPending() async {
    try {
      final int recovered = await _prepayService.recoverHuaweiPurchases();
      if (!mounted || recovered <= 0) return;
      EasyLoading.showToast('已补发 $recovered 笔充值到账');
      await _loadBalance();
    } catch (e) {
      print('补发华为充值凭据失败: $e');
    }
  }

  // ==================== 数据 ====================

  Future<void> _loadBalance() async {
    try {
      // 冷启动 / 长时间闲置后 Constants.token 可能为空，先重新水合
      await _userService.refreshToken();
      final String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        if (mounted) setState(() => _loadingBalance = false);
        return;
      }

      // 余额接口按 unification_id + platform 查询（platform：iOS=1，鸿蒙=3）
      final Map<String, dynamic> response =
          await _prepayService.getTotalBalance(unificationId);
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

  /// 余额取值：服务端返回 `data.total_amount`（iOS 端一致），同时兼容多种 key，取不到按 0 处理
  double _parseBalance(dynamic data) {
    if (data is num) return data.toDouble();
    if (data is String) return double.tryParse(data) ?? 0;
    if (data is Map) {
      const List<String> keys = <String>[
        'total_amount',
        'totalAmount',
        'totalBalance',
        'balance',
        'total_balance',
        'availableBalance',
        'available_balance',
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

  /// 拉取充值档位：productId 写死在 `IapService`，商品与价格以平台商店查询结果为准
  /// （iOS：StoreKit；鸿蒙：IAP Kit）
  Future<void> _loadProducts() async {
    setState(() {
      _loadingProducts = true;
      _productsError = null;
    });

    final Map<String, dynamic> response = await IapService.queryProducts();
    print('充值档位(商店): $response');

    if (!mounted) return;
    if (response['status'] == true && response['data'] is List<PrepayProduct>) {
      final List<PrepayProduct> products =
          response['data'] as List<PrepayProduct>;
      setState(() {
        _products = products;
        _loadingProducts = false;
        if (_selectedIndex >= products.length) _selectedIndex = 0;
      });
    } else {
      setState(() {
        _loadingProducts = false;
        _productsError = response['msg']?.toString() ?? '获取充值档位失败';
      });
    }
  }

  // ==================== 交互 ====================

  void _openRechargeRecord() {
    context.push('/profile/recharge-record');
  }

  /// 确认支付：拉起平台内购 → 服务端验证入账 → 刷新余额
  ///
  /// 1. 登录校验（`unification_id` 是充值入账的账号标识）；
  /// 2. 拉起平台内购（iOS StoreKit / 鸿蒙 IAP Kit）；
  /// 3. 拿支付凭证调充值验证接口（按平台分发，见 `PrepayService.verifyPurchase`：
  ///    iOS `/pos/v1/prepay/prepay_ios_v2`、鸿蒙 `/pos/v1/prepay/prepay_huawei`）；
  ///    鸿蒙的凭据会先落本地，失败可重试时留待补发（防丢单）；
  /// 4. 订单发货确认由**服务端**完成（对接文档流程 ⑦），客户端不再调 IAP 的 finishPurchase；
  /// 5. 刷新余额。
  Future<void> _handlePay() async {
    final PrepayProduct? product = _selected;
    if (product == null) {
      EasyLoading.showToast('请选择充值档位');
      return;
    }
    if (_paying) return;

    setState(() => _paying = true);
    EasyLoading.show(status: '正在唤起支付...');
    try {
      // 1. 登录校验（冷启动 / 长时间闲置后 Constants.token 可能为空，先重新水合）
      await _userService.refreshToken();
      final String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        EasyLoading.dismiss();
        EasyLoading.showToast('请先登录');
        if (mounted) await context.push('/login');
        return;
      }

      // 2. 拉起平台内购（用户在系统面板取消时不会抛异常，只返回失败 + canceled）
      final Map<String, dynamic> purchase =
          await IapService.purchase(product.productId);
      print('内购结果: $purchase');
      if (purchase['status'] != true) {
        EasyLoading.dismiss();
        if (purchase['canceled'] == true) {
          EasyLoading.showToast('已取消充值');
          return;
        }
        // 华为侧说该商品「已拥有」：说明还有已付款未发货的订单（常见于上次入账失败），
        // 这里深查（含全部已购订单）并重新提交验证，而不是让用户重复购买
        if (purchase['code'] == IapService.codeAlreadyOwned) {
          EasyLoading.show(status: '正在核对已付款订单...');
          final int recovered =
              await _prepayService.recoverHuaweiPurchases(deep: true);
          EasyLoading.dismiss();
          if (recovered > 0) {
            EasyLoading.showSuccess('已补发 $recovered 笔充值到账');
            await _loadBalance();
          } else {
            EasyLoading.showToast('该档位有未完成订单，请稍后在充值记录中查看');
          }
          return;
        }
        EasyLoading.showError(purchase['msg']?.toString() ?? '充值失败，请稍后重试');
        return;
      }

      final Map<String, dynamic> data =
          (purchase['data'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      final String purchaseToken = data['purchaseToken']?.toString() ?? '';
      final String purchaseOrderId = data['purchaseOrderId']?.toString() ?? '';
      final String receipt = data['receipt']?.toString() ?? '';
      final String transactionId = data['transactionId']?.toString() ?? '';

      // 3. 服务端验证 + 入账（鸿蒙 /pos/v1/prepay/prepay_huawei，iOS /pos/v1/prepay/prepay_ios_v2）
      EasyLoading.show(status: '正在确认充值结果...');
      final Map<String, dynamic> verify = await _prepayService.verifyPurchase(
        unificationId: unificationId,
        receipt: receipt,
        transactionId: transactionId,
        purchaseToken: purchaseToken,
        purchaseOrderId: purchaseOrderId,
      );
      print('充值验证结果: $verify');

      // 00000000 = 成功；88888822 = 华为幂等命中（重复提交），同样算成功
      if (PrepayService.isVerifySuccess(verify['resultCode'])) {
        EasyLoading.dismiss();
        EasyLoading.showSuccess('充值成功');
        await _loadBalance();
        return;
      }

      // 已支付但未入账：
      // - 可重试（88888821 / 88888823 / 01111111 / 网络异常）：凭据已暂存，下次进入自动补发
      // - 不可重试（88888824 商品不存在 / 88888825 订单状态非法 / POS-000600021 参数错误）：直接提示
      EasyLoading.dismiss();
      if (verify['retryable'] == true) {
        EasyLoading.showToast('充值结果确认中，稍后将自动补发到账');
        await _loadBalance();
      } else {
        EasyLoading.showError(verify['msg']?.toString() ?? '充值失败，请稍后在充值记录中查看');
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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
    final PrepayProduct product = _products[index];
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
              product.titleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: selected ? accent : const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.priceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  /// 档位区：加载中 / 失败 / 空 / 网格
  Widget _buildProductsArea() {
    if (_loadingProducts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      if (_productsError != null && _productsError!.isNotEmpty) {
        return DefaultStateView.loadFailed(
          text: _productsError,
          onRetry: _loadProducts,
          compact: true,
        );
      }
      return DefaultStateView.empty(
        text: '暂无充值档位',
        onRetry: _loadProducts,
        retryText: '重新加载',
        compact: true,
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
      ),
      itemBuilder: (context, index) => _buildOptionTile(index),
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
          _buildProductsArea(),
          if (_selected != null) ...<Widget>[
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                const Text(
                  '支付金额：',
                  style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                ),
                Text(
                  '${PrepayProduct.formatNum(_selected!.price)}元',
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
              onTap: _paying ? null : _handlePay,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _paying
                      ? const Color(0xFFA8C7EE)
                      : const Color(0xFF2376E3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _paying ? '支付中...' : '确认支付',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
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
