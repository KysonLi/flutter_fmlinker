import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fmlink/services/user_service.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({Key? key}) : super(key: key);

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
    final double gradientStop = _blueAreaHeight / screenHeight;

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
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Container(
              height: screenHeight,
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
                  SizedBox(height: 30),
                  Transform.scale(
                    scale: _scaleFactor,
                    child: _buildHeaderContent(context),
                  ),
                  SizedBox(height: 20),
                  _buildHorizontalSection(),
                  SizedBox(height: 15),
                  _buildListSection(),
                  SizedBox(height: 30),
                ],
              ),
            ),
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
                      const Color(0xFF2376E3).withOpacity(_appBarOpacity),
                      const Color(0xFF4DA6FF).withOpacity(_appBarOpacity),
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
                                if (result is Map && result['refresh'] == true) {
                                  await _loadUserInfo();
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
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
            SizedBox(height: 10),
            Text(
              _nickName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 6),
            Text(
              _phoneNumber,
              style: TextStyle(
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
                padding: EdgeInsets.symmetric(horizontal: 35, vertical: 10),
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
      margin: EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/images/my_h_bg.png'),
          fit: BoxFit.cover,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHorizontalItem(
            'assets/icons/my_account_safe.png',
            '账号安全',
            () async {
              final result = await context.push('/profile/account-security');
              if (result is Map && result['refresh'] == true) {
                await _loadUserInfo();
              }
            },
          ),
          _buildHorizontalItem('assets/icons/my_like.png', '我的点赞', () => context.push('/profile/my-like')),
          _buildHorizontalItem('assets/icons/my_order_list.png', '购买记录', () {}),
          _buildHorizontalItem('assets/icons/my_cache.png', '我的缓存', () {}),
        ],
      ),
    );
  }

  Widget _buildHorizontalItem(
    String iconPath,
    String title,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Image.asset(iconPath, width: 26, height: 26),
          SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildListItem('assets/icons/my_account.png', '我的账户', () {}),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_clear_memery.png', '清除缓存', () {}),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_feedback.png', '意见反馈', () {}),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_question.png', '常见问题', () => context.push('/profile/faq')),
          const Divider(height: 1, indent: 15, color: Color(0xFFEEEEEE)),
          _buildListItem('assets/icons/my_about.png', '关于', () => context.push('/profile/about')),
        ],
      ),
    );
  }

  Widget _buildListItem(String iconPath, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Image.asset(iconPath, width: 18, height: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold),
              ),
            ),
            Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
          ],
        ),
      ),
    );
  }
}
