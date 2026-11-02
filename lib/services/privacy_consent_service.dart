import 'package:shared_preferences/shared_preferences.dart';

class PrivacyConsentService {
  static final PrivacyConsentService _instance =
      PrivacyConsentService._internal();
  factory PrivacyConsentService() => _instance;
  PrivacyConsentService._internal();

  static const String _consentKey = 'privacy_policy_consent_v1';

  bool _hasConsent = false;

  bool get hasConsent => _hasConsent;

  Future<bool> loadConsent() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    _hasConsent = preferences.getBool(_consentKey) ?? false;
    return _hasConsent;
  }

  Future<void> accept() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final bool saved = await preferences.setBool(_consentKey, true);
    if (!saved) {
      throw StateError('无法保存隐私政策同意状态');
    }
    _hasConsent = true;
  }
}
