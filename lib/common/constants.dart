class Constants {
  // API基础URL
  static const String baseUrl = 'http://apigateway.mpreader.com:11999'; // 正式服务器地址
  
  // 静态token，实际项目中应该从本地存储中读取
  static String? token;
  
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
}
