import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

import 'package:fmlink/cache/cache_record.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/resource/resource_types.dart';

/// 出版物下的已缓存资源列表
///
/// extra：goodsId / goodsName
/// 点击资源 → 进入播放页（本地优先播放）
class CachePublicationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const CachePublicationDetailScreen({super.key, required this.extra});

  @override
  State<CachePublicationDetailScreen> createState() =>
      _CachePublicationDetailScreenState();
}

class _CachePublicationDetailScreenState
    extends State<CachePublicationDetailScreen> {
  late final String _goodsId;
  late final String _goodsName;

  @override
  void initState() {
    super.initState();
    _goodsId = widget.extra['goodsId']?.toString() ?? '';
    _goodsName = widget.extra['goodsName']?.toString() ?? '';
    CacheService().addListener(_onCacheChanged);
  }

  @override
  void dispose() {
    CacheService().removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) setState(() {});
  }

  List<CacheRecord> get _records => CacheService()
      .completed
      .where((CacheRecord r) => r.goodsId == _goodsId)
      .toList();

  @override
  Widget build(BuildContext context) {
    final List<CacheRecord> records = _records;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _goodsName.isEmpty ? '已缓存资源' : _goodsName,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: records.isEmpty
          ? const Center(
              child: Text(
                '该出版物暂无已缓存资源',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: records.length,
              itemBuilder: (BuildContext context, int index) {
                return _buildItem(records[index]);
              },
            ),
    );
  }

  Widget _buildItem(CacheRecord rec) {
    final ResourceType type = ResourceType.fromRaw(rec.resourceType);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openPlay(rec),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ResourceTypeUi.color(type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(ResourceTypeUi.icon(type),
                      size: 20, color: ResourceTypeUi.color(type)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        rec.resourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${type.label}${rec.isHlsLocal ? ' · 分段视频' : ''}'
                        ' · ${_formatSize(rec.fileSize ?? 0)}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF999999)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '缓存时间：${_formatTime(rec.createdAt)}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF999999)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _confirmDelete(rec),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Color(0xFFC0C4CC)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 进入播放页（本地优先播放）
  void _openPlay(CacheRecord rec) {
    if (rec.isliCode.isEmpty) {
      EasyLoading.showToast('缺少链码信息，无法打开');
      return;
    }
    ResourceEntry.pushPlay(
      context,
      isliCode: rec.isliCode,
      fromScan: false,
      versionCode: rec.versionCode,
      startIndex: rec.resourceIndex,
    );
  }

  Future<void> _confirmDelete(CacheRecord rec) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除缓存', style: TextStyle(fontSize: 16)),
        content: Text('确定删除「${rec.resourceName}」的缓存吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFF56C6C))),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CacheService().removeCache(rec.id!);
    }
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// 缓存时间（创建记录即开始缓存的时间），格式 yyyy-MM-dd HH:mm
  static String _formatTime(int millis) {
    if (millis <= 0) return '-';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
