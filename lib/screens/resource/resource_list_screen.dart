import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';

import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/screens/resource/widgets/chain_code_sheet.dart';
import 'package:fmlink/services/user_service.dart';

/// 资源列表页（多资源链码的中间页）
///
/// extra 键：
/// - isliCode：当前链码（纯数字）
/// - fromScan：是否由扫码进入
/// - versionCode：版本号（String?，可空）
///
/// 数据由 fetchSourceScan 拉取；底部固定工具栏提供
/// 「链码列表 / 扫码 / 源详情」三个入口。
class ResourceListScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const ResourceListScreen({super.key, required this.extra});

  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  final ScrollController _scrollController = ScrollController();

  /// 当前链码（纯数字）
  late String _isliCode;

  /// 是否由扫码界面进入（决定 hasScanUse）
  late bool _fromScan;

  /// 版本号（空串视为未传）
  String? _versionCode;

  SourceScanData? _data;
  bool _loading = true;
  bool _failed = false;

  /// 分页：每次请求 20 条，target.resources 按页返回
  static const int _pageSize = 20;

  /// 已加载的资源列表（跨页累加）
  List<ScanResource> _resources = const [];

  /// 当前已加载到的页码
  int _pageIndex = 1;

  /// 是否还有更多资源（依据 target.resourceCount 与已加载数判断）
  bool _hasMore = true;

  /// 是否正在加载下一页（防重入）
  bool _loadingMore = false;

  /// 加载更多是否失败（footer 可点击重试）
  bool _loadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final Map<String, dynamic> extra = widget.extra;
    _isliCode = (extra['isliCode']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    _fromScan = extra['fromScan'] == true;
    final String? version = extra['versionCode']?.toString();
    _versionCode = (version == null || version.isEmpty) ? null : version;
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== 数据 ====================

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    EasyLoading.show(status: '加载中...');
    try {
      await UserService().refreshToken();

      final Map<String, dynamic> res =
          await ResourceService().fetchSourceScan(
        _isliCode,
        pageIndex: 1,
        pageSize: _pageSize,
        fromScan: _fromScan,
        versionCode: _versionCode,
      );

      if (res['status'] != true || res['data'] == null) {
        EasyLoading.showToast(res['msg']?.toString() ?? '查询资源失败，请重试');
        if (mounted) {
          setState(() {
            _data = null;
            _resources = const [];
            _failed = true;
            _loading = false;
          });
        }
        return;
      }

      if (!mounted) return;
      final SourceScanData data = SourceScanData.fromJson(
        (res['data'] as Map).cast<String, dynamic>(),
      );
      final List<ScanResource> more = data.currentResources;
      setState(() {
        _data = data;
        _resources = more;
        _pageIndex = 1;
        _hasMore = more.isNotEmpty && _hasMoreResources(data, more.length);
        _loadingMore = false;
        _loadMoreFailed = false;
        _failed = false;
        _loading = false;
        // 链码列表接口按当前源的版本号请求更可靠
        if ((_versionCode == null || _versionCode!.isEmpty) &&
            data.versionCode != null) {
          _versionCode = data.versionCode!.toString();
        }
      });

      // 切换链码后滚动回顶部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    } catch (e) {
      EasyLoading.showToast('查询资源失败，请重试');
      if (mounted) {
        setState(() {
          _data = null;
          _resources = const [];
          _failed = true;
          _loading = false;
        });
      }
    } finally {
      EasyLoading.dismiss();
    }
  }

  /// 滚动到底部附近时触发加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  /// 依据后端返回判断是否还有更多：优先使用 target.resourceCount；
  /// 接口未返回总数时，以「当前页是否已满」兜底判断
  bool _hasMoreResources(SourceScanData data, int loaded) {
    final int? total = data.currentTarget?.resourceCount;
    if (total != null && total > 0) return loaded < total;
    return loaded >= _pageSize;
  }

  /// 上拉加载下一页资源（追加到 _resources）
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      await UserService().refreshToken();
      final Map<String, dynamic> res =
          await ResourceService().fetchSourceScan(
        _isliCode,
        pageIndex: _pageIndex + 1,
        pageSize: _pageSize,
        fromScan: _fromScan,
        versionCode: _versionCode,
      );
      if (!mounted) return;
      if (res['status'] != true || res['data'] == null) {
        setState(() {
          _loadingMore = false;
          _loadMoreFailed = true;
        });
        return;
      }
      final SourceScanData data = SourceScanData.fromJson(
        (res['data'] as Map).cast<String, dynamic>(),
      );
      final List<ScanResource> more = data.currentResources;
      if (!mounted) return;
      setState(() {
        _pageIndex++;
        _data = data;
        _resources = <ScanResource>[..._resources, ...more];
        _loadingMore = false;
        _hasMore = more.isNotEmpty && _hasMoreResources(data, _resources.length);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  // ==================== 操作 ====================

  /// 链码列表 → 选择新链码后重拉资源并回顶
  Future<void> _openChainCodeSheet() async {
    final SourceScanData? data = _data;
    final String serviceCode =
        data?.serviceCode ?? data?.source?.serviceCode ?? '';
    final String prefixCode =
        data?.prefixCode ?? data?.source?.prefixCode ?? '';
    if (serviceCode.isEmpty || prefixCode.isEmpty) {
      EasyLoading.showToast('暂无链码列表');
      return;
    }

    final ChainCodeSelection? selection = await showChainCodeSheet(
      context,
      serviceCode: serviceCode,
      prefixCode: prefixCode,
      versionCode: _versionCode,
      currentIsliCode: _isliCode,
    );
    if (selection == null || !mounted) return;
    // 选中同一条链码无需刷新
    if (selection.isliCode == _isliCode) return;

    setState(() {
      _isliCode = selection.isliCode;
    });
    _load();
  }

  void _openScan() {
    context.push('/scan');
  }

  void _openSourceDetail() {
    final SourceScanData? data = _data;
    if (data == null) return;
    context.push(kResourceSourceDetailRoute, extra: <String, dynamic>{
      'data': data.raw,
      'goodsName': data.goodsName ?? '',
    });
  }

  void _pushPlay(int index) {
    ResourceEntry.pushPlay(
      context,
      isliCode: _isliCode,
      fromScan: _fromScan,
      versionCode: _versionCode,
      startIndex: index,
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '资源列表',
          style: TextStyle(fontSize: 16, color: Colors.black),
        ),
      ),
      body: Stack(
        children: <Widget>[
          _buildContent(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_failed || _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 70),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off, size: 48, color: Color(0xFFC0C4CC)),
              const SizedBox(height: 12),
              const Text(
                '查询资源失败，请重试',
                style: TextStyle(fontSize: 13, color: Color(0xFF909399)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final SourceScanData data = _data!;
    final List<ScanResource> resources = _resources;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        0,
        12,
        0,
        76 + MediaQuery.of(context).padding.bottom,
      ),
      children: <Widget>[
        _buildCodeCard(data),
        if (resources.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Column(
                children: <Widget>[
                  const Text(
                    '该链码暂无可播放资源',
                    style: TextStyle(fontSize: 13, color: Color(0xFF909399)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('刷新')),
                ],
              ),
            ),
          )
        else ...<Widget>[
          for (int i = 0; i < resources.length; i++)
            _buildResourceCard(i, resources[i]),
          _buildListFooter(),
        ],
      ],
    );
  }

  /// 列表底部加载状态：加载中 / 失败重试 / 没有更多 / 提示上拉
  Widget _buildListFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: GestureDetector(
            onTap: _loadMore,
            child: const Text(
              '加载失败，点击重试',
              style: TextStyle(fontSize: 12, color: Color(0xFF2F7BFF)),
            ),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            '— 已加载全部 ${_resources.length} 条资源 —',
            style: const TextStyle(fontSize: 12, color: Color(0xFFC0C4CC)),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '上拉加载更多',
          style: TextStyle(fontSize: 12, color: Color(0xFFC0C4CC)),
        ),
      ),
    );
  }

  /// 顶部链码头卡：链码 + 付费状态 + 关联资源总数 + goodsName
  Widget _buildCodeCard(SourceScanData data) {
    // 总数取「当前源」的 resourceCount（顶层 resourceCount 可能为整书总数）
    final int total = data.source?.resourceCount ??
        data.currentTarget?.resourceCount ??
        _resources.length;
    final String goodsName = data.goodsName ?? '';

    String tag;
    Color tagColor;
    if (data.isSourceFree) {
      tag = '免费';
      tagColor = const Color(0xFF67C23A);
    } else if (data.isSourcePaid) {
      tag = '已购';
      tagColor = const Color(0xFF00AFFE);
    } else {
      tag = '付费';
      tagColor = const Color(0xFFFF8F00);
    }

    final String? identifier = data.source?.sourceIdentifier;
    final String codeText =
        (identifier != null && identifier.isNotEmpty) ? identifier : _hyphenCode(_isliCode);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  codeText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildTag(tag, tagColor),
            ],
          ),
          if (goodsName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              goodsName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF909399)),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '关联资源 $total',
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceCard(int index, ScanResource resource) {
    final ResourceType type = resource.type;
    final String title = _resourceTitle(resource);
    final String duration = _durationText(resource.second);
    final String subTitle =
        duration.isEmpty ? type.label : '${type.label} · $duration';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _pushPlay(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ResourceTypeUi.color(type).withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ResourceTypeUi.icon(type),
                  color: ResourceTypeUi.color(type),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF909399),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFC0C4CC)),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部固定工具栏（背景贴底白 + SafeArea）
  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
          color: Colors.white,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: <Widget>[
              _buildAction(Icons.list_alt_outlined, '链码列表', _openChainCodeSheet),
              _buildAction(Icons.qr_code_scanner, '扫码', _openScan),
              _buildAction(Icons.info_outline, '源详情', _openSourceDetail),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: const Color(0xFF4F5960)),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF4F5960)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }

  // ==================== 工具 ====================

  /// 纯数字链码 → 带连字符展示（serviceCode-剩余15位，如 000000-000026477599999）
  static String _hyphenCode(String code) {
    final String digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 21) {
      return '${digits.substring(0, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  /// 资源项名称：resourceName 为空时回退「资源N」，再回退类型 label
  static String _resourceTitle(ScanResource resource) {
    final String name = (resource.resourceName ?? '').trim();
    if (name.isNotEmpty) return name;
    final int? no = resource.resourceNo;
    if (no != null && no > 0) return '资源$no';
    return resource.type.label;
  }

  /// 时长（秒）→ 可读文本，如 90 → 1:30
  static String _durationText(num? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final int total = seconds.toInt();
    final int hour = total ~/ 3600;
    final int minute = (total % 3600) ~/ 60;
    final int sec = total % 60;
    if (hour > 0) {
      return '$hour:${minute.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$minute:${sec.toString().padLeft(2, '0')}';
  }
}
