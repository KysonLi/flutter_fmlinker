// ISLI目标类型枚举
enum ISLITargetType {
  unknown(0), // 未知类型
  text(1), // 文本
  image(2), // 图片
  audio(3), // 音频
  video(4), // 视频
  html(5), // HTML
  obj(6), // 3D模型
  source(7), // 仅类型占位，并不做类型判断依据
  multiple(8), // 仅类型占位，并不做类型判断依据
  allBook(9); // 仅类型占位，并不做类型判断依据

  final int value;
  const ISLITargetType(this.value);

  factory ISLITargetType.fromValue(int value) {
    return values.firstWhere((type) => type.value == value,
        orElse: () => unknown);
  }
}

// 定价策略常量
class PricingStrategy {
  static const String allFree = "CHAIN_ALL_FREE"; // 免费
  static const String uniformPrice = "CHAIN_UNIFORM_PRICE"; // 整体定价
  static const String sourceSamePrice = "CHAIN_SOURCE_SAME_PRICE"; // 按每个源相同定价
  static const String groupFreedomPrice =
      "CHAIN_GROUP_FREEDOM_PRICE"; // 按源自定义分组定价
  static const String sourceDifferencePrice =
      "CHAIN_SOURCE_DIFFERENCE_PRICE"; // 按每个源分别定价
  static const String chapterPrice = "CHAIN_CHAPTER_PRICE"; // 按每章分别定价
}
