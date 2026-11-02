import 'package:flutter/widgets.dart';
import 'package:fmlink/common/constants.dart';
import 'package:go_router/go_router.dart';

class PolicyNavigator {
  static void openUserAgreement(BuildContext context) {
    _open(
      context,
      url: Constants.userAgreementUrl,
      title: '用户协议',
    );
  }

  static void openPrivacyPolicy(BuildContext context) {
    _open(
      context,
      url: Constants.privacyPolicyUrl,
      title: '隐私政策',
    );
  }

  static void _open(
    BuildContext context, {
    required String url,
    required String title,
  }) {
    final String location = Uri(
      path: '/webview',
      queryParameters: <String, String>{
        'url': url,
        'title': title,
      },
    ).toString();
    context.push(location);
  }
}
