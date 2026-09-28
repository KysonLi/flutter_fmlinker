enum AccountLoginType {
  unknown,
  qq,
  wechat,
  weibo,
  huawei,
  nfy,
  phone,
  apple,
}

class UserInfo {
  String userId;
  String unificationId;
  String token;
  String avatarUrl;
  String nickName;
  String phoneNumber;
  String gender;
  bool hasPassword;
  bool hasSetUserName;
  AccountLoginType loginType;

  UserInfo({
    this.userId = '',
    this.unificationId = '',
    this.token = '',
    this.avatarUrl = '',
    this.nickName = '',
    this.phoneNumber = '',
    this.gender = '',
    this.hasPassword = false,
    this.hasSetUserName = false,
    this.loginType = AccountLoginType.unknown,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
        userId: json['userId']?.toString() ?? '',
        unificationId: json['unificationId']?.toString() ?? '',
        token: json['token']?.toString() ?? '',
        avatarUrl: json['userHeadImgUrl']?.toString() ??
            json['headImgUrl']?.toString() ??
            json['avatarUrl']?.toString() ??
            '',
        nickName:
            json['userName']?.toString() ?? json['nickName']?.toString() ?? '',
        phoneNumber: json['phoneNo']?.toString() ??
            json['phone']?.toString() ??
            json['phoneNumber']?.toString() ??
            '',
        gender:
            json['userGender']?.toString() ?? json['gender']?.toString() ?? '',
        hasPassword: _parseBool(json['hasPassword']),
        hasSetUserName: _parseBool(json['hasSetUserName']),
        loginType: _parseLoginType(json));
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      String strValue = value.toLowerCase().trim();
      return strValue == 'true' || strValue == '1';
    }
    if (value is int) return value == 1;
    return false;
  }

  static AccountLoginType _parseLoginType(Map<String, dynamic> json) {
    String? loginType =
        json['loginType']?.toString() ?? json['accountLoginType']?.toString();
    if (loginType == null) return AccountLoginType.unknown;

    switch (loginType.toLowerCase()) {
      case 'qq':
        return AccountLoginType.qq;
      case 'wechat':
      case 'weixin':
        return AccountLoginType.wechat;
      case 'weibo':
        return AccountLoginType.weibo;
      case 'huawei':
        return AccountLoginType.huawei;
      case 'nfy':
        return AccountLoginType.nfy;
      case 'phone':
      case 'mobile':
        return AccountLoginType.phone;
      case 'apple':
        return AccountLoginType.apple;
      default:
        return AccountLoginType.unknown;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'unificationId': unificationId,
      'token': token,
      'headImgUrl': avatarUrl,
      'userName': nickName,
      'phone': phoneNumber,
      'gender': gender,
      'hasPassword': hasPassword,
      'hasSetUserName': hasSetUserName,
    };
  }
}
