import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fmlink/resource/resource_service.dart';
import 'package:fmlink/resource/resource_types.dart';
import 'package:fmlink/resource/source_detail.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';

/// 源详情页
///
/// 由资源列表页 / 资源播放页携带 extra（`Map<String, dynamic>`）跳转：
/// - data：/source/scan 返回的 data 原始 Map
/// - goodsName：出版物名称（可空，data 内也有）
/// - isliCode：完整 ISLI 链码（可空）
/// - fromPlay：是否由资源播放页进入（为 true 时才展示源点赞用户与资源信息）
/// - resourceIndex：当前播放资源下标（资源信息只展示这一个资源）
/// - likeQuery：点赞用户列表接口参数（goodsId / resourceId / resourceOldId /
///   targetIdentifier），由播放页按当前播放资源给出
///
/// 页面内容自上而下：图书信息 → 源信息 →（点赞用户 → 当前资源信息）。
/// 从资源列表页进入时只有图书信息与源信息。
class ResourceSourceDetailScreen extends StatefulWidget {
  /// 路由 extra 参数
  final Map<String, dynamic> extra;

  const ResourceSourceDetailScreen({super.key, required this.extra});

  @override
  State<ResourceSourceDetailScreen> createState() =>
      _ResourceSourceDetailScreenState();
}

class _ResourceSourceDetailScreenState
    extends State<ResourceSourceDetailScreen> {
  static const int _likePageSize = 20;

  /// 点赞用户头像字段候选（不同接口版本命名不一）
  static const List<String> _avatarKeys = <String>[
    'headImgUrl',
    'userHeadImgUrl',
    'avatarUrl',
    'avatar',
    'headImage',
    'userAvatar',
    'portrait',
    'imgUrl',
    'imageUrl',
    'photo',
  ];

  late final SourceScanData _data;

  /// 是否由资源播放页进入（只有播放页进入才展示点赞用户）
  late final bool _fromPlay;

  List<String> _likeAvatars = const <String>[];
  bool _likeLoading = false;

  @override
  void initState() {
    super.initState();
    final dynamic raw = widget.extra['data'];
    _data = SourceScanData.fromJson(
      raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{},
    );
    _fromPlay = widget.extra['fromPlay'] == true;
    if (_fromPlay) {
      _loadLikeUsers();
    }
  }

  // ==================== 数据加载 ====================

  /// 当前播放的资源（资源信息与点赞仅针对它）
  ScanResource? get _currentResource {
    final List<ScanResource> resources = _data.currentResources;
    if (resources.isEmpty) return null;
    final dynamic raw = widget.extra['resourceIndex'];
    final int? index = raw is int ? raw : int.tryParse('${raw ?? ''}');
    if (index != null && index >= 0 && index < resources.length) {
      return resources[index];
    }
    return resources.first;
  }

  /// 源点赞用户列表（只用于展示头像）
  Future<void> _loadLikeUsers() async {
    final Map<String, dynamic> query =
        (widget.extra['likeQuery'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final ScanTarget? target = _data.currentTarget;
    final ScanResource? current = _currentResource;

    final String goodsId = _firstNonEmpty(<String>[
      _str(query['goodsId']),
      _data.goodsId,
      _pick(target?.raw, const <String>['bookId']),
    ]);
    final String resourceId = _firstNonEmpty(<String>[
      _str(query['resourceId']),
      _str(current?.id),
      _pick(target?.raw, const <String>['_id', 'id']),
    ]);
    final String resourceOldId = _firstNonEmpty(<String>[
      _str(query['resourceOldId']),
      _str(current?.resourceId),
      _pick(target?.raw, const <String>['resourceId']),
    ]);
    final String targetIdentifier = _firstNonEmpty(<String>[
      _str(query['targetIdentifier']),
      _str(target?.targetIdentifier),
    ]);
    if (goodsId.isEmpty ||
        resourceId.isEmpty ||
        resourceOldId.isEmpty ||
        targetIdentifier.isEmpty) {
      return;
    }

    setState(() {
      _likeLoading = true;
    });
    try {
      final Map<String, dynamic> res =
          await ResourceService().fetchResourceLikeUsers(
        goodsId: goodsId,
        resourceId: resourceId,
        resourceOldId: resourceOldId,
        targetIdentifier: targetIdentifier,
        pageIndex: 1,
        pageSize: _likePageSize,
      );
      if (!mounted) return;
      if (res['status'] == true) {
        setState(() {
          _likeAvatars = _extractAvatars(res['data']);
        });
      }
    } catch (e) {
      debugPrint('加载点赞用户失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _likeLoading = false;
        });
      }
    }
  }

  /// 兼容 List / {likeUsers|list|records|...} 两种返回结构
  List<String> _extractAvatars(dynamic data) {
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

    final List<String> avatars = <String>[];
    for (final dynamic item in items) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = item.cast<String, dynamic>();
      String url = _pick(map, _avatarKeys);
      final dynamic user = map['user'];
      if (url.isEmpty && user is Map) {
        url = _pick(user.cast<String, dynamic>(), _avatarKeys);
      }
      url = cleanUrl(url);
      if (url.isNotEmpty) avatars.add(url);
    }
    return avatars;
  }

  // ==================== 字段容错 ====================

  String _str(dynamic v) {
    if (v == null) return '';
    final String s = v.toString().trim();
    return s == 'null' ? '' : s;
  }

  String _firstNonEmpty(List<String> candidates) {
    for (final String v in candidates) {
      if (v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  /// 依次取 [keys] 中第一个非空值
  String _pick(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return '';
    for (final String key in keys) {
      final String v = _str(map[key]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final List<ScanResource> resources = _data.currentResources;

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
        title: const Text(
          '源详情',
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _buildBookCard(),
          const SizedBox(height: 12),
          _buildSourceCard(resources.length),
          if (_fromPlay) ...<Widget>[
            const SizedBox(height: 12),
            _buildLikeUsersCard(),
            const SizedBox(height: 12),
            _buildResourceCard(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 图书信息：封面、书名、出版社名称
  Widget _buildBookCard() {
    final Map<String, dynamic> raw = _data.raw;
    final Map<String, dynamic>? publication = raw['publication'] is Map
        ? (raw['publication'] as Map).cast<String, dynamic>()
        : null;
    final Map<String, dynamic>? goods = raw['goods'] is Map
        ? (raw['goods'] as Map).cast<String, dynamic>()
        : null;

    final String goodsName = _firstNonEmpty(<String>[
      _str(_data.goodsName),
      _str(widget.extra['goodsName']),
      _pick(publication, const <String>['goodsName', 'name']),
    ]);
    final String cover = _firstNonEmpty(<String>[
      _str(_data.goodsImage),
      _pick(publication, const <String>['goodsImage', 'image']),
    ]);
    final String publisher = _firstNonEmpty(<String>[
      _pick(raw, const <String>['shopName', 'publisherName', 'publisher']),
      _pick(publication, const <String>['publisher', 'shopName']),
      _pick(goods, const <String>['publisher', 'shopName']),
    ]);

    return _card(
      title: '图书信息',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BookCover(imageUrl: cover, width: 72, height: 100),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  goodsName.isEmpty ? '未知出版物' : goodsName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2329),
                    height: 1.4,
                  ),
                ),
                if (publisher.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '出版社：$publisher',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8C8C8C),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 源信息：isliCode、源名称、资源数量
  Widget _buildSourceCard(int resourceCount) {
    final Map<String, dynamic>? source = _data.source?.raw;
    final Map<String, dynamic>? target = _data.currentTarget?.raw;

    final String isliCode = _firstNonEmpty(<String>[
      _str(_data.source?.sourceIdentifier),
      _str(widget.extra['isliCode']),
      _pick(_data.raw, const <String>['isliCode', 'sourceIdentifier']),
    ]);
    // 源名称：只取真实名称字段，没有就整行不展示（不走片段/章节等兜底）
    final String sourceName = _firstNonEmpty(<String>[
      _pick(source, const <String>['sourceName']),
      _pick(target, const <String>['targetName']),
    ]);
    final int? count = _data.source?.resourceCount ?? _data.resourceCount;

    final List<Widget> rows = <Widget>[
      _infoRow('ISLI 编码', isliCode),
      _infoRow('源名称', sourceName),
      _infoRow('资源数量', (count ?? resourceCount).toString()),
    ].whereType<Padding>().toList();

    return _card(
      title: '源信息',
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF5F6F8)),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// 源点赞用户：仅资源播放页进入时展示，且只显示头像
  Widget _buildLikeUsersCard() {
    Widget content;
    if (_likeLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_likeAvatars.isEmpty) {
      content = const Text(
        '暂无点赞',
        style: TextStyle(fontSize: 12, color: Color(0xFF909399)),
      );
    } else {
      content = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String url in _likeAvatars) _avatar(url),
        ],
      );
    }

    return _card(
      title: '点赞用户',
      child: Align(alignment: Alignment.centerLeft, child: content),
    );
  }

  Widget _avatar(String url) {
    return ClipOval(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CachedNetworkImage(
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

  /// 资源信息：只展示当前资源，有哪些字段就展示哪些
  Widget _buildResourceCard() {
    final ScanResource? r = _currentResource;
    if (r == null) {
      return _card(
        title: '资源信息',
        child: const Text(
          '暂无资源信息',
          style: TextStyle(fontSize: 12, color: Color(0xFF909399)),
        ),
      );
    }

    return _card(
      title: '资源信息',
      child: _resourceItem(r),
    );
  }

  Widget _resourceItem(ScanResource r) {
    final List<Widget> rows = <Widget>[];

    void add(String label, String value) {
      if (value.trim().isEmpty) return;
      rows.add(_infoRow(label, value));
    }

    final String name = _str(r.resourceName);
    add('资源名称', name);
    if (r.type != ResourceType.unknown) add('资源类型', r.type.label);
    if (r.resourceNo != null) add('资源序号', '${r.resourceNo}');
    if (r.second != null && r.second! > 0) add('时长', _durationText(r.second!));
    add('文件大小', _str(r.resourceSize));
    if (r.updateTime != null && r.updateTime! > 0) {
      add('更新时间', _dateText(r.updateTime!));
    }
    if (r.raw.containsKey('free')) add('是否收费', r.isCharge ? '收费' : '免费');
    if (r.likeCount != null) add('点赞数', '${r.likeCount}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              ResourceTypeUi.icon(r.type),
              size: 16,
              color: ResourceTypeUi.color(r.type),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name.isEmpty ? '当前资源' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2329),
                ),
              ),
            ),
          ],
        ),
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, color: Color(0xFFF5F6F8)),
          rows[i],
        ],
      ],
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2329),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 80,
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

  /// 秒 → m:ss / h:mm:ss
  String _durationText(num seconds) {
    final int total = seconds.toInt();
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String mm = m.toString().padLeft(2, '0');
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// 时间戳（秒或毫秒）→ yyyy-MM-dd
  String _dateText(int timestamp) {
    final int ms = timestamp > 1000000000000 ? timestamp : timestamp * 1000;
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(ms);
    final String month = time.month.toString().padLeft(2, '0');
    final String day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
