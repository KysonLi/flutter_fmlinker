import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:fmlink/utils/error_handler.dart';

class BindPhoneScreen extends StatefulWidget {
  const BindPhoneScreen({super.key});

  /// 打开绑定手机号页并等待结果，返回 true 表示绑定成功（调用方据此刷新登录态）
  ///
  /// ⚠️ 必须用 `push` 进入，不能用 `go`：`go` 会把整个路由栈替换成本页，
  /// 绑定成功后本页无处可退，`Navigator.pop` 弹掉的会是最后一个路由——
  /// go_router 会断言失败抛异常，被 `_bindPhone` 的 catch 捕获成「绑定失败」提示，
  /// 同时页面已被移除，界面上只剩下空白页。
  static Future<bool> open(BuildContext context) async {
    final dynamic result = await context.push('/profile/bind-phone');
    return result is Map && result['refresh'] == true;
  }

  @override
  State<BindPhoneScreen> createState() => _BindPhoneScreenState();
}

class _BindPhoneScreenState extends State<BindPhoneScreen> {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isCountingDown = false;
  int _countDownSeconds = 60;

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
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
      final response = await _apiService.post(
        '/chain-server/api/link_code_system/login/get_verification_code',
        data: {
          'phoneNumber': _phoneController.text,
          'type': 'bind_phone',
        },
      );

      if (response['status']) {
        EasyLoading.showToast('验证码发送成功');
        _startCountDown();
      } else {
        EasyLoading.showToast(response['msg'] ?? '发送失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '发送失败'));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone);
  }

  Future<void> _bindPhone() async {
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

      UserInfo? userInfo = await _userService.getUserInfo();
      String userId = userInfo?.userId ?? '';
      String deviceId = await DeviceInfoUtil.getDeviceId();

      Map<String, dynamic> result = await _apiService.post(
        '/chain-server/api/link_code_system/login/bind_user_phone_number',
        data: {
          'phoneNumber': phone,
          'verificationCode': smsCode,
          'userId': userId,
          'deviceId': deviceId,
        },
      );

      if (result['status']) {
        EasyLoading.showToast('绑定成功');
        await _saveBindResult(result['data']);
        if (!mounted) return;
        _closeWithRefresh();
      } else {
        EasyLoading.showToast(result['msg'] ?? '绑定失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '绑定失败'));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 持久化绑定接口返回的最新用户信息（含新 token）
  ///
  /// 绑定手机号可能把第三方账号并入已存在的手机号账号，服务端会重新下发 token；
  /// 这里必须同时更新 SharedPreferences 与内存中的 `Constants.token`
  /// （双写约定见 CLAUDE.md 的「Auth & token storage」），否则后续请求仍带旧 token。
  Future<void> _saveBindResult(dynamic data) async {
    if (data is! Map) return;
    final UserInfo userInfo =
        UserInfo.fromJson(Map<String, dynamic>.from(data));
    await _userService.saveUserInfo(userInfo);
    if (userInfo.token.isNotEmpty) {
      await _userService.saveToken(userInfo.token);
    }
    // 绑定可能更换账号（合并），缓存元数据需按新账号重新加载
    await CacheService().syncAccount();
  }

  /// 关闭本页并回传刷新标志
  ///
  /// 正常入口都是 `push`，直接 pop 即可；若栈中已无上一页（深链直达等异常情况），
  /// 回首页兜底，避免 pop 掉最后一个路由导致空白页（同上注释）。
  void _closeWithRefresh() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, {'refresh': true});
    } else {
      context.go('/');
    }
  }

  String? _validateForm() {
    String phone = _phoneController.text;
    String smsCode = _smsCodeController.text;

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
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('绑定手机号', style: TextStyle(fontSize: 14)),
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
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                        hintStyle:
                            const TextStyle(fontSize: 14, color: Colors.grey),
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
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              hintStyle: const TextStyle(
                                  fontSize: 14, color: Colors.grey),
                              prefixIcon: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                          onPressed: _isCountingDown || _isLoading
                              ? null
                              : _getSmsCode,
                          child: Text(
                            _isCountingDown
                                ? '$_countDownSeconds秒后重新获取'
                                : '获取验证码',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isCountingDown
                                  ? Colors.grey
                                  : const Color(0xFF2376E3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '绑定手机号后可使用手机号登录',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: _isLoading ? null : _bindPhone,
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
                        : const Text(
                            '绑定',
                            style: TextStyle(fontSize: 14, color: Colors.white),
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
