import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fluwx/fluwx.dart';
import 'package:fmlink/services/third_party_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/services/auth_service.dart';
import 'package:fmlink/common/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/utils/device_info_util.dart';

// 登录方式枚举
enum LoginType {
  sms, // 手机验证码登录
  password, // 账号密码登录
  thirdParty, // 第三方登录
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _smsCodeController = TextEditingController();
  bool _isLoading = false;
  bool _isAgreed = false;
  bool _isCountingDown = false;
  int _countDownSeconds = 60;
  bool _isGettingCode = false;
  LoginType _loginType = LoginType.sms; // 默认手机验证码登录

  // 开始倒计时
  void _startCountDown() {
    if (!mounted) return;

    setState(() {
      _isCountingDown = true;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;

      if (_countDownSeconds > 0) {
        setState(() {
          _countDownSeconds--;
        });
        _startCountDown();
      } else {
        setState(() {
          _isCountingDown = false;
          _countDownSeconds = 60;
        });
      }
    });
  }

  // 获取验证码
  void _getSmsCode() async {
    if (_phoneController.text.isEmpty) {
      EasyLoading.showToast('请输入手机号');
      return;
    }

    setState(() {
      _isGettingCode = true;
    });

    try {
      final response = await AuthService()
          .getVerificationCode(_phoneController.text, 'login');

      if (response['status']) {
        // 验证码获取成功
        EasyLoading.showToast(response['msg']);

        // 读取expireTime用于倒计时
        int expireTime = response['data']['expireTime'] ?? 60;
        _countDownSeconds = expireTime;
        _startCountDown();
      } else {
        // 验证码获取失败
        EasyLoading.showToast(response['msg']);
      }
    } catch (e) {
      EasyLoading.showToast('获取验证码失败: $e');
    } finally {
      setState(() {
        _isGettingCode = false;
      });
    }
  }

  // 登录
  void _login() async {
    if (!_isAgreed) {
      EasyLoading.showToast('请阅读并同意用户协议和隐私政策');
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        dynamic response;
        // 获取设备信息
        String deviceId = await DeviceInfoUtil.getDeviceId();
        String deviceName = await DeviceInfoUtil.getDeviceName();

        if (_loginType == LoginType.sms) {
          // 手机验证码登录
          response = await AuthService().loginWithSms(
            _phoneController.text,
            _smsCodeController.text,
            deviceId,
            deviceName,
          );
        } else {
          // 账号密码登录
          response = await AuthService().loginWithPassword(
            _phoneController.text,
            _passwordController.text,
            deviceId,
            deviceName,
          );
        }

        if (response['status']) {
          // 重置倒计时
          _countDownSeconds = 60;

          // // 登录成功，保存token和用户信息
          // String token = response['data']['token'];
          // Constants.token = token;

          // // 保存token
          // await UserService().saveToken(token);

          // // 保存用户信息
          // UserInfo userInfo = UserInfo(
          //   userId: response['data']['userId']?.toString() ?? '',
          //   unificationId: response['data']['unificationId']?.toString() ?? '',
          //   nickName: response['data']['userName']?.toString() ?? '',
          //   phoneNumber: response['data']['phone']?.toString() ?? '',
          //   avatarUrl: response['data']['headImgUrl']?.toString() ?? '',
          //   gender: response['data']['gender']?.toString() ?? '',
          //   hasPassword: response['data']['hasPassword'] == true || response['data']['hasPassword'] == 1,
          //   hasSetUserName: response['data']['hasSetUserName'] == true || response['data']['hasSetUserName'] == 1,
          // );
          // await UserService().saveUserInfo(userInfo);
          String phoneNumber = response['data']['phone']?.toString() ?? '';

          // 保存userId到本地存储
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString(Constants.kUserId, response['data']['userId']);

          // 显示登录成功提示
          EasyLoading.showToast(response['msg']);
          if (!mounted) return;
          // 非手机验证码登录后判断是否需要绑定手机号
          if (_loginType != LoginType.sms && phoneNumber.isEmpty) {
            // 跳转绑定手机号页面
            context.go('/profile/bind-phone');
          } else {
            // 关闭登录页面，携带刷新标志
            Navigator.pop(context, {'refresh': true});
          }
        } else {
          // 登录失败
          EasyLoading.showToast(response['msg']);
        }
      } catch (e) {
        EasyLoading.showToast('登录失败: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 切换登录方式
  void _switchLoginType(LoginType type) {
    setState(() {
      _loginType = type;
    });
  }

  // 打开用户协议
  void _openUserAgreement() {
    context
        .push('/webview?url=${Uri.encodeComponent(Constants.userAgreementUrl)}'
            '&title=${Uri.encodeComponent('用户协议')}');
  }

  // 打开隐私政策
  void _openPrivacyPolicy() {
    context
        .push('/webview?url=${Uri.encodeComponent(Constants.privacyPolicyUrl)}'
            '&title=${Uri.encodeComponent('隐私政策')}');
  }

  Future<void> _sendThirdPartyLogin(
      String code, String? openId, String platform) async {
    String deviceId = await DeviceInfoUtil.getDeviceId();
    String deviceName = await DeviceInfoUtil.getDeviceName();
    dynamic response = await AuthService()
        .loginWithThirdParty(platform, openId, code, deviceId, deviceName);

    if (!mounted) return;

    if (response['status']) {
      String phoneNumber = response['data']['phone']?.toString() ?? '';
      if (phoneNumber.isEmpty) {
        context.go('/profile/bind-phone');
      } else {
        Navigator.pop(context, {'refresh': true});
      }
    } else {
      EasyLoading.showToast(response['msg']);
    }
  }

  // 第三方登录
  Future<void> _thirdPartyLogin(String platform) async {
    // 这里应该实现第三方登录逻辑
    debugPrint('第三方登录: $platform');
    if (platform == 'wechat') {
      // 判断微信是否已安装
      final isInstalled = await ThirdPartyManager.isWeChatInstalled();
      if (!isInstalled) {
        EasyLoading.showToast('请先安装微信');
        return;
      }
      // 微信登录
      ThirdPartyManager.listenWeChatResult((response) async {
        if (response is WeChatAuthResponse) {
          if (response.errCode == 0) {
            final code = response.code ?? '';
            // 微信登录成功
            EasyLoading.showToast('微信登录成功');
            // 发送登录请求
            await _sendThirdPartyLogin(code, null, platform);
            debugPrint(response.toString());
          }
        }
      });
      ThirdPartyManager.weChatLogin();
    }
  }

  // 显示更多登录方式底部弹窗
  void _showMoreLoginOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // 顶部指示条
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5E5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '更多登录方式',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              // 南方云教育平台
              _buildMoreLoginOption(
                sheetContext,
                icon: Icons.cloud_outlined,
                label: '南方云教育平台',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  // 进入南方云教育平台登录页
                  final result = await context
                      .push<Map<String, dynamic>>('/login/south-cloud');
                  if (!mounted) return;
                  // 根据返回结果切换登录方式
                  final loginType = result?['loginType'];
                  if (loginType == 'sms') {
                    _switchLoginType(LoginType.sms);
                  } else if (loginType == 'password') {
                    _switchLoginType(LoginType.password);
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // 底部弹窗中的登录方式选项
  Widget _buildMoreLoginOption(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: const Color(0xFF2376E3), size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 图标尺寸系数：iOS 上随全局文本缩放（屏宽/375，1.0~1.2），Android/鸿蒙恒为 1.0
    final double s = MediaQuery.textScalerOf(context).scale(1.0);
    return Scaffold(
      appBar: null, // 不显示导航栏
      backgroundColor: Colors.white, // 背景为纯白色
      body: GestureDetector(
        onTap: () {
          // 点击空白处收起键盘
          FocusScope.of(context).unfocus();
        },
        child: Container(
          // 顶部淡蓝渐变为页面增加层次感
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF0F6FF), Colors.white],
              stops: [0.0, 0.4],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    // 右上角退出按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.close),
                          color: Colors.black45,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Logo
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 页面标题
                    Text(
                      _loginType == LoginType.sms ? '泛媒管理 精彩呈现' : '账号密码登录',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 副标题（原表单提示文案）
                    Text(
                      _loginType == LoginType.sms
                          ? '未注册手机号将自动注册；登录后可在 我的/账号安全 中设置登录密码'
                          : '已注册[泛媒阅读]、[MPR world]的用户，可直接登录',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF999999),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 输入表单
                    if (_loginType == LoginType.sms) ...[
                      // 手机号输入框
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: '手机号码',
                          hintText: '请输入手机号',
                          labelStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFF999999)),
                          hintStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFFBBBBBB)),
                          prefixIcon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Image.asset(
                              'assets/icons/login_phone.png',
                              width: 22 * s,
                              height: 22,
                              fit: BoxFit.contain,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            maxWidth: 50,
                            maxHeight: 30,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2376E3),
                              width: 1.2,
                            ),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入手机号';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // 验证码输入框
                      TextFormField(
                        controller: _smsCodeController,
                        decoration: InputDecoration(
                          labelText: '验证码',
                          hintText: '请输入验证码',
                          labelStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFF999999)),
                          hintStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFFBBBBBB)),
                          prefixIcon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Image.asset(
                              'assets/icons/login_code.png',
                              width: 22 * s,
                              height: 22,
                              fit: BoxFit.contain,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            maxWidth: 50,
                            maxHeight: 30,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2376E3),
                              width: 1.2,
                            ),
                          ),
                          suffixIcon: _isGettingCode
                              ? Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Transform.scale(
                                    scale: 0.5,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF2376E3),
                                      ),
                                    ),
                                  ),
                                )
                              : TextButton(
                                  onPressed:
                                      _isCountingDown ? null : _getSmsCode,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    _isCountingDown
                                        ? '$_countDownSeconds秒后重试'
                                        : '获取验证码',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF2376E3),
                                    ),
                                  ),
                                ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入验证码';
                          }
                          return null;
                        },
                      ),
                    ] else if (_loginType == LoginType.password) ...[
                      // 账号输入框
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: '账号',
                          hintText: '请输入账号',
                          labelStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFF999999)),
                          hintStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFFBBBBBB)),
                          prefixIcon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Image.asset(
                              'assets/icons/login_account.png',
                              width: 22 * s,
                              height: 22,
                              fit: BoxFit.contain,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            maxWidth: 50,
                            maxHeight: 30,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2376E3),
                              width: 1.2,
                            ),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入账号';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // 密码输入框
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          hintText: '请输入密码',
                          labelStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFF999999)),
                          hintStyle: const TextStyle(
                              fontSize: 12, color: Color(0xFFBBBBBB)),
                          prefixIcon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Image.asset(
                              'assets/icons/login_password.png',
                              width: 22 * s,
                              height: 22,
                              fit: BoxFit.contain,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            maxWidth: 50,
                            maxHeight: 30,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2376E3),
                              width: 1.2,
                            ),
                          ),
                          suffixIcon: TextButton(
                            onPressed: () {
                              // 跳转到找回密码页面
                              context.push('/profile/set-password',
                                  extra: {'type': 'find'});
                            },
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              '找回密码',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF2376E3)),
                            ),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入密码';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    // 登录按钮（蓝色渐变胶囊）
                    SizedBox(
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xFF2376E3), Color(0xFF4A9DFF)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2376E3)
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _isLoading ? null : _login,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _loginType == LoginType.sms
                                          ? '快速登录'
                                          : '立即登录',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 用户协议
                    Row(
                      children: [
                        Checkbox(
                          value: _isAgreed,
                          onChanged: (value) {
                            setState(() {
                              _isAgreed = value ?? false;
                            });
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeColor: const Color(0xFF2376E3),
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: '我已阅读并同意',
                              children: [
                                TextSpan(
                                  text: '《用户协议》',
                                  style: const TextStyle(
                                    color: Color(0xFF2376E3),
                                    fontSize: 12,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _openUserAgreement,
                                ),
                                const TextSpan(text: '《'),
                                TextSpan(
                                  text: '隐私政策',
                                  style: const TextStyle(
                                    color: Color(0xFF2376E3),
                                    fontSize: 12,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _openPrivacyPolicy,
                                ),
                                const TextSpan(text: '》'),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 登录方式切换
                    Center(
                      child: TextButton(
                        onPressed: () {
                          _switchLoginType(
                            _loginType == LoginType.sms
                                ? LoginType.password
                                : LoginType.sms,
                          );
                        },
                        child: Text(
                          _loginType == LoginType.sms ? '账号密码登录' : '手机验证码登录',
                          style: const TextStyle(
                            color: Color(0xFF2376E3),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 第三方登录
                    Column(
                      children: [
                        // 分割线
                        Row(
                          children: const [
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE5E5E5),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              '第三方账号登录',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE5E5E5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 第三方登录按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => _thirdPartyLogin('wechat'),
                              child: Container(
                                width: 50,
                                height: 50 * s,
                                padding: const EdgeInsets.all(8),
                                child: Image.asset(
                                  'assets/icons/wechat.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: () => _thirdPartyLogin('qq'),
                              child: Container(
                                width: 50,
                                height: 50 * s,
                                padding: const EdgeInsets.all(8),
                                child: Image.asset(
                                  'assets/icons/qq.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            // 苹果登录仅在 iOS 平台显示
                            if (Platform.isIOS) ...[
                              const SizedBox(width: 24),
                              GestureDetector(
                                onTap: () => _thirdPartyLogin('apple'),
                                child: Container(
                                  width: 50,
                                  height: 50 * s,
                                  padding: const EdgeInsets.all(8),
                                  child: Image.asset(
                                    'assets/icons/apple.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                            ],
                            // 更多登录方式（点击弹出底部弹窗）
                            GestureDetector(
                              onTap: _showMoreLoginOptions,
                              child: Container(
                                width: 50,
                                height: 50 * s,
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.more_horiz,
                                  size: 32,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
