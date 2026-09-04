import 'package:flutter/material.dart';

/// 源详情页（占位）
///
/// 由资源模块入口携带 extra（`Map<String, dynamic>`）跳转，
/// extra 通常含 data / isliCode / goodsName 等键：
/// - goodsName / data.goodsName：源所属出版物名称
/// - isliCode：完整 ISLI 链码（可带连字符）
/// - data：后端返回的源详情原始数据（Map）
/// 详细交互开发中，先展示基础信息与占位提示。
class ResourceSourceDetailScreen extends StatelessWidget {
  /// 路由 extra 参数
  final Map<String, dynamic> extra;

  const ResourceSourceDetailScreen({super.key, required this.extra});

  /// extra['data']：容错读取为 Map
  Map<String, dynamic> get _data {
    final dynamic v = extra['data'];
    if (v is Map) return v.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// 依次取第一个非空值（兜底链：外层参数 → data 内同名/别名键）
  String _firstNonEmpty(List<dynamic> candidates) {
    for (final dynamic v in candidates) {
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final String name = _firstNonEmpty(<dynamic>[
      extra['goodsName'],
      _data['goodsName'],
    ]);
    final String isliCode = _firstNonEmpty(<dynamic>[
      extra['isliCode'],
      _data['isliCode'],
      _data['sourceIdentifier'],
    ]);
    final String title = name.isEmpty ? '源详情' : name;

    // 基础信息行：名称 / ISLI 编码 + data 中的标量字段（跳过嵌套与已展示键）
    final List<Widget> rows = <Widget>[];
    void addRow(String label, String value) {
      if (value.isEmpty) return;
      rows.add(_infoRow(label, value));
    }

    addRow('名称', name);
    addRow('ISLI 编码', isliCode);
    const Set<String> skipped = <String>{'goodsName', 'isliCode', 'data'};
    _data.forEach((String key, dynamic value) {
      if (skipped.contains(key)) return;
      if (value is Map || value is List) return;
      addRow(key, value.toString());
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          // 基本信息卡
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        '暂无源信息',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF8C8C8C)),
                      ),
                    ),
                  )
                : Column(
                    children: rows,
                  ),
          ),
          // 占位提示
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(
              children: const [
                Icon(
                  Icons.construction_outlined,
                  size: 56,
                  color: Color(0xFFBFBFBF),
                ),
                SizedBox(height: 14),
                Text(
                  '源详情开发中',
                  style: TextStyle(fontSize: 14, color: Color(0xFF8C8C8C)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F6F8)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8C8C8C)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1F2329),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
