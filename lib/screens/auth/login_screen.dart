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
      final response = await AuthService().getVerificationCode(_phoneController.text, 'login');

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
    // 这里应该导航到用户协议页面
    debugPrint('打开用户协议');
  }

  // 打开隐私政策
  void _openPrivacyPolicy() {
    // 这里应该导航到隐私政策页面
    debugPrint('打开隐私政策');
  }

  Future<void> _sendThirdPartyLogin(String code, String? openId, String platform) async {
    String deviceId = await DeviceInfoUtil.getDeviceId();
    String deviceName = await DeviceInfoUtil.getDeviceName();
    dynamic response = await AuthService().loginWithThirdParty(platform, openId, code, deviceId, deviceName);
    
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

  @override
  Widget build(BuildContext context) {
    // 图标尺寸系数：iOS 上随全局文本缩放（屏宽/375，1.0~1.2），Android/鸿蒙恒为 1.0
    final double s = MediaQuery.textScaleFactorOf(context);
    return Scaffold(
      appBar: null, // 不显示导航栏
      backgroundColor: Colors.white, // 背景为纯白色
      body: GestureDetector(
        onTap: () {
          // 点击空白处收起键盘
          FocusScope.of(context).unfocus();
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 顶部右侧退出按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  
                  // 页面标题
                  Text(
                    _loginType == LoginType.sms
                        ? '泛媒管理 精彩呈现'
                        : '账号密码登录',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  
                  // 输入表单
                  if (_loginType == LoginType.sms) ...[
                    // 手机号输入框
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: '手机号码',
                        hintText: '请输入手机号',
                        labelStyle: const TextStyle(fontSize: 12),
                        hintStyle: const TextStyle(fontSize: 10),
                        prefixIcon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_phone.png',
                            width: 24 * s,
                            height: 24,
                            fit: BoxFit.contain,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 50,
                          maxHeight: 30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入手机号';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // 验证码输入框
                    TextFormField(
                      controller: _smsCodeController,
                      decoration: InputDecoration(
                        labelText: '验证码',
                        hintText: '请输入验证码',
                        labelStyle: const TextStyle(fontSize: 12),
                        hintStyle: const TextStyle(fontSize: 10),
                        prefixIcon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_code.png',
                            width: 24 * s,
                            height: 24,
                            fit: BoxFit.contain,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 50,
                          maxHeight: 30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        suffixIcon: _isGettingCode
                            ? Container(
                                padding: const EdgeInsets.all(4),
                                child: Transform.scale(
                                  scale: 0.5,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _isCountingDown ? null : _getSmsCode,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  _isCountingDown
                                      ? '$_countDownSeconds秒后重试'
                                      : '获取验证码',
                                  style: const TextStyle(fontSize: 10, color: Colors.blue),
                                ),
                              ),
                      ),
                      style: const TextStyle(fontSize: 12),
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
                        labelStyle: const TextStyle(fontSize: 12),
                        hintStyle: const TextStyle(fontSize: 10),
                        prefixIcon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_account.png',
                            width: 24 * s,
                            height: 24,
                            fit: BoxFit.contain,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 50,
                          maxHeight: 30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入账号';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // 密码输入框
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '请输入密码',
                        labelStyle: const TextStyle(fontSize: 12),
                        hintStyle: const TextStyle(fontSize: 10),
                        prefixIcon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_password.png',
                            width: 24 * s,
                            height: 24,
                            fit: BoxFit.contain,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 50,
                          maxHeight: 30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        suffixIcon: TextButton(
                          onPressed: () {
                            // 跳转到找回密码页面
                            context.push('/profile/set-password', extra: {'type': 'find'});
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '找回密码',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入密码';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  
                  // 表单提示
                  Text(
                    _loginType == LoginType.sms
                        ? '未注册手机号将自动注册；登录后可在 我的/账号安全 中设置登录密码'
                        : '已注册[泛媒阅读]、[MPR world]的用户，可直接登录',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // 登录按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: Colors.blue, // 主体色为蓝色
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _loginType == LoginType.sms ? '快速登录' : '立即登录',
                              style: const TextStyle(fontSize: 16, color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: '我已阅读并同意',
                            children: [
                              TextSpan(
                                text: '《用户协议》',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = _openUserAgreement,
                              ),
                              const TextSpan(text: '《'),
                              TextSpan(
                                text: '隐私政策',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = _openPrivacyPolicy,
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
                  const SizedBox(height: 16),

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
                        _loginType == LoginType.sms
                            ? '账号密码登录'
                            : '手机验证码登录',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 第三方登录
                  Column(
                    children: [
                      // 分割线
                      Row(
                        children: const [
                          Expanded(
                            child: Divider(
                              color: Color(0xFFE0E0E0),
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
                              color: Color(0xFFE0E0E0),
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
                              width: 60,
                              height: 60 * s,
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
                              width: 60,
                              height: 60 * s,
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
                                width: 60,
                                height: 60 * s,
                                padding: const EdgeInsets.all(8),
                                child: Image.asset(
                                  'assets/icons/apple.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                          ],
                          // 南方云平台登录（暂无专属图标，先用「更多」图标）
                          GestureDetector(
                            onTap: () => _thirdPartyLogin('south_cloud'),
                            child: Container(
                              width: 60,
                              height: 60 * s,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}