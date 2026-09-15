import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fmlink/cache/cache_record.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/widgets/default_state_view.dart';

/// 缓存页
///
/// 两个 Tab：
/// - 已缓存：按出版物聚合展示已下载资源
/// - 缓存列表：展示待缓存 / 缓存中 / 失败的任务
class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen>
    with SingleTickerProviderStateMixin {
  /// 缓存列表 tab 下标
  static const int _listTabIndex = 1;

  late final TabController _tabController;

  /// 是否已按「缓存列表有数据」自动定位过（只定位一次，不干扰用户手动切换）
  bool _autoLocated = false;

  @override
  void initState() {
    super.initState();
    final bool hasTasks = CacheService().unfinished.isNotEmpty;
    // 缓存列表有数据时默认展示该 tab
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: hasTasks ? _listTabIndex : 0,
    );
    _autoLocated = hasTasks;
    CacheService().addListener(_onCacheChanged);
    CacheService().init();
  }

  @override
  void dispose() {
    CacheService().removeListener(_onCacheChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onCacheChanged() {
    if (!mounted) return;
    setState(() {});
    // 进入页面时记录还未加载完成：首次拿到缓存任务后自动定位到缓存列表 tab
    if (!_autoLocated && CacheService().unfinished.isNotEmpty) {
      _autoLocated = true;
      _tabController.animateTo(_listTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int taskCount = CacheService().unfinished.length;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('我的缓存', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2376E3),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2376E3),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: <Widget>[
            const Tab(text: '已缓存'),
            Tab(
              child: Badge(
                // 缓存任务数量角标：最多 99，超过显示 99+
                isLabelVisible: taskCount > 0,
                label: Text(taskCount > 99 ? '99+' : '$taskCount'),
                offset: const Offset(8, -4),
                child: const Text('缓存列表'),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildDownloadedTab(),
          _buildCacheListTab(),
        ],
      ),
    );
  }

  // ==================== 已缓存 Tab ====================

  Widget _buildDownloadedTab() {
    final List<CacheRecord> completed = CacheService().completed;
    if (completed.isEmpty) {
      return _buildEmpty('暂无已缓存资源');
    }
    // 按出版物聚合
    final Map<String, List<CacheRecord>> groups = <String, List<CacheRecord>>{};
    for (final CacheRecord rec in completed) {
      groups.putIfAbsent(rec.goodsId, () => <CacheRecord>[]).add(rec);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: groups.entries.map((MapEntry<String, List<CacheRecord>> e) {
        final List<CacheRecord> records = e.value;
        final CacheRecord first = records.first;
        final int totalSize = records.fold<int>(
            0, (int sum, CacheRecord r) => sum + (r.fileSize ?? 0));
        return _buildPublicationCard(
          goodsId: e.key,
          goodsName: first.goodsName,
          goodsImage: first.goodsImage,
          count: records.length,
          totalSize: totalSize,
        );
      }).toList(),
    );
  }

  Widget _buildPublicationCard({
    required String goodsId,
    required String goodsName,
    required String goodsImage,
    required int count,
    required int totalSize,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () =>
              context.push('/cache/publication', extra: <String, dynamic>{
            'goodsId': goodsId,
            'goodsName': goodsName,
          }),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: goodsImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: goodsImage,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (BuildContext c, String u) =>
                              _coverPlaceholder(),
                          errorWidget: (BuildContext c, String u, dynamic e) =>
                              _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        goodsName.isEmpty ? '未命名出版物' : goodsName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$count 个资源 · ${_formatSize(totalSize)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF999999)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: Color(0xFFC0C4CC)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: const Color(0xFFF0F0F0),
      child: const Icon(Icons.menu_book_outlined,
          size: 26, color: Color(0xFFBFBFBF)),
    );
  }

  // ==================== 缓存列表 Tab ====================

  Widget _buildCacheListTab() {
    final List<CacheRecord> unfinished = CacheService().unfinished;
    if (unfinished.isEmpty) {
      return _buildEmpty('暂无缓存任务');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: unfinished.length,
      itemBuilder: (BuildContext context, int index) {
        return _buildCacheListItem(unfinished[index]);
      },
    );
  }

  Widget _buildCacheListItem(CacheRecord rec) {
    final ResourceType type = ResourceType.fromRaw(rec.resourceType);
    final CacheStatus status = rec.statusEnum;
    final bool downloading = status == CacheStatus.downloading;
    final bool failed = status == CacheStatus.failed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: <Widget>[
          Row(
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
                      _statusText(rec),
                      style: TextStyle(
                        fontSize: 11,
                        color: failed
                            ? const Color(0xFFF56C6C)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
              // 操作按钮
              _buildActionButton(rec),
            ],
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: rec.progress,
                minHeight: 4,
                backgroundColor: const Color(0xFFEEEEEE),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF2376E3)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusText(CacheRecord rec) {
    // HLS(m3u8) 为「播放列表 + 分片」多文件缓存，单独标注便于用户理解进度含义
    final String tag = (rec.isHlsSource || rec.isHlsLocal) ? ' · 分段视频' : '';
    // 文件大小：直链取已获知的总大小；分段视频为已下载分片合计
    final int size = rec.fileSize ?? 0;
    final String sizeText = size > 0 ? ' · ${_formatSize(size)}' : '';
    switch (rec.statusEnum) {
      case CacheStatus.pending:
        return '待缓存$tag$sizeText';
      case CacheStatus.downloading:
        return '缓存中 ${(rec.progress * 100).toStringAsFixed(0)}%$tag$sizeText';
      case CacheStatus.completed:
        return '已缓存$tag$sizeText';
      case CacheStatus.failed:
        return '缓存失败，点击重试$tag$sizeText';
    }
  }

  Widget _buildActionButton(CacheRecord rec) {
    final CacheStatus status = rec.statusEnum;
    final VoidCallback? onTap;
    final IconData icon;
    final Color color;

    switch (status) {
      case CacheStatus.downloading:
        onTap = () => CacheService().pause(rec.id!);
        icon = Icons.pause_circle_outline;
        color = const Color(0xFF2376E3);
        break;
      case CacheStatus.pending:
        onTap = () => CacheService().resume(rec.id!);
        icon = Icons.play_circle_outline;
        color = const Color(0xFF2376E3);
        break;
      case CacheStatus.failed:
        onTap = () => CacheService().retry(rec.id!);
        icon = Icons.refresh;
        color = const Color(0xFFF56C6C);
        break;
      case CacheStatus.completed:
        onTap = null;
        icon = Icons.check_circle_outline;
        color = const Color(0xFF67C23A);
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onTap != null)
          IconButton(
            onPressed: onTap,
            icon: Icon(icon, size: 22, color: color),
            visualDensity: VisualDensity.compact,
          ),
        IconButton(
          onPressed: () => _confirmDelete(rec),
          icon: const Icon(Icons.delete_outline,
              size: 20, color: Color(0xFFC0C4CC)),
          visualDensity: VisualDensity.compact,
        ),
      ],
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

  // ==================== 通用 ====================

  Widget _buildEmpty(String text) {
    return DefaultStateView.empty(text: text);
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
}
