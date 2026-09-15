import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/widgets/default_state_view.dart';
import 'package:go_router/go_router.dart';

/// 扫码结果页：展示扫描到的 ISLI 码（线码/图标码）解析出的关联资源
class ScanResultScreen extends StatefulWidget {
  final String isliCode;
  final dynamic resultData;

  const ScanResultScreen({
    super.key,
    required this.isliCode,
    this.resultData,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

/// 单个关联资源
class _ScanTarget {
  final String name;
  final String? url;
  final String? content;
  final int? type;

  const _ScanTarget({
    required this.name,
    this.url,
    this.content,
    this.type,
  });
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  List<_ScanTarget> _targets = <_ScanTarget>[];
  final Map<String, dynamic> _goods = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _parseResult();
  }

  /// 后端 data 结构缺少文档，这里按常见字段名做容错解析
  void _parseResult() {
    final dynamic data = widget.resultData;
    final List<dynamic> items = <dynamic>[];

    if (data is List) {
      items.addAll(data);
    } else if (data is Map) {
      // 顶部商品信息（若返回）
      for (final String key in <String>[
        'goodsName',
        'goodsImage',
        'goodsId',
        'author',
        'publisher',
      ]) {
        if (data[key] != null) {
          _goods[key] = data[key];
        }
      }
      // 资源列表：依次尝试常见键名
      for (final String key in <String>[
        'targetList',
        'targets',
        'targetInfoList',
        'resourceList',
        'resources',
        'sourceList',
        'list',
        'records',
      ]) {
        final dynamic value = data[key];
        if (value is List && value.isNotEmpty) {
          items.addAll(value);
          break;
        }
      }
    }

    _targets = items
        .map((dynamic item) => _parseTarget(item))
        .where((_ScanTarget t) => t.name.isNotEmpty || (t.url ?? '').isNotEmpty)
        .toList();
  }

  _ScanTarget _parseTarget(dynamic item) {
    String? name = _firstString(item, <String>[
      'targetName',
      'name',
      'title',
      'resourceName',
      'sourceFragment',
    ]);
    final String? url = _firstString(item, <String>[
      'targetUrl',
      'url',
      'address',
      'resourceUrl',
      'linkUrl',
      'targetAddress',
      'fileUrl',
    ]);
    final String? content = _firstString(item, <String>[
      'content',
      'text',
      'desc',
      'description',
    ]);
    final int? type = _firstInt(item, <String>[
      'targetType',
      'resourceType',
      'type',
      'fileType',
    ]);

    // 无名称时用内容/链接兜底
    if (name == null || name.isEmpty) {
      if (content != null && content.isNotEmpty) {
        name = content.length > 20 ? '${content.substring(0, 20)}…' : content;
      } else if (url != null && url.isNotEmpty) {
        name = url;
      } else {
        name = '未命名资源';
      }
    }

    return _ScanTarget(name: name, url: url, content: content, type: type);
  }

  static String? _firstString(dynamic item, List<String> keys) {
    if (item is! Map) return null;
    for (final String key in keys) {
      final dynamic value = item[key];
      if (value is String && value.isNotEmpty) return value;
      if (value is num) return value.toString();
    }
    return null;
  }

  static int? _firstInt(dynamic item, List<String> keys) {
    if (item is! Map) return null;
    for (final String key in keys) {
      final dynamic value = item[key];
      if (value is int) return value;
      if (value is String) {
        final int? parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// 资源类型文案：优先按 targetType（ISLITargetType 编码），否则按链接后缀推断
  String _typeLabel(_ScanTarget target) {
    switch (target.type) {
      case 1:
        return '文本';
      case 2:
        return '图片';
      case 3:
        return '音频';
      case 4:
        return '视频';
      case 5:
        return '网页';
      case 6:
        return '3D模型';
    }
    return _typeLabelFromUrl(target.url) ?? '资源';
  }

  static String? _typeLabelFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final String lower = url.toLowerCase().split('?').first;
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi')) {
      return '视频';
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav')) {
      return '音频';
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return '图片';
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return '网页';
    }
    if (lower.endsWith('.glb') ||
        lower.endsWith('.obj') ||
        lower.endsWith('.gltf')) {
      return '3D模型';
    }
    return null;
  }

  IconData _typeIcon(String label) {
    switch (label) {
      case '文本':
        return Icons.description_outlined;
      case '图片':
        return Icons.image_outlined;
      case '音频':
        return Icons.headset_outlined;
      case '视频':
        return Icons.play_circle_outline;
      case '网页':
        return Icons.language;
      case '3D模型':
        return Icons.view_in_ar_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Color _typeColor(String label) {
    switch (label) {
      case '文本':
        return const Color(0xFF67C23A);
      case '图片':
        return const Color(0xFFE6A23C);
      case '音频':
        return const Color(0xFF9B59B6);
      case '视频':
        return const Color(0xFF409EFF);
      case '网页':
        return const Color(0xFF409EFF);
      case '3D模型':
        return const Color(0xFFE6A23C);
      default:
        return const Color(0xFF909399);
    }
  }

  void _openTarget(_ScanTarget target) {
    final String url = target.url ?? '';
    if (url.isNotEmpty) {
      context.push(
        '/webview?url=${Uri.encodeComponent(url)}'
        '&title=${Uri.encodeComponent(target.name)}',
      );
      return;
    }
    final String content = target.content ?? '';
    if (content.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _TargetTextPage(
            title: target.name,
            content: content,
          ),
        ),
      );
      return;
    }
    EasyLoading.showToast('该资源暂无内容');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('扫码结果', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _targets.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return DefaultStateView.empty(
      text: '该码暂未关联资源',
      subText: widget.isliCode,
    );
  }

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildCodeCard(),
        if (_goods.isNotEmpty) ..._buildGoodsCard(),
        const SizedBox(height: 4),
        ..._targets.map(_buildTargetItem),
      ],
    );
  }

  /// 扫描到的码
  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2, size: 20, color: Color(0xFF409EFF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isliCode,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            '共 ${_targets.length} 个资源',
            style: const TextStyle(fontSize: 12, color: Color(0xFF909399)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGoodsCard() {
    final String goodsName = _goods['goodsName']?.toString() ?? '';
    final String goodsImage = _goods['goodsImage']?.toString() ?? '';
    return <Widget>[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: goodsImage.isNotEmpty
                  ? Image.network(
                      goodsImage,
                      width: 56,
                      height: 78,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/default_cover.png',
                        width: 56,
                        height: 78,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Image.asset(
                      'assets/images/default_cover.png',
                      width: 56,
                      height: 78,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                goodsName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildTargetItem(_ScanTarget target) {
    final String label = _typeLabel(target);
    final Color color = _typeColor(label);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            shape: BoxShape.circle,
          ),
          child: Icon(_typeIcon(label), color: color, size: 20),
        ),
        title: Text(
          target.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: color)),
        ),
        trailing:
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC0C4CC)),
        onTap: () => _openTarget(target),
      ),
    );
  }
}

/// 纯文本资源查看页
class _TargetTextPage extends StatelessWidget {
  final String title;
  final String content;

  const _TargetTextPage({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          content,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
      ),
    );
  }
}
