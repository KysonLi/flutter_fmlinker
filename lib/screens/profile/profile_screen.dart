import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fmlink/services/user_service.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  final ScrollController _scrollController = ScrollController();
  final UserService _userService = UserService();

  bool _isLoggedIn = false;
  String _avatarUrl = '';
  String _nickName = '用户12345';
  String _phoneNumber = '138****8888';
  final double _blueAreaHeight = 230.0;

  /// 横向区块（账号安全栏）估算高度：padding 20*2 + 图标 26 + 间距 5 + 文字 ~14
  static const double _horizontalSectionHeight = 85;

  double _scrollOffset = 0;
  static const double _maxScrollExtent = 150.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUserInfo();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    bool isLoggedIn = await _userService.checkLoginStatus();
    setState(() {
      _isLoggedIn = isLoggedIn;
    });

    _nickName = await _userService.getNickName();
    _phoneNumber = await _userService.getMaskedPhone();
    _avatarUrl = await _userService.getAvatarUrl();

    setState(() {});
  }

  /// 需要登录的操作：未登录时弹窗引导去登录，登录成功后刷新用户信息
  Future<void> _requireLogin(VoidCallback action) async {
    final bool loggedIn = await _userService.checkLoginStatus();
    if (!mounted) return;
    if (loggedIn) {
      action();
      return;
    }

    // 未登录：弹窗提示去登录
    final bool? goLogin = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: const Text('请先登录后再操作'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
    if (goLogin != true || !mounted) return;

    final result = await context.push('/login');
    if (!mounted) return;
    if (result is Map && result['refresh'] == true) {
      await _loadUserInfo();
    }
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset.clamp(0.0, _maxScrollExtent);
    });
  }

  double get _scaleFactor {
    if (_scrollOffset <= 0) return 1.0;
    if (_scrollOffset >= _maxScrollExtent) return 0.5;
    return 1.0 - (_scrollOffset / _maxScrollExtent) * 0.5;
  }

  bool get _showAppBar {
    return _scrollOffset > _maxScrollExtent * 0.6;
  }

  double get _appBarOpacity {
    if (_scrollOffset <= _maxScrollExtent * 0.6) return 0.0;
    return ((_scrollOffset - _maxScrollExtent * 0.6) / (_maxScrollExtent * 0.3))
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: screenHeight,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2376E3),
                  Color(0xFF2376E3),
                  Color(0xFFF5F5F5),
                  Color(0xFFF5F5F5),
                ],
                stops: [0.0, 0.5, 0.5, 1.0],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // 视口可用高度（已扣除底部导航栏等），内容高度与视口一致，
              // 使 maxScrollExtent=0，滑动仅触发 overscroll，松手回弹到起始位置
              final double viewportHeight = constraints.maxHeight;
              // 蓝色区域底线对齐横向区块（账号安全栏）中心：
              // 顶部间距 48 + 头部区域 + 间距 20 + 横向区块半高
              final double horizontalCenter = 48 +
                  (_blueAreaHeight - 90) +
                  20 +
                  _horizontalSectionHeight / 2;
              final double gradientStop = horizontalCenter / viewportHeight;
              return SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Container(
                  height: viewportHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Color(0xFF2376E3),
                        Color(0xFF4DA6FF),
                        Color(0xFFF5F5F5),
                        Color(0xFFF5F5F5),
                      ],
                      stops: [0.0, gradientStop, gradientStop, 1.0],
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      Transform.scale(
                        scale: _scaleFactor,
                        child: _buildHeaderContent(context),
                      ),
                      const SizedBox(height: 20),
                      _buildHorizontalSection(),
                      const SizedBox(height: 20),
                      _buildListSection(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_showAppBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF2376E3).withValues(alpha: _appBarOpacity),
                      const Color(0xFF4DA6FF).withValues(alpha: _appBarOpacity),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Opacity(
                    opacity: _appBarOpacity,
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isLoggedIn)
                            Text(
                              _nickName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () async {
                                final result = await context.push('/login');
                                if (result is Map &&
                                    result['refresh'] == true) {
                                  await _loadUserInfo();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  '登录',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF2376E3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderContent(BuildContext context) {
    return SizedBox(
      height: _blueAreaHeight - 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoggedIn) ...[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
              ),
              child: ClipOval(
                child: _avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _avatarUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          return Image.asset(
                            'assets/images/default_avatar.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          );
                        },
                      )
                    : Image.asset(
                        'assets/images/default_avatar.png',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _nickName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _phoneNumber,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: () async {
                final result = await context.push('/login');
                if (result is Map && result['refresh'] == true) {
                  await _loadUserInfo();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 35, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  '登录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2376E3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // 去掉背景图，纯代码实现：白底 + 圆角 + 柔和阴影
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHorizontalItem(
            'assets/icons/my_account_safe.png',
            '账号安全',
            () =>
                _requireLogin(() => context.push('/profile/account-security')),
          ),
          _buildHorizontalItem(
            'assets/icons/my_like.png',
            '我的点赞',
            () => _requireLogin(() => context.push('/profile/my-like')),
          ),
          _buildHorizontalItem(
            'assets/icons/my_order_list.png',
            '购买记录',
            () => _requireLogin(() => context.push('/profile/purchase-record')),
          ),
          _buildHorizontalItem(
            'assets/icons/my_cache.png',
            '我的缓存',
            () => _requireLogin(() => EasyLoading.showToast('功能开发中')),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalItem(
    String iconPath,
    String title,
    VoidCallback onTap,
  ) {
    // 图标尺寸系数：iOS 上随全局文本缩放（屏宽/375），其他平台恒为 1.0
    final double s = MediaQuery.textScalerOf(context).scale(1.0);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Image.asset(iconPath, width: 26 * s, height: 26 * s),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection() {
    // 我的账户仅 iOS 平台展示（Android/鸿蒙隐藏）
    final bool showAccount = Platform.isIOS;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (showAccount) ...[
            _buildListItem(
              'assets/icons/my_account.png',
              '我的账户',
              () => _requireLogin(() => EasyLoading.showToast('功能开发中')),
            ),
            const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          ],
          _buildListItem('assets/icons/my_clear_memery.png', '清除缓存', () {}),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_feedback.png', '意见反馈',
              () => context.push('/profile/feedback')),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_question.png', '常见问题',
              () => context.push('/profile/faq')),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_about.png', '关于',
              () => context.push('/profile/about')),
        ],
      ),
    );
  }

  Widget _buildListItem(String iconPath, String title, VoidCallback onTap) {
    // 图标尺寸系数：iOS 上随全局文本缩放（屏宽/375），其他平台恒为 1.0
    final double s = MediaQuery.textScalerOf(context).scale(1.0);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Image.asset(iconPath, width: 18 * s, height: 18 * s),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Image.asset('assets/icons/right_arrow.png',
                width: 12 * s, height: 12 * s),
          ],
        ),
      ),
    );
  }
}
