import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/screens/resource/widgets/audio_player_view.dart';
import 'package:fmlink/screens/resource/widgets/center_column.dart';
import 'package:fmlink/screens/resource/widgets/chain_code_sheet.dart';
import 'package:fmlink/screens/resource/widgets/image_view.dart';
import 'package:fmlink/screens/resource/widgets/text_view.dart';
import 'package:fmlink/screens/resource/widgets/video_player_view.dart';

/// 资源播放页
///
/// 深色沉浸式页面：内容区按资源类型渲染（文本/图片/视频/音频/web/3D），
/// 支持左右滑动切换当前源的多个资源；顶部导航栏与底部操作栏
/// 点击切换显隐并自动隐藏。
///
/// 音频播放方案：与视频一致使用 video_player（方案 B）。
/// 点赞为本地状态（计数/高亮来自接口 likeCount/hasLike，接口待接入）。
///
/// 路由参数（extra）：
/// - isliCode：当前链码（纯数字）
/// - fromScan：是否由扫码进入
/// - versionCode：版本号（可空）
/// - startIndex：初始展示的资源下标
class ResourcePlayScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const ResourcePlayScreen({Key? key, required this.extra}) : super(key: key);

  @override
  State<ResourcePlayScreen> createState() => _ResourcePlayScreenState();
}

class _ResourcePlayScreenState extends State<ResourcePlayScreen> {
  final ResourceService _service = ResourceService();
  final ApiService _apiService = ApiService();

  late String _isliCode;
  late bool _fromScan;
  String? _versionCode;
  late int _startIndex;

  bool _loading = true;
  String? _error;
  SourceScanData? _data;
  List<ScanResource> _resources = const [];
  int _index = 0;

  /// 分页：每次请求 20 条，target.resources 按页返回
  static const int _pageSize = 20;

  /// 当前已加载到的页码
  int _pageIndex = 1;

  /// 是否还有更多资源（依据 target.resourceCount 与已加载数判断）
  bool _hasMore = true;

  /// 是否正在加载下一页（防重入）
  bool _loadingMore = false;

  /// 加载更多是否失败（末尾占位页可点击重试）
  bool _loadMoreFailed = false;

  /// 导航栏/操作栏显隐
  bool _overlayVisible = true;
  Timer? _hideTimer;

  /// 当前媒体播放器（视频/音频），由本页统一管理
  VideoPlayerController? _vc;
  bool _vcInitialized = false;
  bool _vcFailed = false;

  /// 资源分页控制器：以 startIndex 作为初始页，进入时定位到指定资源
  PageController? _pageController;

  ScanResource? get _current =>
      (_resources.isNotEmpty && _index < _resources.length)
          ? _resources[_index]
          : null;

  bool get _currentIsMedia {
    final ScanResource? r = _current;
    return r != null &&
        (r.type == ResourceType.video || r.type == ResourceType.audio);
  }

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> extra = widget.extra;
    _isliCode =
        (extra['isliCode']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    _fromScan = extra['fromScan'] == true;
    final String? version = extra['versionCode']?.toString();
    _versionCode = (version == null || version.isEmpty) ? null : version;
    final dynamic si = extra['startIndex'];
    _startIndex = si is int && si > 0 ? si : 0;
    _load();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _restoreSystemUi(); // 兜底恢复系统状态栏/导航栏，避免全屏退出时残留沉浸式
    _pageController?.dispose();
    _disposeMedia();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await UserService().refreshToken();
      // 分页拉取：数据为 target.resources 按页返回，逐页累加，
      // 直到覆盖目标起始下标（startIndex）或资源已加载完毕
      final List<ScanResource> acc = <ScanResource>[];
      SourceScanData? data;
      int page = 0;
      bool hasMore = true;
      while (hasMore && (acc.isEmpty || acc.length <= _startIndex)) {
        page++;
        final Map<String, dynamic> res = await _service.fetchSourceScan(
          _isliCode,
          pageIndex: page,
          pageSize: _pageSize,
          fromScan: _fromScan,
          versionCode: _versionCode,
        );
        if (!mounted) return;
        if (res['status'] != true || res['data'] == null) {
          setState(() {
            _loading = false;
            _error = res['msg']?.toString() ?? '获取资源失败';
          });
          return;
        }
        data = SourceScanData.fromJson(res['data'] as Map<String, dynamic>);
        if (_versionCode == null && data.versionCode != null) {
          _versionCode = data.versionCode!.toString();
        }
        final List<ScanResource> more = data.currentResources;
        acc.addAll(more);
        hasMore = more.isNotEmpty && _hasMoreResources(data, acc.length);
      }
      final List<ScanResource> all = acc;
      if (all.isNotEmpty) {
        _index = _startIndex < all.length ? _startIndex : 0;
      } else {
        _index = 0;
      }
      // 重建分页控制器：以当前 _index 作为初始页（加载中已卸载旧的 PageView，此处可安全 dispose）
      _pageController?.dispose();
      _pageController = PageController(initialPage: _index);
      setState(() {
        _data = data;
        _resources = all;
        _pageIndex = page;
        _hasMore = hasMore;
        _loadingMore = false;
        _loadMoreFailed = false;
        _loading = false;
      });
      _scheduleHide();
      _ensureMedia();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络异常，请重试';
      });
    }
  }

  /// 依据后端返回判断是否还有更多：优先使用 target.resourceCount；
  /// 接口未返回总数时，以「当前页是否已满」兜底判断
  bool _hasMoreResources(SourceScanData data, int loaded) {
    final int? total = data.currentTarget?.resourceCount;
    if (total != null && total > 0) return loaded < total;
    return loaded >= _pageSize;
  }

  /// 左滑到末尾占位页时加载下一页资源（追加到 _resources）
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      await UserService().refreshToken();
      final Map<String, dynamic> res = await _service.fetchSourceScan(
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
      final SourceScanData data =
          SourceScanData.fromJson(res['data'] as Map<String, dynamic>);
      final List<ScanResource> more = data.currentResources;
      final int before = _resources.length;
      setState(() {
        _pageIndex++;
        _data = data;
        _resources = <ScanResource>[..._resources, ...more];
        _loadingMore = false;
        _hasMore =
            more.isNotEmpty && _hasMoreResources(data, _resources.length);
      });
      // 用户当前正停留在原来的「加载更多」占位页：加载完成后该位置已被新资源填充，
      // 同步切换当前资源，实现左滑接续浏览
      final int cur = (_pageController?.hasClients ?? false)
          ? (_pageController!.page?.round() ?? -1)
          : -1;
      if (mounted && cur >= before && cur < _resources.length) {
        setState(() {
          _index = cur;
          _overlayVisible = true;
        });
        _scheduleHide();
        _ensureMedia();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  // ==================== 媒体控制 ====================

  void _disposeMedia() {
    _vc?.removeListener(_onMediaTick);
    _vc?.dispose();
    _vc = null;
    _vcInitialized = false;
    _vcFailed = false;
  }

  void _onMediaTick() {
    if (mounted) setState(() {});
  }

  /// 按当前资源初始化媒体控制器（仅视频/音频；其它类型仅释放）
  Future<void> _ensureMedia() async {
    _disposeMedia();
    if (!_currentIsMedia) return;
    final ScanResource r = _current!;
    final String url = _httpsUrl(r.cleanAddress);
    if (url.isEmpty) return; // 无地址场景由内容区兜底
    final VideoPlayerController vc =
        VideoPlayerController.networkUrl(Uri.parse(url));
    vc.addListener(_onMediaTick);
    _vc = vc;
    setState(() {});
    try {
      await vc.initialize();
      if (!mounted || _vc != vc) return;
      setState(() => _vcInitialized = true);
      await vc.play();
    } catch (e) {
      if (!mounted || _vc != vc) return;
      setState(() => _vcFailed = true);
    }
  }

  // ==================== 显隐控制 ====================

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_overlayVisible) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ==================== 行为 ====================

  void _onPageChanged(int index) {
    // 滑到末尾「加载更多」占位页：触发下一页加载（占位页本身不产生媒体）
    if (_hasMore && index >= _resources.length) {
      _loadMore();
      return;
    }
    if (index == _index) return;
    setState(() {
      _index = index;
      _overlayVisible = true;
    });
    _scheduleHide();
    _ensureMedia();
  }

  // ==================== 全屏系统栏控制 ====================

  /// 退出沉浸式：恢复系统状态栏/导航栏显示
  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 视频全屏状态变化：全屏时隐藏页面导航/操作栏并暂停自动隐藏，
  /// 退出全屏时恢复页面导航/操作栏并重新开始自动隐藏
  void _onVideoFullscreenChanged(bool fullscreen) {
    if (fullscreen) {
      _hideTimer?.cancel();
      setState(() => _overlayVisible = false);
    } else {
      setState(() => _overlayVisible = true);
      _scheduleHide();
    }
  }

  /// 封面 URL 候选链：资源海报 resourcePoster → 图书封面 goodsImage，
  /// 每个 URL 若为 https 再补一个 http 变体（部分服务仅支持 http，避免强制 https 加载失败）
  List<String> _coverCandidates(ScanResource r) {
    final List<String> list = <String>[];
    for (final String u in <String>[
      cleanUrl(r.resourcePoster).trim(),
      cleanUrl(_data?.goodsImage).trim(),
    ]) {
      if (u.isEmpty || list.contains(u)) continue;
      list.add(u);
      if (u.startsWith('https://')) {
        list.add('http://${u.substring('https://'.length)}');
      }
    }
    return list;
  }

  Future<void> _openChainList() async {
    final SourceScanData? data = _data;
    if (data == null) return;
    final String serviceCode =
        data.serviceCode ?? (data.source?.serviceCode ?? '');
    final String prefixCode =
        data.prefixCode ?? (data.source?.prefixCode ?? '');
    if (serviceCode.isEmpty || prefixCode.isEmpty) {
      EasyLoading.showToast('未获取到链码信息');
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
    if (selection.isliCode == _isliCode) return;
    context.pushReplacement(kResourcePlayRoute, extra: <String, dynamic>{
      'isliCode': selection.isliCode,
      'fromScan': _fromScan,
      'versionCode': _versionCode,
      'startIndex': 0,
    });
  }

  void _toggleLike() {
    final ScanResource? r = _current;
    if (r == null) return;
    // TODO(点赞接口): 后端点赞/取消接口待接入后替换为真实请求；
    // 目前保持展示接口返回的 likeCount/hasLike。
    EasyLoading.showToast('点赞功能开发中');
  }

  Future<void> _cacheCurrent() async {
    final ScanResource? r = _current;
    if (r == null) return;
    final String url = _httpsUrl(r.cleanAddress);
    if (url.isEmpty) {
      EasyLoading.showToast('该资源暂无可缓存地址');
      return;
    }
    try {
      EasyLoading.show(status: '缓存中...');
      final Directory dir = await getApplicationDocumentsDirectory();
      final String file = _cacheFileName(r, url);
      await _apiService.download(url, '${dir.path}/$file');
      EasyLoading.dismiss();
      if (mounted) EasyLoading.showToast('已缓存到本地');
    } catch (e) {
      EasyLoading.dismiss();
      if (mounted) EasyLoading.showToast('缓存失败');
    }
  }

  String _cacheFileName(ScanResource r, String url) {
    String name = url.split('?').first.split('/').last.trim();
    if (name.isEmpty || name.contains('.')) {
      final String? suffix = r.resourceSuffix;
      name = 'resource_${DateTime.now().millisecondsSinceEpoch}'
          '${(suffix == null || suffix.isEmpty) ? '' : '.$suffix'}';
    }
    return name;
  }

  void _openMore() {
    final SourceScanData? data = _data;
    final int total = _resources.length;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (data != null && data.needPurchase)
                _sheetItem(
                  icon: Icons.lock_open_outlined,
                  label: '购买当前资源',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openPurchase();
                  },
                ),
              if (total > 1)
                _sheetItem(
                  icon: Icons.list_alt_outlined,
                  label: '资源列表（共 $total 个）',
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(kResourceListRoute, extra: <String, dynamic>{
                      'isliCode': _isliCode,
                      'fromScan': _fromScan,
                      'versionCode': _versionCode,
                    });
                  },
                ),
              _sheetItem(
                icon: Icons.info_outline,
                label: '源详情',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(kResourceSourceDetailRoute,
                      extra: <String, dynamic>{
                        'data': data?.raw ?? const <String, dynamic>{},
                        'isliCode': _isliCode,
                        'goodsName': data?.goodsName ?? '',
                      });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF333333), size: 22),
      title: Text(
        label,
        style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
      ),
      trailing:
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC0C4CC)),
      onTap: onTap,
    );
  }

  Future<void> _openPurchase() async {
    final SourceScanData? data = _data;
    if (data == null) return;
    final bool? ok = await context.push<bool>(
      kPurchaseRoute,
      extra: ResourceEntry.buildPurchaseParams(
        data,
        sourceName:
            data.source?.sourceNo != null ? '链码${data.source!.sourceNo}' : null,
      ),
    );
    if (ok == true && mounted) {
      _load();
    }
  }

  // ==================== 工具 ====================

  /// http → https 并去掉端口；同时去除反引号与首尾空白
  static String _httpsUrl(String? raw) {
    String url = cleanUrl(raw).trim();
    if (url.toLowerCase().startsWith('http://')) {
      url = url.replaceFirst(
          RegExp(r'^http://', caseSensitive: false), 'https://');
      url = url.replaceFirst(
          RegExp(r'^(https://[^/?#]+):\d+(?=/|$|#|\?)'), r'$1');
    }
    return url;
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    // 本页为黑色沉浸式页面：状态栏图标/文字使用亮色，避免黑色背景下不可见
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    if (_error != null) {
      return CenterColumn(
        icon: Icons.search_off,
        text: _error!,
        button: _retryButton(),
      );
    }
    if (_resources.isEmpty) {
      return CenterColumn(
        icon: Icons.inbox_outlined,
        text: '该链码暂无可播放资源',
        button: _retryButton(),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleOverlay,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildPages()),
          if (_overlayVisible) ..._buildOverlays(),
        ],
      ),
    );
  }

  Widget _buildPages() {
    // 还有更多时末尾追加一页「加载更多」占位页：左滑到该页即触发下一页加载，
    // 加载完成后占位页被新资源替换，当前停留位置正好接续到下一页首个资源
    final int itemCount = _resources.length + (_hasMore ? 1 : 0);
    return PageView.builder(
      controller: _pageController,
      itemCount: itemCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (BuildContext ctx, int i) {
        if (i >= _resources.length) {
          return _buildLoadMorePlaceholder();
        }
        final ScanResource r = _resources[i];
        return _buildResourceContent(r);
      },
    );
  }

  /// 末尾「左滑加载更多」占位页：等待左滑 / 加载中 / 失败点击重试
  Widget _buildLoadMorePlaceholder() {
    final Widget body;
    if (_loadingMore) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: const <Widget>[
          CircularProgressIndicator(color: Colors.white54),
          SizedBox(height: 12),
          Text(
            '加载更多资源...',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    } else if (_loadMoreFailed) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 32, color: Colors.white54),
          const SizedBox(height: 10),
          const Text(
            '加载失败',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _loadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                '点击重试',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: const <Widget>[
          Icon(Icons.swipe_left, size: 32, color: Colors.white38),
          SizedBox(height: 10),
          Text(
            '左滑加载更多资源',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }
    return Center(child: body);
  }

  Widget _buildResourceContent(ScanResource r) {
    final SourceScanData? data = _data;
    final bool locked = r.cleanAddress.isEmpty &&
        data != null &&
        !data.isSourceAccessible &&
        r.type != ResourceType.unknown;
    if (locked) {
      return _LockView(onPurchase: _openPurchase);
    }

    switch (r.type) {
      case ResourceType.text:
        return TextView(
          url: _httpsUrl(r.cleanAddress),
          hasAddress: r.cleanAddress.isNotEmpty,
        );
      case ResourceType.image:
        return ImageView(
          url: _httpsUrl(r.cleanAddress),
          hasAddress: r.cleanAddress.isNotEmpty,
        );
      case ResourceType.video:
        return _buildMediaView(r, withPlayerWidget: true);
      case ResourceType.audio:
        return _buildMediaView(r, withPlayerWidget: false);
      case ResourceType.web:
        return _WebCard(
          resource: r,
          url: _httpsUrl(r.cleanAddress),
          hasAddress: r.cleanAddress.isNotEmpty,
        );
      case ResourceType.model3d:
        return const _Model3dCard();
      case ResourceType.unknown:
        return const CenterColumn(icon: Icons.help_outline, text: '暂不支持该资源类型');
    }
  }

  Widget _buildMediaView(ScanResource r, {required bool withPlayerWidget}) {
    if (r.cleanAddress.isEmpty) {
      return const CenterColumn(
          icon: Icons.play_disabled_outlined, text: '该资源暂未提供地址');
    }
    if (_vcFailed) {
      return const CenterColumn(icon: Icons.error_outline, text: '媒体加载失败');
    }
    final VideoPlayerController? vc = _vc;
    if (vc == null || !_vcInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    if (!withPlayerWidget) {
      // 音频：封面模糊背景 + 封面卡片 + 进度条 + 播放控制（循环/倍速由组件自持）
      return AudioPlayerView(
        controller: vc,
        resource: r,
        coverUrls: _coverCandidates(r),
      );
    }
    // 视频：等比/全屏、沉浸式、控制栏显隐均由组件自持，通过回调联动页面导航/操作栏
    return VideoPlayerView(
      controller: vc,
      pageControlsVisible: _overlayVisible,
      onTogglePageControls: _toggleOverlay,
      onInteract: _scheduleHide,
      onFullscreenChanged: _onVideoFullscreenChanged,
    );
  }

  Widget _retryButton() {
    return GestureDetector(
      onTap: _load,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          '重新加载',
          style: TextStyle(fontSize: 13, color: Colors.white),
        ),
      ),
    );
  }

  List<Widget> _buildOverlays() {
    return <Widget>[
      // 顶部导航栏
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(child: _navCenter()),
                  IconButton(
                    icon: const Icon(Icons.more_horiz,
                        color: Colors.white, size: 22),
                    onPressed: _openMore,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // 底部：媒体控制条 + 操作栏
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // 底部操作栏始终显示；视频/音频控制组件均内嵌于各自媒体视图
              children: <Widget>[
                _buildOpBar(),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _navCenter() {
    final ScanResource? r = _current;
    final SourceScanData? data = _data;
    final List<String> parts = <String>[];
    final int? page = data?.source?.bookPageNo;
    final int? sourceNo = data?.source?.sourceNo;
    final int? resourceNo = r?.resourceNo;
    if (page != null && page > 0) parts.add('第$page页');
    if (sourceNo != null && sourceNo > 0) parts.add('链码$sourceNo');
    if (resourceNo != null && resourceNo > 0) parts.add('资源$resourceNo');
    final String sub = parts.join(' | ');

    final String title;
    if (r == null) {
      title = '';
    } else if (r.resourceName != null && r.resourceName!.isNotEmpty) {
      title = r.resourceName!;
    } else {
      title = '资源${r.resourceNo ?? (_index + 1)}';
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
      ],
    );
  }

  /// 底部操作栏：链码列表 / 点赞 / 缓存
  Widget _buildOpBar() {
    final ScanResource? r = _current;
    final int likeCount = r?.likeCount ?? 0;
    final bool liked = r?.hasLike == true;
    // 网页资源为在线浏览，不支持缓存到本地
    final bool cacheDisabled = r?.type == ResourceType.web;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _opItem(Icons.view_list_outlined, '链码列表', _openChainList),
          _opItem(
            liked ? Icons.favorite : Icons.favorite_border,
            likeCount > 0 ? '$likeCount' : '点赞',
            _toggleLike,
            active: liked,
          ),
          _opItem(
            Icons.download_outlined,
            '缓存',
            _cacheCurrent,
            enabled: !cacheDisabled,
          ),
        ],
      ),
    );
  }

  Widget _opItem(IconData icon, String label, VoidCallback onTap,
      {bool active = false, bool enabled = true}) {
    final Color color = !enabled
        ? Colors.white24
        : active
            ? const Color(0xFFFF6B6B)
            : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

/// Web 资源：基本信息卡 + 进入独立 webview
class _WebCard extends StatelessWidget {
  final ScanResource resource;
  final String url;
  final bool hasAddress;

  const _WebCard({
    required this.resource,
    required this.url,
    required this.hasAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset(
                'assets/icons/resource/html_review_icon.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              resource.resourceName ?? '网页资源',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '网页类型资源 · 在线浏览',
              style: TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                if (!hasAddress) {
                  EasyLoading.showToast('该资源暂无地址');
                  return;
                }
                context.push('/webview?url=${Uri.encodeComponent(url)}'
                    '&title=${Uri.encodeComponent(resource.resourceName ?? '网页')}');
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F7BFF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  '在网页中打开',
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3D 资源占位（详情页另行展示）
class _Model3dCard extends StatelessWidget {
  const _Model3dCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset(
                'assets/icons/resource/obj_review_icon.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '3D 模型资源',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '3D 展示功能开发中',
              style: TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => context.push(kResourceModel3dRoute),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F7BFF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  '进入 3D 模型页',
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 收费未解锁资源占位
class _LockView extends StatelessWidget {
  final VoidCallback onPurchase;

  const _LockView({required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 60, color: Colors.white38),
          const SizedBox(height: 12),
          const Text(
            '该资源为付费内容，购买后即可查看',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onPurchase,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF2F7BFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '购买后解锁',
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
