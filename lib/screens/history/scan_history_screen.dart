import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/resource/resource_entry.dart';
import 'package:fmlink/services/link_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/isli_code_util.dart';
import 'package:fmlink/widgets/delete_action_button.dart';

class ScanHistoryScreen extends StatefulWidget {
  final String goodsId;
  final String goodsName;

  const ScanHistoryScreen({
    super.key,
    required this.goodsId,
    required this.goodsName,
  });

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

enum SortType {
  scanOrder,
  serialOrder,
  serialDescOrder,
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  final LinkService _linkService = LinkService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  List<dynamic> _scanHistory = [];
  int _totalCount = 0;
  int _scannedCount = 0;
  bool _isLoading = true;
  SortType _sortType = SortType.scanOrder;

  int _pageIndex = 1;
  final int _pageSize = 20;
  bool _hasMore = true;

  bool _isManageMode = false;
  final Set<String> _selectedItems = {};
  bool _isSelectAll = false;

  @override
  void initState() {
    super.initState();
    _loadScanHistory();
  }

  String _getSortString() {
    switch (_sortType) {
      case SortType.scanOrder:
        return 'ORDER_BY_LINK';
      case SortType.serialOrder:
        return 'ORDER_BY_POSITIVE_SEQUENCE';
      case SortType.serialDescOrder:
        return 'ORDER_BY_INVERT_SEQUENCE';
    }
  }

  Future<void> _loadScanHistory({bool isRefresh = false}) async {
    if (!isRefresh && !_hasMore) {
      _refreshController.finishLoad(IndicatorResult.noMore);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        return;
      }

      Map<String, dynamic> response = await _linkService.getScanHistory(
        unificationId,
        goodsId: widget.goodsId,
        pageIndex: _pageIndex,
        pageSize: _pageSize,
        orderBy: _getSortString(),
      );

      if (response['status'] && response['data'] != null) {
        Map<String, dynamic> data = response['data'];
        List<dynamic> linkInfoList = data['linkInfoList'] ?? [];

        setState(() {
          _totalCount = data['goodLinkCount'] ?? 0;

          if (isRefresh) {
            _scannedCount = linkInfoList.length;
            _scanHistory = linkInfoList;
            _pageIndex = 1;
            _hasMore = true;
          } else {
            _scannedCount += linkInfoList.length;
            _scanHistory.addAll(linkInfoList);
            _pageIndex++;
          }

          _hasMore = linkInfoList.length >= _pageSize;
        });
      }
    } catch (e) {
      debugPrint('加载扫码历史失败: $e');
      EasyLoading.showToast('加载失败，请稍后重试');
    } finally {
      EasyLoading.dismiss();
      setState(() {
        _isLoading = false;
      });
      if (isRefresh) {
        _refreshController.finishRefresh();
        _refreshController.resetFooter();
      } else {
        _refreshController.finishLoad(
          _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
        );
      }
    }
  }

  void _changeSortType(SortType type) {
    setState(() {
      _sortType = type;
    });
    _pageIndex = 1;
    _loadScanHistory(isRefresh: true);
  }

  void _toggleManageMode() {
    setState(() {
      _isManageMode = !_isManageMode;
      _selectedItems.clear();
      _isSelectAll = false;
    });
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItems.contains(itemId)) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems.add(itemId);
      }
      _isSelectAll = _selectedItems.length == _scanHistory.length &&
          _scanHistory.isNotEmpty;
    });
  }

  /// 普通模式下点击记录 → 以 sourceIdentifier 进入资源模块
  void _handleItemTap(dynamic item) {
    final String? sourceIdentifier = item['sourceIdentifier']?.toString();
    if (sourceIdentifier == null || sourceIdentifier.isEmpty) {
      EasyLoading.showToast('暂无链码信息');
      return;
    }
    ResourceEntry.openFromCode(
      context,
      isliCode: sourceIdentifier.replaceAll('-', ''),
      fromScan: false,
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isSelectAll) {
        _selectedItems.clear();
      } else {
        _selectedItems.clear();
        for (var item in _scanHistory) {
          String? itemId = _getItemId(item);
          if (itemId != null) {
            _selectedItems.add(itemId);
          }
        }
      }
      _isSelectAll = !_isSelectAll;
    });
  }

  String? _getItemId(dynamic item) {
    if (item == null) return null;
    String? sourceIdentifier = item['sourceIdentifier']?.toString();
    String? versionCode = item['versionCode']?.toString();
    if (sourceIdentifier != null && sourceIdentifier.isNotEmpty) {
      return '$sourceIdentifier-${versionCode ?? ''}';
    }
    return null;
  }

  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除选中的${_selectedItems.length}条扫码记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDelete();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete() async {
    try {
      EasyLoading.show(status: '删除中...');

      String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        EasyLoading.showError('用户未登录');
        return;
      }

      String sourceIds = _selectedItems.join(',');

      Map<String, dynamic> response = await _linkService.deleteScanHistory(
        unificationId,
        sourceIds,
      );

      if (response['status']) {
        setState(() {
          _isManageMode = false;
          _selectedItems.clear();
          _isSelectAll = false;
        });

        _pageIndex = 1;
        _loadScanHistory(isRefresh: true);

        EasyLoading.showSuccess('删除成功');
      } else {
        EasyLoading.showError(response['msg'] ?? '删除失败');
      }
    } catch (e) {
      debugPrint('删除失败: $e');
      EasyLoading.showError('删除失败，请稍后重试');
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.goodsName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _toggleManageMode,
            child: Text(
              _isManageMode ? '完成' : '管理',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          EasyRefresh(
            controller: _refreshController,
            onRefresh: () => _loadScanHistory(isRefresh: true),
            onLoad: () => _loadScanHistory(),
            header: RefreshConfig.buildHeader(),
            footer: RefreshConfig.buildFooter(),
            child: _buildContent(),
          ),
          if (_isManageMode) _buildBottomToolbar(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Container();
    }

    return ListView(
      padding: EdgeInsets.only(
        bottom: _isManageMode ? 70 + MediaQuery.of(context).padding.bottom : 0,
      ),
      children: [
        _buildHeader(),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),
        _buildList(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '扫链码关联的源: $_scannedCount/$_totalCount',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
            ),
          ),
          _buildSortButton(),
        ],
      ),
    );
  }

  Widget _buildSortButton() {
    return PopupMenuButton<SortType>(
      initialValue: _sortType,
      onSelected: _changeSortType,
      offset: const Offset(0, 30),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // 圆角菜单
        side: BorderSide(color: Colors.grey.shade300, width: 1), // 边框
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: SortType.scanOrder,
          child: Text('扫码顺序'),
        ),
        const PopupMenuItem(
          value: SortType.serialOrder,
          child: Text('序号顺序'),
        ),
        const PopupMenuItem(
          value: SortType.serialDescOrder,
          child: Text('序号倒序'),
        ),
      ],
      child: Row(
        children: [
          Text(
            _getSortLabel(),
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
          ),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
    );
  }

  String _getSortLabel() {
    switch (_sortType) {
      case SortType.scanOrder:
        return '扫码顺序';
      case SortType.serialOrder:
        return '序号顺序';
      case SortType.serialDescOrder:
        return '序号倒序';
    }
  }

  Widget _buildList() {
    if (_scanHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('暂无扫码记录')),
      );
    }

    return Column(
      children: _scanHistory.asMap().entries.map((entry) {
        int index = entry.key;
        dynamic item = entry.value;
        String? itemId = _getItemId(item);
        bool isSelected = itemId != null && _selectedItems.contains(itemId);

        return ScanHistoryItem(
          index: index + 1,
          sourceNo: item['sourceNo']?.toString() ?? '',
          sourceFragment: item['sourceFragment']?.toString() ?? '',
          serviceCode: item['serviceCode']?.toString(),
          prefixCode: item['prefixCode']?.toString(),
          suffixCode: item['suffixCode']?.toString(),
          resourceCount: item['resourceCount'] ?? 0,
          bookPageNo: item['bookPageNo'] ?? 0,
          isPaid: item['pay'] == true,
          isFree: item['free'] == true,
          isSelectable: _isManageMode,
          isSelected: isSelected,
          onTap: _isManageMode
              ? (itemId != null ? () => _toggleItemSelection(itemId) : null)
              : () => _handleItemTap(item),
        );
      }).toList(),
    );
  }

  Widget _buildBottomToolbar() {
    return Positioned(
      // 背景块紧贴屏幕底部，底部安全区高度只由内部 SafeArea 为内容让位
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 3,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleSelectAll,
                child: Row(
                  children: [
                    Image.asset(
                      _isSelectAll
                          ? 'assets/icons/all_selected.png'
                          : 'assets/icons/all_unselect.png',
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('全选'),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('已选择 ${_selectedItems.length} 条',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              DeleteActionButton(
                enabled: _selectedItems.isNotEmpty,
                onPressed: _deleteSelectedItems,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScanHistoryItem extends StatelessWidget {
  final int index;
  final String sourceNo;
  final String sourceFragment;
  final String? serviceCode;
  final String? prefixCode;
  final String? suffixCode;
  final int resourceCount;
  final int bookPageNo;
  final bool isPaid;
  final bool isFree;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback? onTap;

  const ScanHistoryItem({
    super.key,
    required this.index,
    required this.sourceNo,
    required this.sourceFragment,
    this.serviceCode,
    this.prefixCode,
    this.suffixCode,
    required this.resourceCount,
    required this.bookPageNo,
    required this.isPaid,
    required this.isFree,
    this.isSelectable = false,
    this.isSelected = false,
    this.onTap,
  });

  String _getSourceName() {
    if (sourceFragment.isNotEmpty) {
      return sourceFragment;
    }

    String service = serviceCode ?? '';
    String prefix = prefixCode ?? '';
    String suffix = suffixCode ?? '';

    if (service.isEmpty && prefix.isEmpty && suffix.isEmpty) {
      return '链码';
    }

    return ISLICodeUtil.buildISLICode(service, prefix, suffix);
  }

  Widget _buildStatusIcon() {
    if (isFree) {
      return const SizedBox.shrink();
    }

    if (isPaid) {
      return Image.asset('assets/icons/source_paid.png', width: 24, height: 24);
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSelectable)
            GestureDetector(
              onTap: onTap,
              child: Image.asset(
                isSelected
                    ? 'assets/icons/item_selected.png'
                    : 'assets/icons/item_unselect_outline.png',
                width: 20,
                height: 20,
              ),
            ),
          if (isSelectable) const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                sourceNo.isNotEmpty ? sourceNo : '$index',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF4F5960),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getSourceName(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF585959),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '资源 $resourceCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      bookPageNo > 0 ? '页码 P$bookPageNo' : '页码 P-',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Center(
            child: _buildStatusIcon(),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    return row;
  }
}
