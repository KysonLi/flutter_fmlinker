import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';

enum PasswordType { setPassword, findPassword }

class SetPasswordScreen extends StatefulWidget {
  final PasswordType type;

  const SetPasswordScreen({
    super.key,
    this.type = PasswordType.setPassword,
  });

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class SetPasswordScreenWithExtra extends StatelessWidget {
  const SetPasswordScreenWithExtra({super.key});

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final type = extra?['type'] == 'find' ? PasswordType.findPassword : PasswordType.setPassword;
    return SetPasswordScreen(type: type);
  }
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isCountingDown = false;
  int _countDownSeconds = 60;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPhone() async {
    UserInfo? userInfo = await _userService.getUserInfo();
    if (userInfo != null && userInfo.phoneNumber.isNotEmpty) {
      _phoneController.text = userInfo.phoneNumber;
    }
  }

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

  Future<void> _getSmsCode() async {
    if (_phoneController.text.isEmpty) {
      EasyLoading.showToast('请输入手机号');
      return;
    }

    if (!_isValidPhone(_phoneController.text)) {
      EasyLoading.showToast('请输入正确的手机号');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String type = widget.type == PasswordType.setPassword ? 'change_password' : 'find_password';
      
      final response = await _apiService.post(
        '/chain-server/api/link_code_system/login/get_verification_code',
        data: {
          'phoneNumber': _phoneController.text,
          'type': type,
        },
      );

      if (response['status']) {
        EasyLoading.showToast('验证码发送成功');
        _startCountDown();
      } else {
        EasyLoading.showToast(response['msg'] ?? '发送失败');
      }
    } catch (e) {
      EasyLoading.showToast('发送失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone);
  }

  bool _isValidPassword(String password) {
    return password.length >= 6 && password.length <= 16;
  }

  Future<void> _submit() async {
    String? error = _validateForm();
    if (error != null) {
      EasyLoading.showToast(error);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String phone = _phoneController.text;
      String smsCode = _smsCodeController.text;
      String password = _passwordController.text;

      UserInfo? userInfo = await _userService.getUserInfo();
      String userId = userInfo?.userId ?? '';
      String deviceId = await DeviceInfoUtil.getDeviceId();

      Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/set_user_password',
        data: {
          'phoneNumber': phone,
          'verificationCode': smsCode,
          'password': password,
          'userId': userId,
          'deviceId': deviceId,
        },
      );

      if (result['status']) {
        if (widget.type == PasswordType.setPassword) {
          EasyLoading.showToast('密码设置成功！');
          if (result['data'] != null) {
            await _userService.saveUserInfo(UserInfo.fromJson(result['data']));
          }
          if (!mounted) return;
          Navigator.pop(context, {'refresh': true});
        } else {
          EasyLoading.showToast('密码重置成功！');
          if (result['data'] != null) {
            await _userService.saveUserInfo(UserInfo.fromJson(result['data']));
          }
          if (!mounted) return;
          Navigator.pop(context, {'refresh': true});
        }
      } else {
        EasyLoading.showToast(result['msg'] ?? '操作失败');
      }
    } catch (e) {
      EasyLoading.showToast('操作失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _validateForm() {
    String phone = _phoneController.text;
    String smsCode = _smsCodeController.text;
    String password = _passwordController.text;

    if (phone.isEmpty) {
      return '请输入手机号';
    }
    if (!_isValidPhone(phone)) {
      return '请输入正确的手机号';
    }
    if (smsCode.isEmpty) {
      return '请输入验证码';
    }
    if (smsCode.length != 6) {
      return '请输入6位验证码';
    }
    if (password.isEmpty) {
      return '请输入密码';
    }
    if (!_isValidPassword(password)) {
      return '密码长度需在6-16位之间';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.type == PasswordType.setPassword ? '设置登录密码' : '找回密码';
    String buttonText = widget.type == PasswordType.setPassword ? '设置密码' : '确认修改';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '请输入手机号',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_phone.png',
                            width: 20,
                            height: 20,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 44,
                          maxHeight: 28,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _smsCodeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: '请输入验证码',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Image.asset(
                                  'assets/icons/login_code.png',
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                maxWidth: 44,
                                maxHeight: 28,
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: _isCountingDown || _isLoading ? null : _getSmsCode,
                          child: Text(
                            _isCountingDown ? '$_countDownSeconds秒后重新获取' : '获取验证码',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isCountingDown ? Colors.grey : const Color(0xFF2376E3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        hintText: '请输入密码（6-16位）',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Image.asset(
                            'assets/icons/login_password.png',
                            width: 20,
                            height: 20,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          maxWidth: 44,
                          maxHeight: 28,
                        ),
                        suffixIcon: IconButton(
                          icon: Image.asset(
                            _isPasswordVisible ? 'assets/icons/eye_open.png' : 'assets/icons/eye_close.png',
                            width: 20,
                            height: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: _isLoading ? null : _submit,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2376E3),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            buttonText,
                            style: const TextStyle(fontSize: 14, color: Colors.white),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
