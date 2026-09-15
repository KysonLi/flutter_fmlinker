import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/error_handler.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final UserService _userService = UserService();

  int _currentStep = 1;
  bool _agreeChecked = false;
  String _inputPhone = '';
  String _code = '';

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    setState(() {});
  }

  void _nextStep() {
    if (_currentStep == 1) {
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      if (_agreeChecked) {
        setState(() => _currentStep = 3);
      } else {
        EasyLoading.showToast('请先阅读并同意《注销须知》');
      }
    }
  }

  Future<void> _submitDelete() async {
    if (_inputPhone.isEmpty) {
      EasyLoading.showToast('请输入手机号');
      return;
    }
    if (_code.isEmpty) {
      EasyLoading.showToast('请输入验证码');
      return;
    }

    EasyLoading.show(status: '处理中...');
    try {
      Map<String, dynamic> response =
          await _userService.deleteAccount(_inputPhone, _code);
      if (response['status']) {
        EasyLoading.showToast('注销申请已提交，请在15天内不要登录');
        await _userService.clearUserInfo();
        // 缓存元数据按账号隔离：注销后立即切回未登录视角
        await CacheService().syncAccount();
        if (!mounted) return;
        context.go('/login');
      } else {
        EasyLoading.showToast(response['msg'] ?? '注销失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '注销失败'));
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _getSmsCode() async {
    if (_inputPhone.isEmpty) {
      EasyLoading.showToast('请先输入手机号');
      return;
    }
    try {
      await _userService.refreshToken();
      Map<String, dynamic> response =
          await _userService.sendSmsCode(_inputPhone, 'delete_account');
      if (response['status']) {
        EasyLoading.showToast('验证码发送成功');
      } else {
        EasyLoading.showToast(response['msg'] ?? '发送失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '发送失败'));
    }
  }

  Widget _numberText(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFFFF4757),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      children: [
        const Text(
          '账号注销后，你在泛媒关联上的所有个人数据和信息将被清空，包括但不限于以下内容:',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 15),
        _numberText('1', '你的 泛票 余额将全部被清零'),
        const SizedBox(height: 10),
        _numberText('2', '你将无法再浏览你已购买的所有资源'),
        const SizedBox(height: 10),
        _numberText('3', '你的关联记录将会被清空'),
        const SizedBox(height: 10),
        _numberText('4', '你的缓存资源文件将会被清空'),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: const Color(0xFFFF4757),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: const Text(
              '继续申请注销',
              style: TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      children: [
        const Text(
          '点击“申请注销”即表示你已阅读并同意以下内容：\n'
          '1.泛媒关联账号成功注销后，将是不可恢复的操作，你应在自行备份账号内相关的信息和数据后，再提交注销申请。\n'
          '2.注销申请提交后，你将自动退出登录，进入15天的注销等待期。注销等待期间如你再次登录该账号，将导致注销申请被撤回，账号自动恢复正常使用。\n'
          '3.注销等待期间，如果你的泛媒关联账号被他人投诉、被国家机关调查或者正处于诉讼、仲裁程序中，泛媒关联团队有权自行终止你的账号注销而无需另行得到你的同意。\n'
          '4.注销等待期满，你的账号将完成注销，你的个人数据和信息将会被清空或者作匿名化处理，包括但不限于：\n'
          '1)你的泛票余额将被清零而无法使用；\n'
          '2)你已购买的目标资源将会被清空而无法浏览；\n'
          '3)你的关联记录、购买记录、点赞记录将会被清除；\n'
          '4)你的评论以及点赞将会作匿名化处理；\n'
          '5.请注意，注销你的泛媒关联账号并不代表本账号注销前的行为和相关责任得到豁免或减轻。\n'
          '6.当你的泛媒阅读账号成功注销后，即便你再次以同一个泛媒个人账号登录泛媒阅读，也无法恢复已注销的泛媒关联账号内的个人数据或信息。',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.8),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Checkbox(
              value: _agreeChecked,
              onChanged: (value) =>
                  setState(() => _agreeChecked = value ?? false),
              activeColor: const Color(0xFFFF4757),
            ),
            const Expanded(
              child: Text(
                '已阅读《注销须知》',
                style: TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor:
                  _agreeChecked ? const Color(0xFFFF4757) : Colors.grey[300],
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: const Text(
              '申请注销',
              style: TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      children: [
        TextField(
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: '请输入手机号',
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2376E3)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
          onChanged: (value) => _inputPhone = value,
        ),
        const SizedBox(height: 12),
        TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '请输入验证码',
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2376E3)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
            counterText: '',
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
            suffixIcon: TextButton(
              onPressed: _getSmsCode,
              child: const Text(
                '获取验证码',
                style: TextStyle(fontSize: 12, color: Color(0xFF2376E3)),
              ),
            ),
          ),
          maxLength: 6,
          style: const TextStyle(fontSize: 14),
          onChanged: (value) => _code = value,
        ),
        const SizedBox(height: 12),
        const Text(
          '请输入绑定的手机号和收到的验证码进行验证',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitDelete,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: const Color(0xFFFF4757),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: const Text(
              '确认注销',
              style: TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return '你正在申请\n注销泛媒关联账号';
      case 2:
        return '注销须知';
      case 3:
        return '注销验证';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        height: double.infinity,
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  _getStepTitle(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    color: Colors.black,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: _currentStep == 1
                    ? _buildStep1()
                    : _currentStep == 2
                        ? _buildStep2()
                        : _buildStep3(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
