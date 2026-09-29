import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/screens/profile/bind_phone_screen.dart';
import 'package:fmlink/services/auth_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 南方云教育平台登录页
///
/// 走账号密码格式，最终调用接口：
/// /chain-server/api/link_code_system/login/login_spm
/// 参数：userName / password / deviceId / deviceName
/// 登录成功后的返回处理逻辑与账号密码登录一致。
class SouthCloudLoginScreen extends StatefulWidget {
  const SouthCloudLoginScreen({super.key});

  @override
  State<SouthCloudLoginScreen> createState() => _SouthCloudLoginScreenState();
}

class _SouthCloudLoginScreenState extends State<SouthCloudLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isAgreed = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 南方云教育平台登录
  Future<void> _login() async {
    if (!_isAgreed) {
      EasyLoading.showToast('请阅读并同意泛媒用户协议');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 获取设备信息
      String deviceId = await DeviceInfoUtil.getDeviceId();
      String deviceName = await DeviceInfoUtil.getDeviceName();

      final response = await AuthService().loginWithSouthCloud(
        _accountController.text.trim(),
        _passwordController.text,
        deviceId,
        deviceName,
      );

      if (!mounted) return;

      if (response['status']) {
        // 保存userId到本地存储
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          Constants.kUserId,
          response['data']?['userId']?.toString() ?? '',
        );

        EasyLoading.showToast(response['msg'] ?? '登录成功');
        if (!mounted) return;

        String phoneNumber = response['data']?['phone']?.toString() ?? '';
        if (phoneNumber.isEmpty) {
          // 未绑定手机号：先进入绑定手机号页（必须 push，go 会清空路由栈，
          // 绑定成功后 pop 会弹掉最后一个路由 → 报错 + 空白页）
          final bool bound = await BindPhoneScreen.open(context);
          if (!mounted || !bound) return;
        }
        // 关闭南方云登录页和登录页，携带刷新标志
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.pop({'refresh': true});
      } else {
        // 登录失败
        EasyLoading.showToast(response['msg'] ?? '登录失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '登录失败'));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 打开用户协议（与登录页用户协议一致）
  void _openUserAgreement() {
    context
        .push('/webview?url=${Uri.encodeComponent(Constants.userAgreementUrl)}'
            '&title=${Uri.encodeComponent('泛媒用户协议')}');
  }

  @override
  Widget build(BuildContext context) {
    // 图标尺寸系数：iOS 上随全局文本缩放（屏宽/375，1.0~1.2），Android/鸿蒙恒为 1.0
    final double s = MediaQuery.textScalerOf(context).scale(1.0);
    return Scaffold(
      backgroundColor: Colors.white,
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
            child: Column(
              children: [
                Expanded(
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
                          // 页面标题
                          const Text(
                            '南方云教育平台登录',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 副标题
                          const Text(
                            '使用南方云教育平台账号登录，即可关联泛媒资源',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF999999),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),

                          // 账号输入框
                          TextFormField(
                            controller: _accountController,
                            decoration: InputDecoration(
                              labelText: '账号',
                              hintText: '请输入南方云教育平台账号',
                              labelStyle: const TextStyle(
                                  fontSize: 12, color: Color(0xFF999999)),
                              hintStyle: const TextStyle(
                                  fontSize: 12, color: Color(0xFFBBBBBB)),
                              prefixIcon: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                              if (value == null || value.trim().isEmpty) {
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                  color: const Color(0xFF999999),
                                ),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            obscureText: _obscurePassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入密码';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // 登录按钮（蓝色渐变胶囊）
                          SizedBox(
                            height: 48,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFF2376E3),
                                    Color(0xFF4A9DFF)
                                  ],
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
                                        : const Text(
                                            '登录',
                                            style: TextStyle(
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
                                        text: '《泛媒用户协议》',
                                        style: const TextStyle(
                                          color: Color(0xFF2376E3),
                                          fontSize: 12,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = _openUserAgreement,
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                // 底部文字按钮：免密登录 | 泛媒用户登录（紧贴屏幕底部）
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          // 返回登录页并切换到手机验证码登录
                          Navigator.of(context).pop({'loginType': 'sms'});
                        },
                        child: const Text(
                          '免密登录',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF2376E3),
                          ),
                        ),
                      ),
                      const Text(
                        '|',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFBBBBBB),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // 返回登录页并切换到账号密码登录
                          Navigator.of(context).pop({'loginType': 'password'});
                        },
                        child: const Text(
                          '泛媒用户登录',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF2376E3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
