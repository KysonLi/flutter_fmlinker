import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:fmlink/widgets/default_state_view.dart';
import 'package:go_router/go_router.dart';

/// 源详情 / 资源详情页（同一页面、两种模式）
///
/// - 源列表 →「源详情」：extra 不含 fromPlay，请求
///   `GET /target-goods/app/v1/source/detail/:sourceIdentifier`
/// - 资源播放页底部「详情」→ 资源详情：extra.fromPlay = true，请求
///   `GET /target-goods/app/v1/resource/detail/:sourceIdentifier?resourceId=&resourceOldId=`
///
/// 两个接口 data 结构基本一致：
/// ```
/// {
///   shopInfo: {shopId, shopName, logo, goodsCount, ...},
///   sourceCount,                      // 链码总数
///   resourceCount,                    // 整书资源总数
///   goodsId, goodsName, goodsImage, goodsReadCount,
///   source: {sourceIdentifier, sourceNo, bookPageNo, resourceCount, ...},
///   // 仅资源详情：
///   resourceReadCount,
///   likeUsers: [{userHeadImgUrl}],
///   resource: {id, resourceId, resourceType, resourceName, resourceNo,
///              resourceSize, updateTime, hasLike, likeCount, ...},
/// }
/// ```
///
/// 内容自上而下：
/// 1. 源信息 / 资源信息：统计项为「上数值 + 下 icon&文案」
///    （资源 = 资源总数 或 资源序号/资源总数，页 = P页码，链码 = 序号/总数）
/// 2. 点赞行（仅资源详情）：首行头像 + 点赞总数（可点开名单）+ 点赞按钮
/// 3. 关联资源信息（仅资源详情）：阅读次数 / 资源大小 / 更新时间
/// 4. 链码信息：ISLI 编码
/// 5. 出版物信息：封面 / 书名 / 链码 | 资源 | 关联阅读
/// 6. 发布者信息：logo / 名称 / 出版物总数
class ResourceSourceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const ResourceSourceDetailScreen({super.key, required this.extra});

  @override
  State<ResourceSourceDetailScreen> createState() =>
      _ResourceSourceDetailScreenState();
}

class _ResourceSourceDetailScreenState
    extends State<ResourceSourceDetailScreen> {
  static const double _avatarSize = 30;

  final ResourceService _service = ResourceService();

  /// /source/scan 的 data（extra 传入），用于接口字段缺失时兜底
  late final SourceScanData _scanData;

  /// true = 资源详情（播放页进入）；false = 源详情（源列表进入）
  late final bool _resourceMode;

  /// 详情接口返回的 data
  Map<String, dynamic>? _detail;
  String? _error;

  bool _liked = false;
  int _likeCount = 0;
  List<Map<String, dynamic>> _likeUsers = const <Map<String, dynamic>>[];
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    final dynamic raw = widget.extra['data'];
    _scanData = SourceScanData.fromJson(
      raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{},
    );
    _resourceMode = widget.extra['fromPlay'] == true;
    _loadDetail();
  }

  // ==================== 详情数据 ====================

  Map<String, dynamic> get _source => _map(_detail?['source']);
  Map<String, dynamic> get _resource => _map(_detail?['resource']);
  Map<String, dynamic> get _shop => _map(_detail?['shopInfo']);

  /// 链码（接口返回已带连字符，兜底取 extra / scan 数据）
  String get _isliCode {
    final String code = _str(_source['sourceIdentifier']);
    if (code.isNotEmpty) return code;
    final String fromExtra = _str(widget.extra['isliCode']);
    if (fromExtra.isNotEmpty) return fromExtra;
    return _str(_scanData.source?.sourceIdentifier);
  }

  /// 请求用的链码参数（纯数字，由 isliDigits 归一）
  String get _requestCode {
    final String fromExtra = _str(widget.extra['isliCode']);
    if (fromExtra.isNotEmpty) return fromExtra;
    final String fromScan = _str(_scanData.source?.sourceIdentifier);
    if (fromScan.isNotEmpty) return fromScan;
    return _isliCode;
  }

  Map<String, dynamic> get _likeQuery => _map(widget.extra['likeQuery']);

  ScanResource? get _scanResource {
    final List<ScanResource> resources = _scanData.currentResources;
    if (resources.isEmpty) return null;
    final dynamic rawIndex = widget.extra['resourceIndex'];
    final int? index = rawIndex is int ? rawIndex : int.tryParse('$rawIndex');
    if (index != null && index >= 0 && index < resources.length) {
      return resources[index];
    }
    return resources.first;
  }

  String get _likeGoodsId => _firstNonEmpty(<String>[
        _str(_likeQuery['goodsId']),
        _str(_detail?['goodsId']),
        _scanData.goodsId,
      ]);

  String get _likeResourceId => _firstNonEmpty(<String>[
        _str(_likeQuery['resourceId']),
        _str(_resource['id']),
        _str(_scanResource?.id),
      ]);

  String get _likeResourceOldId => _firstNonEmpty(<String>[
        _str(_likeQuery['resourceOldId']),
        _str(_resource['resourceId']),
        _str(_scanResource?.resourceId),
      ]);

  String get _likeTargetIdentifier => _firstNonEmpty(<String>[
        _str(_likeQuery['targetIdentifier']),
        _str(_scanData.currentTarget?.targetIdentifier),
      ]);

  Future<void> _loadDetail() async {
    // 本页只用 EasyLoading 一个 loading（全局单例，不会叠加）
    EasyLoading.show(status: '加载中...');
    try {
      await UserService().refreshToken();
      final String uid = await UserService().getUnificationId();

      final Map<String, dynamic> res = _resourceMode
          ? await _service.fetchResourceDetail(
              sourceIdentifier: _requestCode,
              resourceId: _str(_likeQuery['resourceId']).isNotEmpty
                  ? _str(_likeQuery['resourceId'])
                  : _str(_scanResource?.id),
              resourceOldId: _str(_likeQuery['resourceOldId']).isNotEmpty
                  ? _str(_likeQuery['resourceOldId'])
                  : _str(_scanResource?.resourceId),
              unificationId: uid,
            )
          : await _service.fetchSourceDetail(
              sourceIdentifier: _requestCode,
              unificationId: uid,
            );

      if (!mounted) return;
      final dynamic data = res['data'];
      if (res['status'] == true && data is Map) {
        setState(() {
          _detail = data.cast<String, dynamic>();
          _error = null;
          _syncLikeState();
        });
        if (_resourceMode && _likeUsers.isEmpty) {
          // 详情未带点赞用户时补拉一次（只用于头像展示）
          await _loadLikeUsers();
        }
      } else {
        setState(() {
          _error = res['msg']?.toString() ?? '加载失败，请稍后重试';
        });
      }
    } catch (e) {
      debugPrint('加载源/资源详情失败: $e');
      if (!mounted) return;
      setState(() {
        _error = '加载失败，请稍后重试';
      });
    } finally {
      EasyLoading.dismiss();
    }
  }

  void _syncLikeState() {
    final dynamic rawUsers = _detail?['likeUsers'];
    _likeUsers = rawUsers is List
        ? rawUsers
            .whereType<Map>()
            .map((Map e) => e.cast<String, dynamic>())
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    _likeCount = _toInt(_resource['likeCount']) ?? _likeUsers.length;
    _liked = _toBool(_resource['hasLike']) ?? (_scanResource?.hasLike == true);
  }

  Future<void> _loadLikeUsers() async {
    final String goodsId = _likeGoodsId;
    final String resourceId = _likeResourceId;
    final String resourceOldId = _likeResourceOldId;
    final String targetIdentifier = _likeTargetIdentifier;
    if (goodsId.isEmpty ||
        resourceId.isEmpty ||
        resourceOldId.isEmpty ||
        targetIdentifier.isEmpty) {
      return;
    }
    try {
      final Map<String, dynamic> res = await _service.fetchResourceLikeUsers(
        goodsId: goodsId,
        resourceId: resourceId,
        resourceOldId: resourceOldId,
        targetIdentifier: targetIdentifier,
        pageIndex: 1,
        pageSize: 20,
      );
      if (!mounted) return;
      if (res['status'] == true) {
        final List<Map<String, dynamic>> users = _extractLikeUsers(res['data']);
        if (users.isNotEmpty) {
          setState(() {
            _likeUsers = users;
            if (_likeCount < users.length) _likeCount = users.length;
          });
        }
      }
    } catch (e) {
      debugPrint('加载点赞用户失败: $e');
    }
  }

  List<Map<String, dynamic>> _extractLikeUsers(dynamic data) {
    List<dynamic> items = const <dynamic>[];
    if (data is List) {
      items = data;
    } else if (data is Map) {
      for (final String key in const <String>[
        'likeUsers',
        'list',
        'records',
        'userList',
        'likeList',
        'rows',
        'data',
      ]) {
        final dynamic v = data[key];
        if (v is List) {
          items = v;
          break;
        }
      }
    }
    return items
        .whereType<Map>()
        .map((Map e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  // ==================== 点赞 ====================

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final String goodsId = _likeGoodsId;
    final String resourceId = _likeResourceId;
    final String resourceOldId = _likeResourceOldId;
    final String targetIdentifier = _likeTargetIdentifier;
    if (goodsId.isEmpty ||
        resourceId.isEmpty ||
        resourceOldId.isEmpty ||
        targetIdentifier.isEmpty) {
      EasyLoading.showToast('资源信息缺失，无法点赞');
      return;
    }

    bool loggedIn = await UserService().checkLoginStatus();
    if (!loggedIn) {
      if (!mounted) return;
      await context.push('/login');
      if (!mounted) return;
      loggedIn = await UserService().checkLoginStatus();
      if (!loggedIn) return;
    }

    await UserService().refreshToken();
    final String uid = await UserService().getUnificationId();
    if (uid.isEmpty) {
      EasyLoading.showToast('获取用户信息失败，请重新登录');
      return;
    }

    setState(() {
      _likeBusy = true;
    });
    try {
      final bool liked = _liked;
      final Map<String, dynamic> res = liked
          ? await _service.unlikeResource(
              goodsId: goodsId,
              resourceId: resourceId,
              resourceOldId: resourceOldId,
              targetIdentifier: targetIdentifier,
              unificationId: uid,
            )
          : await _service.likeResource(
              goodsId: goodsId,
              resourceId: resourceId,
              resourceOldId: resourceOldId,
              targetIdentifier: targetIdentifier,
              unificationId: uid,
            );
      if (!mounted) return;
      if (res['status'] == true) {
        setState(() {
          _liked = !liked;
          _likeCount =
              liked ? (_likeCount > 0 ? _likeCount - 1 : 0) : _likeCount + 1;
        });
        EasyLoading.showToast(liked ? '已取消点赞' : '点赞成功');
        await _loadLikeUsers();
      } else {
        EasyLoading.showToast(res['msg']?.toString() ?? '操作失败');
      }
    } catch (e) {
      debugPrint('点赞操作失败: $e');
      if (mounted) EasyLoading.showToast('操作失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _likeBusy = false;
        });
      }
    }
  }

  /// 点赞用户列表（头像 + 昵称，接口无昵称时显示「用户」）
  void _showLikeUsers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) => _LikeUsersSheet(
        title: '点赞用户 · $_likeCount',
        fetcher: () async {
          final String goodsId = _likeGoodsId;
          final String resourceId = _likeResourceId;
          final String resourceOldId = _likeResourceOldId;
          final String targetIdentifier = _likeTargetIdentifier;
          if (goodsId.isEmpty ||
              resourceId.isEmpty ||
              resourceOldId.isEmpty ||
              targetIdentifier.isEmpty) {
            return const <Map<String, dynamic>>[];
          }
          final Map<String, dynamic> res =
              await _service.fetchResourceLikeUsers(
            goodsId: goodsId,
            resourceId: resourceId,
            resourceOldId: resourceOldId,
            targetIdentifier: targetIdentifier,
            pageIndex: 1,
            pageSize: 50,
          );
          if (res['status'] != true) return const <Map<String, dynamic>>[];
          return _extractLikeUsers(res['data']);
        },
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _resourceMode ? '资源详情' : '源详情',
          style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return DefaultStateView.fromError(
        message: _error ?? '加载失败，请稍后重试',
        onRetry: () {
          setState(() {
            _error = null;
          });
          _loadDetail();
        },
      );
    }
    if (_detail == null) {
      // loading 由 EasyLoading 展示，这里留白避免出现第二个转圈
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _buildPrimaryCard(),
        if (_resourceMode) ...<Widget>[
          const SizedBox(height: 12),
          _buildLikeRow(),
          const SizedBox(height: 12),
          _buildRelatedCard(),
        ],
        const SizedBox(height: 12),
        _buildCodeCard(),
        const SizedBox(height: 12),
        _buildPublicationCard(),
        const SizedBox(height: 12),
        _buildPublisherCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 1. 源信息 / 资源信息
  Widget _buildPrimaryCard() {
    final int? sourceResourceCount = _toInt(_source['resourceCount']);
    final int? pageNo = _toInt(_source['bookPageNo']);
    final int? resourceNo = _toInt(_resource['resourceNo']);
    final ResourceType type = ResourceType.fromRaw(_resource['resourceType']);
    final String name = _str(_resource['resourceName']);

    final int? sourceNo = _toInt(_source['sourceNo']);
    final int? sourceTotal = _toInt(_detail?['sourceCount']);

    // 「资源」：源详情=资源总数；资源详情=资源序号/资源总数（总数作辅助信息）
    _Stat? resourceStat;
    if (_resourceMode && resourceNo != null && resourceNo > 0) {
      resourceStat = _Stat(
        value: '$resourceNo',
        suffix: sourceResourceCount != null && sourceResourceCount > 0
            ? ' / $sourceResourceCount'
            : null,
        icon: Icons.widgets_outlined,
        label: '资源',
      );
    } else if (sourceResourceCount != null && sourceResourceCount > 0) {
      resourceStat = _Stat(
        value: '$sourceResourceCount',
        icon: Icons.widgets_outlined,
        label: '资源',
      );
    }

    // 「页面」：P 作为辅助前缀 + 页码
    final _Stat? pageStat = pageNo != null && pageNo > 0
        ? _Stat(
            prefix: 'P',
            value: '$pageNo',
            icon: Icons.description_outlined,
            label: '页面',
          )
        : null;

    // 「链码」：序号 + /总数（总数作辅助信息）
    final _Stat? chainStat = sourceNo != null && sourceNo > 0
        ? _Stat(
            value: '$sourceNo',
            suffix: sourceTotal != null && sourceTotal > 0
                ? ' / $sourceTotal'
                : null,
            icon: Icons.qr_code_2,
            label: '链码',
          )
        : null;

    final List<_Stat> stats = <_Stat>[
      if (resourceStat != null) resourceStat,
      if (pageStat != null) pageStat,
      if (chainStat != null) chainStat,
    ];

    if (!_resourceMode) {
      return _card(title: '源信息', child: _buildStatBar(stats));
    }

    return _card(
      title: '资源信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            // 类型图标与资源名称（可能两行）垂直居中对齐
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ResourceTypeUi.color(type).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  ResourceTypeUi.icon(type),
                  size: 17,
                  color: ResourceTypeUi.color(type),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isEmpty ? '资源' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2329),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _buildStatBar(stats),
          ],
        ],
      ),
    );
  }

  /// 统计项：上排数值、下排 icon + 文字；整行等宽均分、居中
  Widget _buildStatBar(List<_Stat> stats) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        for (final _Stat stat in stats) Expanded(child: _buildStatItem(stat)),
      ],
    );
  }

  Widget _buildStatItem(_Stat stat) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              if (stat.prefix != null)
                TextSpan(text: stat.prefix, style: _statAuxStyle),
              TextSpan(text: stat.value, style: _statMainStyle),
              if (stat.suffix != null)
                TextSpan(text: stat.suffix, style: _statAuxStyle),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(stat.icon, size: 12, color: const Color(0xFF909399)),
            const SizedBox(width: 4),
            Text(
              stat.label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF909399)),
            ),
          ],
        ),
      ],
    );
  }

  /// 2. 点赞行：头像 + 点赞总数（点击看名单）+ 点赞/取消
  Widget _buildLikeRow() {
    return _card(
      title: '',
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (_likeUsers.isEmpty) {
                  return const Text(
                    '还没有人点赞',
                    style: TextStyle(fontSize: 12, color: Color(0xFF909399)),
                  );
                }
                const double gap = 6;
                final int capacity =
                    ((constraints.maxWidth + gap) / (_avatarSize + gap))
                        .floor()
                        .clamp(1, 12);
                final List<Map<String, dynamic>> shown =
                    _likeUsers.take(capacity).toList(growable: false);
                return Row(
                  children: <Widget>[
                    for (final Map<String, dynamic> user in shown)
                      Padding(
                        padding: const EdgeInsets.only(right: gap),
                        child: _avatar(user),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _likeCount > 0 ? _showLikeUsers : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '$_likeCount 人点赞',
                style: TextStyle(
                  fontSize: 12,
                  color: _likeCount > 0
                      ? const Color(0xFF409EFF)
                      : const Color(0xFF909399),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildLikeButton(),
        ],
      ),
    );
  }

  Widget _buildLikeButton() {
    final bool liked = _liked;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleLike,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: liked
              ? const Color(0xFFFF6B6B).withValues(alpha: 0.1)
              : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_likeBusy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color:
                    liked ? const Color(0xFFFF6B6B) : const Color(0xFF5B6470),
              ),
            const SizedBox(width: 4),
            Text(
              liked ? '已点赞' : '点赞',
              style: TextStyle(
                fontSize: 12,
                color:
                    liked ? const Color(0xFFFF6B6B) : const Color(0xFF5B6470),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> user) {
    final String url = cleanUrl(_avatarUrl(user));
    return ClipOval(
      child: SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: url.isEmpty
            ? Image.asset('assets/images/default_avatar.png', fit: BoxFit.cover)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (BuildContext context, String url) =>
                    Container(color: const Color(0xFFF0F2F5)),
                errorWidget: (BuildContext context, String url, Object error) =>
                    Image.asset('assets/images/default_avatar.png',
                        fit: BoxFit.cover),
              ),
      ),
    );
  }

  /// 3. 关联资源信息：阅读次数 / 资源大小 / 更新时间
  Widget _buildRelatedCard() {
    final String readCount = _text(_toInt(_detail?['resourceReadCount']));
    final String size = _sizeText(_toNum(_resource['resourceSize']));
    final String updateTime = _str(_resource['updateTime']);

    return _card(
      title: '关联资源信息',
      child: Column(
        children: <Widget>[
          _infoRow('阅读次数', readCount),
          _infoRow('资源大小', size),
          _infoRow('更新时间', updateTime),
        ].whereType<Padding>().toList(),
      ),
    );
  }

  /// 4. 链码信息
  Widget _buildCodeCard() {
    return _card(
      title: '链码信息',
      child: _infoRow('ISLI 编码', _hyphenCode(_isliCode)),
    );
  }

  /// 5. 出版物信息：封面 / 书名 / 链码 | 资源 | 关联阅读
  Widget _buildPublicationCard() {
    final String name = _firstNonEmpty(<String>[
      _str(_detail?['goodsName']),
      _scanData.goodsName ?? '',
      _str(widget.extra['goodsName']),
    ]);
    final String cover = _firstNonEmpty(<String>[
      _str(_detail?['goodsImage']),
      _scanData.goodsImage ?? '',
    ]);
    final int? sourceCount = _toInt(_detail?['sourceCount']);
    final int? resourceCount = _toInt(_detail?['resourceCount']);
    final String readCount = _text(_toInt(_detail?['goodsReadCount']));

    final List<String> stats = <String>[
      if (sourceCount != null && sourceCount > 0) '链码 $sourceCount',
      if (resourceCount != null && resourceCount > 0) '资源 $resourceCount',
      if (readCount.isNotEmpty) '关联阅读 $readCount',
    ];

    return _card(
      title: '出版物信息',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BookCover(imageUrl: cover, width: 56, height: 76),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isEmpty ? '未知出版物' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2329),
                    height: 1.4,
                  ),
                ),
                if (stats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      stats.join('  ·  '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF909399),
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 6. 发布者信息：logo / 名称 / 出版物总数
  Widget _buildPublisherCard() {
    final String name = _str(_shop['shopName']);
    final String logo = cleanUrl(_str(_shop['logo']));
    final String goodsCount = _text(_toInt(_shop['goodsCount']));

    if (name.isEmpty && logo.isEmpty) {
      return const SizedBox.shrink();
    }

    return _card(
      title: '发布者信息',
      child: Row(
        // 出版社 logo 多为长方形横幅，用等比 contain 展示，不做圆形裁切
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: logo.isEmpty
                ? Image.asset('assets/images/publisher_logo_default.png',
                    fit: BoxFit.contain)
                : CachedNetworkImage(
                    imageUrl: logo,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    placeholder: (BuildContext context, String url) =>
                        const SizedBox.shrink(),
                    errorWidget: (BuildContext context, String url,
                            Object error) =>
                        Image.asset('assets/images/publisher_logo_default.png',
                            fit: BoxFit.contain),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isEmpty ? '未知发布者' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2329),
                  ),
                ),
                if (goodsCount.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '出版物总数 $goodsCount',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF909399),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 通用组件 ====================

  String _text(int? value) => value == null ? '' : '$value';

  Widget _card({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title.isNotEmpty) ...<Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2329),
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
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

/// 统计项：主数值（+ 辅助前缀/后缀）+ icon + 文案
class _Stat {
  /// 主数值（16px 加粗）
  final String value;

  /// 辅助前缀（如页码的「P」，12px 不加粗）
  final String? prefix;

  /// 辅助后缀（如「/ 总数」，12px 不加粗）
  final String? suffix;

  final IconData icon;
  final String label;

  const _Stat({
    required this.value,
    this.prefix,
    this.suffix,
    required this.icon,
    required this.label,
  });
}

/// 统计主数值样式（保持原字号、加粗）
const TextStyle _statMainStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
  color: Color(0xFF1F2329),
  height: 1.2,
);

/// 统计辅助信息样式（总数、页码前缀等：缩小一号、不加粗）
const TextStyle _statAuxStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: Color(0xFF909399),
  height: 1.2,
);

// ==================== 字段容错 ====================

/// 转为可读 Map（非 Map 时返回空 Map）
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

String _str(dynamic v) {
  if (v == null) return '';
  final String s = v.toString().trim();
  return s == 'null' ? '' : s;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? _toBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final String s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

String _firstNonEmpty(List<String> candidates) {
  for (final String v in candidates) {
    if (v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// 纯数字链码 → 带连字符展示（服务码 6 位 + 剩余部分）
String _hyphenCode(String code) {
  final String digits = code.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 21) {
    return '${digits.substring(0, 6)}-${digits.substring(6)}';
  }
  return digits;
}

/// 字节数 → B / KB / MB / GB（整数不带小数点）
String _sizeText(num? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const double kb = 1024;
  const double mb = kb * 1024;
  const double gb = mb * 1024;
  String trim(double v) {
    final String s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (bytes < kb) return '${bytes.toInt()} B';
  if (bytes < mb) return '${trim(bytes / kb)} KB';
  if (bytes < gb) return '${trim(bytes / mb)} MB';
  return '${trim(bytes / gb)} GB';
}

String _avatarUrl(Map<String, dynamic> user) => _firstNonEmpty(<String>[
      _str(user['userHeadImgUrl']),
      _str(user['headImgUrl']),
      _str(user['avatarUrl']),
      _str(user['avatar']),
      _str(user['userAvatar']),
    ]);

String _userName(Map<String, dynamic> user) => _firstNonEmpty(<String>[
      _str(user['userName']),
      _str(user['nickName']),
      _str(user['nickname']),
      _str(user['name']),
    ]);

/// 点赞用户列表弹窗
class _LikeUsersSheet extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() fetcher;

  const _LikeUsersSheet({required this.title, required this.fetcher});

  @override
  State<_LikeUsersSheet> createState() => _LikeUsersSheetState();
}

class _LikeUsersSheetState extends State<_LikeUsersSheet> {
  late final Future<List<Map<String, dynamic>>> _future = widget.fetcher();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2329),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F2F5)),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final List<Map<String, dynamic>> users =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无点赞用户',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF909399)),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: users.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(
                      height: 1,
                      indent: 60,
                      color: Color(0xFFF5F6F8),
                    ),
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, dynamic> user = users[index];
                      final String url = cleanUrl(_avatarUrl(user));
                      final String name = _userName(user);
                      return ListTile(
                        leading: ClipOval(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: url.isEmpty
                                ? Image.asset(
                                    'assets/images/default_avatar.png',
                                    fit: BoxFit.cover,
                                  )
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    placeholder:
                                        (BuildContext context, String url) =>
                                            Container(
                                      color: const Color(0xFFF0F2F5),
                                    ),
                                    errorWidget: (BuildContext context,
                                            String url, Object error) =>
                                        Image.asset(
                                      'assets/images/default_avatar.png',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(
                          name.isEmpty ? '用户' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1F2329),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
