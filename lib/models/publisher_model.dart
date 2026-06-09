class PublisherModel {
  final String shopId;
  final String shopName;
  final String shopDesc;
  final String shopBrief;
  final String createTime;
  final String nameInitial;
  final String logo;
  final String isliLogo;
  final String goodsCount;

  PublisherModel({
    required this.shopId,
    required this.shopName,
    required this.shopDesc,
    required this.shopBrief,
    required this.createTime,
    required this.nameInitial,
    required this.logo,
    required this.isliLogo,
    required this.goodsCount,
  });

  factory PublisherModel.fromJson(Map<String, dynamic> json) {
    String shopName = json['shopName']?.toString() ?? '';
    return PublisherModel(
      shopId: json['id']?.toString() ?? json['shopId']?.toString() ?? '',
      shopName: shopName,
      shopDesc: json['description']?.toString() ?? json['shopDesc']?.toString() ?? '',
      shopBrief: json['shopBrief']?.toString() ?? '',
      createTime: json['createTime']?.toString() ?? '',
      nameInitial: shopName.isNotEmpty ? shopName.substring(0, 1) : '?',
      logo: json['logo']?.toString() ?? '',
      isliLogo: json['isliLogo']?.toString() ?? '',
      goodsCount: json['goodsCount']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shopId': shopId,
      'shopName': shopName,
      'shopDesc': shopDesc,
      'shopBrief': shopBrief,
      'createTime': createTime,
      'nameInitial': nameInitial,
      'logo': logo,
      'isliLogo': isliLogo,
      'goodsCount': goodsCount,
    };
  }
}