import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'package:fmlink/cache/cache_record.dart';
import 'package:fmlink/cache/cache_service.dart';
import 'package:fmlink/cache/local_media_server.dart';
import 'package:fmlink/resource/offline_source.dart';
import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/network_info_util.dart';
import 'package:fmlink/screens/resource/widgets/audio_player_view.dart';
import 'package:fmlink/screens/resource/widgets/center_column.dart';
import 'package:fmlink/screens/resource/widgets/chain_code_sheet.dart';
import 'package:fmlink/screens/resource/widgets/cover_image.dart';
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
/// 点赞：调用 /target-goods/app/v1/resource/like（点赞）与
/// /target-goods/app/v1/resource/unlike（取消点赞），需登录。
///
/// 路由参数（extra）：
/// - isliCode：当前链码（纯数字）
/// - fromScan：是否由扫码进入
/// - versionCode：版本号（可空）
/// - startIndex：初始展示的资源下标
class ResourcePlayScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const ResourcePlayScreen({super.key, required this.extra});

  @override
  State<ResourcePlayScreen> createState() => _ResourcePlayScreenState();
}

class _ResourcePlayScreenState extends State<ResourcePlayScreen> {
  final ResourceService _service = ResourceService();

  late String _isliCode;
  late bool _fromScan;
  String? _versionCode;
  late int _startIndex;

  bool _loading = true;
  String? _error;
  SourceScanData? _data;
  List<ScanResource> _resources = const [];
  int _index = 0;

  /// 是否处于离线（本地缓存）模式：无网络或接口失败时用本地已缓存资源兜底
  bool _offline = false;

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
    CacheService().addListener(_onCacheChanged);
    _load();
  }

  @override
  void dispose() {
    CacheService().removeListener(_onCacheChanged);
    _hideTimer?.cancel();
    _restoreSystemUi(); // 兜底恢复系统状态栏/导航栏，避免全屏退出时残留沉浸式
    _pageController?.dispose();
    _disposeMedia();
    super.dispose();
  }

  /// 缓存状态变化（下载进度/完成/删除）时刷新缓存按钮
  void _onCacheChanged() {
    if (mounted) setState(() {});
  }

  // ==================== 数据加载 ====================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // 缓存元数据按账号隔离：进入页面先对齐当前账号（登录/退出/切号后重新加载）
    await CacheService().syncAccount();
    if (!mounted) return;

    // 无网络（飞行模式等）：直接走本地缓存，避免等待接口超时且保证已下载资源可播放
    final NetworkType net = await NetworkInfoUtil.getNetworkType();
    if (net == NetworkType.none) {
      if (await _loadOffline()) return;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '当前离线且无本地缓存，请联网后重试';
      });
      return;
    }

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
          // 接口失败（含无网络导致的请求失败）：若本地有缓存则降级为离线播放
          if (await _loadOffline()) return;
          if (!mounted) return;
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
        _offline = false;
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
      // 网络异常同样优先降级为本地缓存播放
      if (await _loadOffline()) return;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络异常，请重试';
      });
    }
  }

  /// 离线兜底：用本地已缓存资源构造资源列表（各资源视图本地优先，可直接播放）
  ///
  /// 返回是否成功加载（无本地缓存时返回 false，由调用方决定错误提示）
  Future<bool> _loadOffline() async {
    final List<CacheRecord> records =
        CacheService().cachedByIsli(_isliCode, versionCode: _versionCode);
    final SourceScanData? data = buildOfflineScanData(
      records,
      isliCode: _isliCode,
      versionCode: _versionCode,
    );
    if (data == null) return false;

    final List<ScanResource> all = data.currentResources;
    if (all.isEmpty) return false;

    _index = _startIndex < all.length ? _startIndex : 0;
    _pageController?.dispose();
    _pageController = PageController(initialPage: _index);
    if (!mounted) return true;
    setState(() {
      _offline = true;
      _data = data;
      _resources = all;
      _pageIndex = 1;
      _hasMore = false; // 离线仅能展示已缓存资源，无更多分页
      _loadingMore = false;
      _loadMoreFailed = false;
      _loading = false;
      _error = null;
    });
    _scheduleHide();
    _ensureMedia();
    EasyLoading.showToast('离线模式：已加载 ${all.length} 个已缓存资源');
    return true;
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
    // 离线模式：只展示已缓存资源，不再请求网络
    if (_offline) return;
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
  ///
  /// 本地优先：当前资源有已完成的本地缓存时，直接播放本地文件，不加载网络；
  /// 本地初始化失败（文件损坏 / 平台不支持本地播放）时自动回退网络地址，
  /// 避免已下载资源反而无法播放。
  Future<void> _ensureMedia() async {
    _disposeMedia();
    // 每次资源成为当前项都记一次访问（账号维度元数据）
    _markCurrentAccessed();
    if (!_currentIsMedia) return;
    final ScanResource r = _current!;

    // 候选控制器：本地缓存优先，网络地址兜底
    final List<VideoPlayerController> candidates = <VideoPlayerController>[];
    final String? localPath = _localPathFor(r);
    if (localPath != null && localPath.isNotEmpty) {
      candidates
          .add(await _localController(CacheService().recordFor(r), localPath));
    }
    final String url = _httpsUrl(r.cleanAddress);
    if (url.isNotEmpty) {
      candidates.add(VideoPlayerController.networkUrl(Uri.parse(url)));
    }
    if (candidates.isEmpty) return; // 无地址场景由内容区兜底

    for (final VideoPlayerController vc in candidates) {
      vc.addListener(_onMediaTick);
      _vc = vc;
      setState(() {});
      try {
        await vc.initialize();
        if (!mounted || _vc != vc) return;
        setState(() => _vcInitialized = true);
        await vc.play();
        return;
      } catch (e) {
        if (!mounted) return;
        print('媒体初始化失败: ${vc.dataSource} $e');
        vc.removeListener(_onMediaTick);
        await vc.dispose();
        if (_vc == vc) _vc = null;
      }
    }
    if (!mounted) return;
    setState(() => _vcFailed = true);
  }

  /// 记录一次资源访问（播放/打开）：写当前账号的访问记录，便于后续统计与排序
  void _markCurrentAccessed() {
    final ScanResource? r = _current;
    if (r == null) return;
    final CacheRecord? cache = CacheService().recordFor(r);
    if (cache == null || !cache.isCompleted) return;
    CacheService().touchAccess(cache);
  }

  /// 本地缓存对应的播放控制器
  ///
  /// HLS(m3u8) 走回环 HTTP：播放器需以播放列表地址为基准解析相对路径的分片与密钥，
  /// 直接用 file:// 在部分平台会失败（如 OHOS 端会被转成 fd://，失去基准地址）；
  /// 其它资源直接用 file:// 播放，少一层转发效率更高。
  Future<VideoPlayerController> _localController(
      CacheRecord? cache, String localPath) async {
    if (cache != null && cache.isHlsLocal) {
      final String? localUrl =
          await LocalMediaServer.instance.urlForLocalPath(localPath);
      if (localUrl != null && localUrl.isNotEmpty) {
        print('HLS本地播放: $localUrl');
        return VideoPlayerController.networkUrl(Uri.parse(localUrl));
      }
    }
    return VideoPlayerController.file(File(localPath));
  }

  /// 当前资源的本地缓存路径（已缓存且文件存在时返回，否则 null）
  ///
  /// HLS(m3u8) 视频的本地路径为分段目录下的 index.m3u8 入口，
  /// 路径解析统一交给 CacheService 处理（兼容容器路径迁移）。
  String? _localPathFor(ScanResource r) {
    final CacheRecord? cache = CacheService().recordFor(r);
    if (cache == null) return null;
    return CacheService().localPathFor(cache);
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

  Future<void> _toggleLike() async {
    final ScanResource? r = _current;
    if (r == null) return;

    // 点赞需登录：未登录先跳转登录页
    final bool loggedIn = await UserService().checkLoginStatus();
    if (!loggedIn) {
      if (!mounted) return;
      await context.push('/login');
      if (!mounted) return;
      final bool loggedAfter = await UserService().checkLoginStatus();
      if (!loggedAfter) return;
    }

    // 冷启动后重新水合 token，并取用户 unificationId
    await UserService().refreshToken();
    final String unificationId = await UserService().getUnificationId();
    if (unificationId.isEmpty) {
      EasyLoading.showToast('获取用户信息失败，请重新登录');
      return;
    }

    final SourceScanData? data = _data;
    final String goodsId = data?.goodsId ?? '';
    final String resourceId = r.id?.toString() ?? '';
    final String resourceOldId = r.resourceId ?? '';
    final String targetIdentifier = data?.currentTarget?.targetIdentifier ?? '';
    if (goodsId.isEmpty ||
        resourceId.isEmpty ||
        resourceOldId.isEmpty ||
        targetIdentifier.isEmpty) {
      EasyLoading.showToast('资源信息缺失，无法点赞');
      return;
    }

    final bool liked = r.hasLike == true;
    final Map<String, dynamic> res = liked
        ? await _service.unlikeResource(
            goodsId: goodsId,
            resourceId: resourceId,
            resourceOldId: resourceOldId,
            targetIdentifier: targetIdentifier,
            unificationId: unificationId,
          )
        : await _service.likeResource(
            goodsId: goodsId,
            resourceId: resourceId,
            resourceOldId: resourceOldId,
            targetIdentifier: targetIdentifier,
            unificationId: unificationId,
          );
    if (!mounted) return;
    if (res['status'] == true) {
      setState(() {
        final int count = r.likeCount ?? 0;
        r.raw['hasLike'] = !liked;
        r.raw['likeCount'] = liked ? (count > 0 ? count - 1 : 0) : count + 1;
      });
      EasyLoading.showToast(liked ? '已取消点赞' : '点赞成功');
    } else {
      EasyLoading.showToast(res['msg']?.toString() ?? '操作失败');
    }
  }

  /// 缓存当前资源（含网络判断与移动网络确认）
  Future<void> _cacheCurrent() async {
    final ScanResource? r = _current;
    if (r == null) return;
    final SourceScanData? data = _data;
    if (data == null) return;

    final CacheAddResult result = await CacheService().addToCache(
      r,
      data,
      isliCode: _isliCode,
      resourceIndex: _index,
    );
    if (!mounted) return;

    switch (result) {
      case CacheAddResult.alreadyCached:
        // 已缓存：提供删除入口
        _confirmRemoveCache(r);
        break;
      case CacheAddResult.alreadyQueued:
        EasyLoading.showToast('已在缓存队列');
        break;
      case CacheAddResult.added:
        EasyLoading.showToast('已加入缓存队列');
        break;
      case CacheAddResult.reused:
        // 命中全局共享文件本体：切换账号后无需重新下载
        EasyLoading.showToast('已复用本地缓存文件');
        break;
      case CacheAddResult.needConfirm:
        _confirmCellularDownload();
        break;
      case CacheAddResult.noAddress:
        EasyLoading.showToast('该资源暂无可缓存地址');
        break;
      case CacheAddResult.noPermission:
        EasyLoading.showToast('购买后可离线缓存');
        break;
    }
  }

  /// 移动网络缓存确认弹窗
  Future<void> _confirmCellularDownload() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('移动网络缓存', style: TextStyle(fontSize: 16)),
        content: const Text('当前为移动网络，缓存将消耗较多流量，是否继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CacheService().confirmCellularAndStart();
    }
  }

  /// 已缓存资源：删除确认
  Future<void> _confirmRemoveCache(ScanResource r) async {
    final CacheRecord? cache = CacheService().recordFor(r);
    if (cache == null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除缓存', style: TextStyle(fontSize: 16)),
        content: Text('确定删除「${cache.resourceName}」的本地缓存吗？'),
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
      await CacheService().removeCache(cache.id!);
    }
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
          // 离线提示与上下控制栏一起显隐：常驻会遮挡文本/图片等资源内容
          if (_overlayVisible && _offline) _buildOfflineBadge(),
        ],
      ),
    );
  }

  /// 离线模式提示：明确告知当前仅展示已缓存资源
  ///
  /// 位于导航栏（高 64）下方，随控制栏一起显隐并自动隐藏
  Widget _buildOfflineBadge() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 64 + 4,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 13, color: Colors.white70),
                SizedBox(width: 4),
                Text(
                  '离线模式 · 仅显示已缓存资源',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
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

    final String? localPath = _localPathFor(r);

    switch (r.type) {
      case ResourceType.text:
        return TextView(
          url: _httpsUrl(r.cleanAddress),
          hasAddress: r.cleanAddress.isNotEmpty,
          localPath: localPath,
        );
      case ResourceType.image:
        return ImageView(
          url: _httpsUrl(r.cleanAddress),
          hasAddress: r.cleanAddress.isNotEmpty,
          localPath: localPath,
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
          coverUrls: _coverCandidates(r),
        );
      case ResourceType.model3d:
        return _Model3dCard(
          coverUrls: _coverCandidates(r),
          url: r.cleanAddress.isEmpty ? null : r.cleanAddress,
          localPath: localPath,
        );
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
    final double topInset = MediaQuery.paddingOf(context).top;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    // 顶部黑色渐变：从状态栏浓黑缓慢淡出到画面里，而不是在导航栏下沿戛然而止。
    // 用 5 段缓动 stop 保证曲线圆润，末端 alpha 归零无分割线；作用区向画面延伸
    // 120px，横屏时同样细腻。装饰层与导航栏分离，避免遮挡视频点击。
    const List<Color> fadeColors = <Color>[
      Color(0xE6000000),
      Color(0xB3000000),
      Color(0x73000000),
      Color(0x26000000),
      Color(0x00000000),
    ];
    const List<double> fadeStops = <double>[0.0, 0.14, 0.38, 0.68, 1.0];
    return <Widget>[
      // 顶部渐变装饰层
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: topInset + 64 + 120,
        child: IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: fadeColors,
                stops: fadeStops,
              ),
            ),
          ),
        ),
      ),
      // 顶部导航栏
      Positioned(
        top: 0,
        left: 0,
        right: 0,
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
      // 底部渐变装饰层（向上延伸 140px 缓慢淡出，不挡视频交互）
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: bottomInset + 52 + 140,
        child: IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: fadeColors,
                stops: fadeStops,
              ),
            ),
          ),
        ),
      ),
      // 底部操作栏：媒体控制条 + 操作栏
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
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
    // 缓存按钮三态：未缓存 / 缓存中 / 已缓存
    final CacheRecord? cache = r == null ? null : CacheService().recordFor(r);
    final CacheStatus? cacheStatus = cache?.statusEnum;
    final bool cacheActive = cacheStatus == CacheStatus.completed;
    final bool cacheBusy = cacheStatus == CacheStatus.downloading;
    final IconData cacheIcon;
    final String cacheLabel;
    if (cacheDisabled) {
      cacheIcon = Icons.download_outlined;
      cacheLabel = '缓存';
    } else if (cacheStatus == CacheStatus.completed) {
      cacheIcon = Icons.check_circle_outline;
      cacheLabel = '已缓存';
    } else if (cacheStatus == CacheStatus.downloading) {
      cacheIcon = Icons.downloading;
      cacheLabel = '缓存中';
    } else if (cacheStatus == CacheStatus.pending ||
        cacheStatus == CacheStatus.failed) {
      cacheIcon = Icons.schedule;
      cacheLabel = '待缓存';
    } else {
      cacheIcon = Icons.download_outlined;
      cacheLabel = '缓存';
    }
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
            cacheIcon,
            cacheLabel,
            _cacheCurrent,
            enabled: !cacheDisabled,
            active: cacheActive,
            activeColor: const Color(0xFF67C23A),
            busy: cacheBusy,
          ),
        ],
      ),
    );
  }

  Widget _opItem(IconData icon, String label, VoidCallback onTap,
      {bool active = false,
      bool enabled = true,
      bool busy = false,
      Color activeColor = const Color(0xFFFF6B6B)}) {
    final Color color = !enabled
        ? Colors.white24
        : active
            ? activeColor
            : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              : Icon(icon, color: color, size: 22),
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

/// Web 资源：高斯模糊封面背景 + 深色玻璃信息卡 + 进入独立 webview
class _WebCard extends StatelessWidget {
  final ScanResource resource;
  final String url;
  final bool hasAddress;
  final List<String> coverUrls;

  const _WebCard({
    required this.resource,
    required this.url,
    required this.hasAddress,
    required this.coverUrls,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 背景：高斯模糊封面 + 暗色渐变遮罩（与音频视图一致），避免纯白过亮
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: CoverImage(
            urls: coverUrls,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            placeholder: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF1B1C22)),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x59000000), Color(0xE6000000)],
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.all(40),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xD91E2229),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
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
                    color: Colors.white10,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '网页类型资源 · 在线浏览',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 10),
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
        ),
      ],
    );
  }
}

/// 3D 资源占位：高斯模糊封面背景 + 深色玻璃信息卡（详情页另行展示）
class _Model3dCard extends StatelessWidget {
  final List<String> coverUrls;
  final String? url;

  /// 本地已缓存的 zip 包路径（有则直接解压，跳过网络下载）
  final String? localPath;

  const _Model3dCard({required this.coverUrls, this.url, this.localPath});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 背景：高斯模糊封面 + 暗色渐变遮罩（与音频视图一致），避免纯白过亮
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: CoverImage(
            urls: coverUrls,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            placeholder: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF1B1C22)),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x59000000), Color(0xE6000000)],
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.all(40),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xD91E2229),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
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
                    color: Colors.white10,
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
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '3D 展示功能开发中',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => context
                      .push(kResourceModel3dRoute, extra: <String, dynamic>{
                    'url': url,
                    'localZipPath': localPath,
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 10),
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
        ),
      ],
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
