class Constants {
  // API基础URL
  static const String baseUrl =
      'http://apigateway.mpreader.com:11999'; // 正式服务器地址

  // 协议地址
  static const String userAgreementUrl =
      'https://apigateway.mpreader.com/agreement.html'; // 用户协议
  static const String privacyPolicyUrl =
      'http://www.fanmeinet.com/privacy_policy.html'; // 隐私政策

  // 静态token，实际项目中应该从本地存储中读取
  static String? token;

  // 用户尚未同意隐私政策前禁止触发埋点上报
  static bool hasPrivacyConsent = false;

  // 友盟 SDK 配置：
  // - android / ios 的 AppKey 由 Dart 传入（UmengCommonSdk.initCommonNew）
  // - ohos 的 AppKey 只能配置在原生 ohos/AppScope/resources/rawfile/umconfig.json，
  //   这里的 umengOhosAppKey 仅用于与后台核对，运行时不会传给 SDK
  static const String umengAndroidAppKey = '5b3f2c928f4a9d675a00002c';
  static const String umengIosAppKey = '5ad01d67b27b0a17d9000087';
  static const String umengOhosAppKey = '6ae80442863270068cb2697c';
  static const String umengChannel = 'Umeng';

  // 与 pubspec.yaml 的 version 保持一致，供 U-APM 上报应用版本
  static const String appVersion = '1.0.0+1';

  // 存储键名
  static const String kToken = 'token';
  static const String kUserId = 'user_id';
  static const String kUserInfo = 'user_info';

  // 资源类型
  static const int resourceTypeImage = 1; // 图片
  static const int resourceTypeText = 2; // 文本
  static const int resourceTypeAudio = 3; // 音频
  static const int resourceTypeVideo = 4; // 视频
  static const int resourceType3D = 5; // 3D模型
  static const int resourceTypeHtml = 6; // HTML

  // 支付状态
  static const int payStatusUnpaid = 0; // 未支付
  static const int payStatusPaid = 1; // 已支付
  static const int payStatusRefunded = 2; // 已退款

  // 订单状态
  static const int orderStatusPending = 0; // 待处理
  static const int orderStatusSuccess = 1; // 成功
  static const int orderStatusFailed = 2; // 失败

  // 错误码
  static const int errorCodeSuccess = 0; // 成功
  static const int errorCodeTokenExpired = 401; // token过期
  static const int errorCodeServerError = 500; // 服务器错误

  // 分页默认值
  static const int pageSize = 20;
  static const int pageIndex = 1;

  // 第三方登录平台标识（服务端约定值：weixin/qq/weibo/huawei，注意是 weixin 不是 wechat）
  static const String thirdPartyWeixin = 'weixin'; // 微信
  static const String thirdPartyQq = 'qq'; // QQ
  static const String thirdPartyWeibo = 'weibo'; // 微博
  static const String thirdPartyHuawei = 'huawei'; // 华为

  // ==================== QQ 互联（tencent_kit） ====================

  /// QQ 互联 AppID（纯数字）
  ///
  /// 必须与下面三处保持一致，改动时同步修改：
  /// 1. `pubspec.yaml` 顶部 `tencent_kit.app_id`（Android/iOS 构建脚本读取，缺失构建失败）；
  /// 2. `ohos/entry/src/main/module.json5` 中 QQ 登录回调的 `skills.uris[].host`；
  /// 3. QQ 互联后台登记的应用 AppID。
  static const String qqAppId = '1106531844';
}
