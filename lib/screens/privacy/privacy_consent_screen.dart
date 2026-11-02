import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fmlink/common/policy_navigator.dart';
import 'package:fmlink/services/privacy_consent_service.dart';

class PrivacyConsentScreen extends StatefulWidget {
  final Future<void> Function() onAccepted;

  const PrivacyConsentScreen({super.key, required this.onAccepted});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  late final TapGestureRecognizer _agreementRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _agreementRecognizer = TapGestureRecognizer()
      ..onTap = () => PolicyNavigator.openUserAgreement(context);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => PolicyNavigator.openPrivacyPolicy(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showConsentDialog();
    });
  }

  @override
  void dispose() {
    _agreementRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await PrivacyConsentService().accept();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await widget.onAccepted();
    } catch (error) {
      print('保存隐私政策同意状态失败: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = '保存失败，请重试';
        });
      }
    }
  }

  void _showConsentDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text(
            '隐私政策提示',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF606266),
                      fontSize: 14,
                      height: 1.65,
                    ),
                    children: <InlineSpan>[
                      const TextSpan(
                        text: '欢迎使用泛媒关联！我们将通过泛媒关联',
                      ),
                      TextSpan(
                        text: '《用户协议》',
                        style: const TextStyle(color: Color(0xFF409EFF)),
                        recognizer: _agreementRecognizer,
                      ),
                      const TextSpan(text: '|'),
                      TextSpan(
                        text: '《隐私政策》',
                        style: const TextStyle(color: Color(0xFF409EFF)),
                        recognizer: _privacyRecognizer,
                      ),
                      const TextSpan(
                        text: '帮助您了解我们收集、使用、存储和共享个人信息的情况，以及您所享有的相关权利。\n\n'
                            '您可以通过阅读完整版用户隐私政策，了解个人信息类型与用途的对应关系等更加详尽的个人信息处理规则。\n'
                            '如您同意，请点击“同意”开始接受我们的服务。',
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFF56C6C),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _saving ? null : SystemNavigator.pop,
              child: const Text('不同意并退出'),
            ),
            TextButton(
              onPressed: _saving ? null : _accept,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('同意'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: SizedBox.expand(),
      );
}
