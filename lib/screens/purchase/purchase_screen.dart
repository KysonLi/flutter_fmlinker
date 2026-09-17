import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/common/isli_constants.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';

/// 购买页
///
/// 参考微信小程序端已实现的购买页（`_template_....txt` 中的 purchase 页），
/// 复刻其展示结构：出版物卡片（封面+名称+链码）+ 定价卡片（免费/单个源/整书）
/// + 支付方式卡片 + 购买说明 + 底部合计与确认按钮。
///
/// 传入参数（`PurchaseScreen.params`）与小程序购买页 onLoad options 保持一致：
/// goodsId / shopId / serviceCode / prefixCode / pricingStrategy / versionCode /
/// sourceIdentifier / article / chapter / groupName / chapterName / price /
/// goodsName / cover(goodsImage) / sourceId / sourceName / totalPrice /
/// benefitPrice / isBenefit / sourcePrice / sourceFree / sourcePay。
///
/// 进入页面后调用 fetchDeratePrice 拉取「已购源减免金额」与「出版物标识」，
/// 减免金额（deratePrice）会从整书价中扣除。
///
/// 价格策略说明（PricingStrategy，见 common/isli_constants.dart）：
/// - CHAIN_ALL_FREE：资源全部免费，无需购买
/// - CHAIN_UNIFORM_PRICE：整书一口价，只支持整书购买
/// - 其余策略：按源/分组/按章定价，均展示「单个源购买」与「整书购买」两个选项
class PurchaseScreen extends StatefulWidget {
  final Map<String, dynamic> params;

  const PurchaseScreen({super.key, required this.params});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

/// 购买类型：单个源 / 整书
const String _typeSingle = 'single';
const String _typeWhole = 'whole';

class _PurchaseScreenState extends State<PurchaseScreen> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();

  /// 当前选中的购买类型
  String _purchaseType = _typeWhole;

  /// 已购源减免金额（fetchDeratePrice 返回 deratePrice）：整书购买时从整书价扣除
  double _deratePrice = 0;

  /// 出版物标识（fetchDeratePrice 返回 identifier）：生成支付订单时传 goods_identifier
  // ignore: unused_field
  String _goodsIdentifier = '';

  /// 是否正在支付
  bool _paying = false;

  Map<String, dynamic> get _p => widget.params;

  @override
  void initState() {
    super.initState();
    // 默认购买类型：整书一口价或无单源选项时默认整书；单源已解锁（免费/已购）时也默认整书
    _purchaseType =
        (!showSingleOption || singleAlreadyUnlocked) ? _typeWhole : _typeSingle;
    _loadDerate();
  }

  // ==================== 参数读取辅助 ====================

  String _str(String key) {
    final dynamic v = _p[key];
    return (v == null ? '' : v.toString()).trim();
  }

  /// 无效值统一视为 0
  double _price(String key) {
    final dynamic v = _p[key];
    if (v == null) return 0;
    final double n =
        v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return (n.isNaN || n < 0) ? 0 : n;
  }

  /// 'true'/'false'、true/false、1/0 兼容
  bool _flag(String key) {
    final dynamic v = _p[key];
    if (v == null) return false;
    if (v is bool) return v;
    final String s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  String _fixed(double v) => v.toStringAsFixed(2);

  // ==================== 页面状态 ====================

  /// 免费策略：CHAIN_ALL_FREE 资源全部免费，无需购买
  bool get isFreeStrategy => _str('pricingStrategy') == PricingStrategy.allFree;

  /// 整体一口价策略：只支持整书购买
  bool get isUniformStrategy =>
      _str('pricingStrategy') == PricingStrategy.uniformPrice;

  /// 当前源是否免费（source.free）
  bool get sourceFree => _flag('sourceFree');

  /// 当前源是否已购买（source.pay）
  bool get sourcePaid => _flag('sourcePay');

  /// 单个源是否已解锁（免费或已购）
  bool get singleAlreadyUnlocked => sourceFree || sourcePaid;

  /// 是否展示「单个源购买」选项：除免费/整书一口价策略外都有该选项
  bool get showSingleOption => !isFreeStrategy && !isUniformStrategy;

  /// 是否启用整书优惠：仅 isBenefit=true 且优惠价有效时生效
  bool get isBenefitActive => _flag('isBenefit') && _price('benefitPrice') > 0;

  /// 整书价（减免前）：isBenefit=true 时用优惠价，否则用原价 totalPrice；不含 deratePrice 减免
  double get baseWholePrice {
    if (isBenefitActive) return _price('benefitPrice');
    double total = _price('totalPrice');
    if (total <= 0) total = _price('price');
    return total;
  }

  /// 整书实付价：减免前整书价再减去已购源减免（最低为 0）
  double get wholePrice {
    double price = baseWholePrice;
    if (_deratePrice > 0) {
      price -= _deratePrice;
      if (price < 0) price = 0;
    }
    return price;
  }

  /// 单个源价格：source.price 兜底 price
  double get singlePrice {
    double p = _price('sourcePrice');
    if (p <= 0) p = _price('price');
    return p;
  }

  double get totalPrice => _price('totalPrice');

  /// 实付金额
  String get displayPrice {
    if (isFreeStrategy) return '0.00';
    if (_purchaseType == _typeWhole) return _fixed(wholePrice);
    return _fixed(singlePrice);
  }

  /// 链码展示：serviceCode-prefixCode
  String get chainLabel {
    final List<String> parts = <String>[];
    if (_str('serviceCode').isNotEmpty) parts.add(_str('serviceCode'));
    if (_str('prefixCode').isNotEmpty) parts.add(_str('prefixCode'));
    return parts.join('-').isNotEmpty ? parts.join('-') : '未关联';
  }

  /// 定价策略标签
  String get pricingLabel {
    switch (_str('pricingStrategy')) {
      case PricingStrategy.allFree:
        return '免费内容';
      case PricingStrategy.uniformPrice:
        return '整体定价';
      case PricingStrategy.sourceSamePrice:
        return '按链码相同定价';
      case PricingStrategy.groupFreedomPrice:
        return '分组定价';
      case PricingStrategy.chapterPrice:
        return '按章定价';
      default:
        return '按源分别定价';
    }
  }

  bool get canPay =>
      !_paying &&
      (_str('goodsId').isNotEmpty || _str('serviceCode').isNotEmpty);

  void _selectType(String type) {
    if (type == _typeSingle && (isUniformStrategy || singleAlreadyUnlocked)) {
      return;
    }
    setState(() => _purchaseType = type);
  }

  // ==================== 数据加载 ====================

  /// 拉取已购源减免金额：deratePrice（整书减免）+ identifier（下单用 goods_identifier）
  Future<void> _loadDerate() async {
    final String goodsId = _str('goodsId');
    if (goodsId.isEmpty) return;

    try {
      await _userService.refreshToken();
      String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        unificationId = await DeviceInfoUtil.getDeviceId();
      }

      final Map<String, dynamic> response =
          await _publishService.fetchDeratePrice(
        unificationId,
        goodsId,
        versionCode: int.tryParse(_str('versionCode')),
        sourceIdentifier: _str('sourceIdentifier'),
      );

      if (response['status'] && response['data'] != null) {
        final dynamic data = response['data'];
        if (data is Map) {
          setState(() {
            _deratePrice = _priceOf(data['deratePrice']);
            _goodsIdentifier = (data['identifier'] ?? '').toString();
          });
        }
      }
    } catch (e) {
      print('获取减免金额失败: $e');
    }
  }

  double _priceOf(dynamic v) {
    if (v == null) return 0;
    final double n =
        v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return (n.isNaN || n < 0) ? 0 : n;
  }

  // ==================== 确认购买 ====================

  Future<void> _handleConfirmPay() async {
    if (!canPay) return;

    // 只有「需要付费购买」时才提示登录
    if (!isFreeStrategy) {
      final bool loggedIn = await _userService.checkLoginStatus();
      if (!loggedIn) {
        if (!mounted) return;
        await context.push('/login');
        if (!mounted) return;
        final bool loggedAfter = await _userService.checkLoginStatus();
        if (!loggedAfter) return;
      }
    }

    if (isFreeStrategy) {
      // 免费内容：无需支付，直接完成
      _completePurchase('获取成功');
      return;
    }

    // 付费内容：拉取微信支付参数并拉起 fluwx 支付
    setState(() => _paying = true);
    try {
      await _startWechatPay();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// 发起微信支付（fluwx 真实支付）。
  ///
  /// 接入步骤（待后端下单接口确认后补齐）：
  /// 1. 调用下单接口（对应小程序端 createPayOrder）获取微信支付参数；
  ///    入参预计含：unification_id、goods_id、shop_id、source_id
  ///    （整书=WHOLE_PUBLICATION / 单源=sourceIdentifier）、goods_identifier。
  /// 2. 通过 fluwx.payWithWeChat 拉起支付：
  ///    fluwx.payWithWeChat(appId/partnerId/prepayId/packageValue/nonceStr/timeStamp/sign)。
  /// 3. 支付结果监听 fluwx.weChatResponseEventHandler，errCode == 0 视为成功，
  ///    成功后再调用 _completePurchase('支付成功') 收尾。
  Future<void> _startWechatPay() async {
    // TODO(支付接入): 仍被后端接口阻塞。已核对仓库内全部接口文档
    // （泛媒关联APP接口文档.md 等），只有旧的 chain-server 充值/购买接口
    // （/chain-server/api/link_code_system/pay，入参 user_id/goodsId/amount/pay_type），
    // 没有小程序端 createPayOrder 对应的下单接口（unification_id/goods_id/shop_id/
    // source_id/goods_identifier）与 prepayId 等微信支付参数，无法安全实现。
    // 拿到真实下单接口后，按上方 _startWechatPay 注释的三步替换此处占位。
    EasyLoading.showToast('微信支付接入中，暂未开通');
  }

  /// 购买完成后的收尾：提示 → 延时返回上一页（返回 true 便于上游刷新购买状态）
  void _completePurchase(String toastTitle) {
    EasyLoading.showToast(toastTitle,
        duration: const Duration(milliseconds: 2000));
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pop(true);
    });
  }

  // ==================== UI ====================

  String get _coverUrl {
    final String cover = _str('cover');
    if (cover.isNotEmpty) return cover;
    return _str('goodsImage');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('购买', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          _buildPublicationCard(),
          _buildPricingCard(),
          _buildPayCard(),
          _buildNoticeCard(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ---------- 出版物卡片 ----------

  Widget _buildPublicationCard() {
    final String name =
        _str('goodsName').isNotEmpty ? _str('goodsName') : '未知出版物';
    final String cover = _coverUrl;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: cover.isNotEmpty
                ? Image.network(
                    cover,
                    width: 80,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _defaultCover(),
                  )
                : _defaultCover(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '链码：',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
                    ),
                    Expanded(
                      child: Text(
                        chainLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF595959),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultCover() {
    return Image.asset(
      'assets/images/default_cover.png',
      width: 80,
      height: 100,
      fit: BoxFit.cover,
    );
  }

  // ---------- 定价卡片 ----------

  Widget _buildPricingCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: isFreeStrategy ? _buildFreeContent() : _buildPaidContent(),
    );
  }

  Widget _buildFreeContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF52C41A), Color(0xFF73D13D)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            '免费',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '该出版物资源全部免费，无需购买',
          style: TextStyle(fontSize: 13, color: Color(0xFF8C8C8C)),
        ),
      ],
    );
  }

  Widget _buildPaidContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 定价策略标签 + 来源名
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pricingLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF2F7BFF)),
              ),
            ),
            if (_str('sourceName').isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _str('sourceName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
                ),
              ),
            ],
          ],
        ),
        // 单个源购买
        if (showSingleOption) ...[
          const SizedBox(height: 10),
          _buildOptionItem(
            type: _typeSingle,
            title: '单个源购买',
            tag: singleAlreadyUnlocked
                ? const _Tag(
                    text: '已解锁',
                    color: Color(0xFF52C41A),
                    bg: Color(0xFFF6FFED),
                    border: Color(0xFFB7EB8F),
                  )
                : null,
            desc: '购买后可查看当前链码关联的一个或多个资源',
            price: _fixed(singlePrice),
            selected: _purchaseType == _typeSingle,
            onTap: () => _selectType(_typeSingle),
            children: <Widget>[],
          ),
        ],
        // 整书购买
        const SizedBox(height: 10),
        _buildOptionItem(
          type: _typeWhole,
          title: '整书购买',
          tag: isBenefitActive
              ? const _Tag(
                  text: '优惠',
                  color: Color(0xFFFF4D4F),
                  bg: Color(0xFFFFF1F0),
                  border: Color(0xFFFFA39E))
              : null,
          desc: '注：购买过[单个源]，再购买[整书源]将减免部分费用',
          price: _fixed(wholePrice),
          selected: _purchaseType == _typeWhole,
          onTap: () => _selectType(_typeWhole),
          children: <Widget>[
            if (isBenefitActive)
              Row(
                children: [
                  const Text('原价 ',
                      style: TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                  Text(
                    '¥$_fixedTotalPrice',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBFBFBF),
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '¥${_fixed(baseWholePrice)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52C41A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            if (_deratePrice > 0)
              Row(
                children: [
                  const Text('减免 ',
                      style: TextStyle(fontSize: 11, color: Color(0xFFFF4D4F))),
                  Text(
                    '-¥${_fixed(_deratePrice)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF4D4F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String get _fixedTotalPrice => _fixed(totalPrice);

  /// 单个定价选项行
  Widget _buildOptionItem({
    required String type,
    required String title,
    required String desc,
    required String price,
    required bool selected,
    required VoidCallback onTap,
    _Tag? tag,
    List<Widget> children = const <Widget>[],
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0F5FF) : const Color(0xFFFAFAFA),
          border: Border.all(
            color: selected ? const Color(0xFF2F7BFF) : Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        tag,
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C8C8C),
                      height: 1.5,
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _priceText(price),
                const SizedBox(height: 8),
                _radio(checked: selected),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceText(String price) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text(
          '¥',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF2F7BFF),
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          price,
          style: const TextStyle(
            fontSize: 20,
            color: Color(0xFF2F7BFF),
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }

  Widget _radio({required bool checked}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: checked ? const Color(0xFF2F7BFF) : const Color(0xFFD9D9D9),
          width: 1.5,
        ),
      ),
      child: checked
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2F7BFF),
                ),
              ),
            )
          : null,
    );
  }

  // ---------- 支付方式卡片 ----------

  Widget _buildPayCard() {
    // 支付通道已确定为 fluwx（微信支付），固定选中微信支付
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择支付方式',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FF),
              border: Border.all(color: const Color(0xFF2F7BFF), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF07C160),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '微',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '微信支付',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '推荐使用微信支付',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                      ),
                    ],
                  ),
                ),
                _radio(checked: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 购买说明卡片 ----------

  Widget _buildNoticeCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '购买说明',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          _buildNoticeItem(
            index: '1',
            text: '源是每个链码所标识的内容，通过链码建立源与资源的关联关系。',
          ),
          _buildNoticeItem(
            index: '2',
            textSpanChildren: const <InlineSpan>[
              TextSpan(
                  text: '链码关联的资源由出版社或内容提供者进行维护，维护过程中可能会出现资源数量增加或精减的情况，如有疑问，请'),
              TextSpan(
                text: '[我的-意见反馈]',
                style: TextStyle(color: Color(0xFF2F7BFF)),
              ),
              TextSpan(text: '里进行反馈。'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeItem(
      {required String index,
      String? text,
      List<InlineSpan>? textSpanChildren}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2F7BFF),
            ),
            alignment: Alignment.center,
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: textSpanChildren != null
                ? Text.rich(
                    TextSpan(children: textSpanChildren),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF595959),
                      height: 1.6,
                    ),
                  )
                : Text(
                    text ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF595959),
                      height: 1.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- 底部合计栏 ----------

  Widget _buildBottomBar() {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  '合计：',
                  style: TextStyle(fontSize: 13, color: Color(0xFF595959)),
                ),
                const Text(
                  '¥',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2F7BFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  displayPrice,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Color(0xFF2F7BFF),
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: canPay ? _handleConfirmPay : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 140,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (!canPay || _paying)
                    ? const Color(0xFFB8D4FF)
                    : const Color(0xFF2F7BFF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                _paying ? '订单创建中' : (isFreeStrategy ? '确认获取' : '确认支付'),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 选项行小标签（如「已解锁」「优惠」）
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  final Color border;

  const _Tag({
    required this.text,
    required this.color,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}
