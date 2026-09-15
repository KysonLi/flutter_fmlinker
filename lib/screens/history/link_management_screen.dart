import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/services/link_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/delete_action_button.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:fmlink/widgets/default_state_view.dart';
import 'package:go_router/go_router.dart';

class LinkManagementScreen extends StatefulWidget {
  const LinkManagementScreen({super.key});

  @override
  State<LinkManagementScreen> createState() => _LinkManagementScreenState();
}

class _LinkManagementScreenState extends State<LinkManagementScreen> {
  List<dynamic> _linkHistory = [];
  int _page = 1;
  final int _pageSize = 20;
  bool _hasMore = true;

  /// 加载失败原因（为空表示未失败），用于展示统一失败占位
  String? _error;
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  // 管理模式相关
  bool _isManageMode = false;
  final Set<String> _selectedItems = {};
  bool _isSelectAll = false;

  @override
  void initState() {
    super.initState();
    _loadLinkHistory();
  }

  // 获取历史关联数据
  void _loadLinkHistory({bool isRefresh = false}) async {
    if (!isRefresh && !_hasMore) {
      _refreshController.finishLoad(IndicatorResult.noMore);
      return;
    }

    try {
      if (isRefresh) {
        _page = 1;
        _hasMore = true;
        _error = null;
      }

      // 获取unificationId
      String unificationId = await UserService().getUnificationId();

      if (unificationId.isEmpty) {
        setState(() {});
        return;
      }

      if (isRefresh) {
        EasyLoading.show(status: '刷新中...');
      } else if (_page == 1) {
        EasyLoading.show(status: '加载中...');
      }

      final response = await LinkService().getGoodsScanHistory(
        unificationId,
        page: _page,
        pageSize: _pageSize,
      );

      if (response['status']) {
        dynamic data = response['data'];
        if (data != null && data is Map) {
          // 处理数据
          List<dynamic> linkInfoList = [];
          if (data.containsKey('linkInfoList') &&
              data['linkInfoList'] is List) {
            linkInfoList = data['linkInfoList'];
          }

          setState(() {
            if (isRefresh) {
              _linkHistory = linkInfoList;
            } else {
              _linkHistory.addAll(linkInfoList);
            }
            // 判断是否有更多数据
            _hasMore = linkInfoList.length >= _pageSize;
            _page++;
          });
        }
      } else {
        _error = response['msg']?.toString() ?? '';
        EasyLoading.showError(_error!.isEmpty ? '加载失败，请稍后重试' : _error!);
      }
    } catch (e) {
      debugPrint('加载历史关联数据失败: $e');
      _error = '加载失败，请稍后重试';
      EasyLoading.showError('加载失败，请稍后重试');
    } finally {
      EasyLoading.dismiss();
      setState(() {});
      if (isRefresh) {
        _refreshController.finishRefresh();
      } else {
        _refreshController.finishLoad(
          _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
        );
      }
    }
  }

  // 下拉刷新
  void _onRefresh() {
    _loadLinkHistory(isRefresh: true);
  }

  // 上拉加载更多
  void _onLoading() {
    _loadLinkHistory();
  }

  // 处理管理按钮点击
  void _handleManage() {
    _toggleManageMode();
  }

  // 构建状态图标
  Widget _buildStatusIcon(dynamic status) {
    int statusInt = 0;
    if (status is int) {
      statusInt = status;
    } else if (status is String) {
      int.tryParse(status) ?? 0;
    }

    Widget? icon;
    if (statusInt == 0) {
      // 下架图标
      icon = Image.asset('assets/icons/order_status_soldout.png',
          width: 32, height: 32);
    } else if (statusInt == 2 || statusInt == 3) {
      // 删除图标
      icon = Image.asset('assets/icons/order_status_delete.png',
          width: 32, height: 32);
    }

    if (icon != null) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: icon,
          ),
        ),
      );
    }

    return Container();
  }

  // 进入/退出管理模式
  void _toggleManageMode() {
    setState(() {
      _isManageMode = !_isManageMode;
      _selectedItems.clear();
      _isSelectAll = false;
    });
  }

  // 选择/取消选择单个项目
  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItems.contains(itemId)) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems.add(itemId);
      }
      // 检查是否所有项目都被选中
      _isSelectAll = _selectedItems.length == _linkHistory.length &&
          _linkHistory.isNotEmpty;
    });
  }

  // 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_isSelectAll) {
        // 取消全选
        _selectedItems.clear();
      } else {
        // 全选
        _selectedItems.clear();
        for (var item in _linkHistory) {
          String? itemId = _getItemId(item);
          if (itemId != null) {
            _selectedItems.add(itemId);
          }
        }
      }
      _isSelectAll = !_isSelectAll;
    });
  }

  // 获取项目ID
  String? _getItemId(dynamic item) {
    if (item == null) return null;
    if (item.containsKey('id') && item['id'] != null) {
      return item['id'].toString();
    } else if (item.containsKey('goodsId') && item['goodsId'] != null) {
      return item['goodsId'].toString();
    }
    return null;
  }

  // 删除选中的项目
  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除选中的${_selectedItems.length}条关联记录吗？'),
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

  // 执行删除操作
  Future<void> _performDelete() async {
    try {
      EasyLoading.show(status: '删除中...');

      // 获取unificationId
      String unificationId = await UserService().getUnificationId();
      if (unificationId.isEmpty) {
        EasyLoading.showError('用户未登录');
        return;
      }

      // 构建goodsIds参数
      String goodsIds = _selectedItems.join(',');

      // 调用删除接口
      final response = await LinkService().deleteGoodsLink(
        unificationId,
        goodsIds,
      );

      if (response['status']) {
        // 删除成功，重置页面状态
        setState(() {
          _isManageMode = false;
          _selectedItems.clear();
          _isSelectAll = false;
        });

        // 刷新列表数据
        _loadLinkHistory(isRefresh: true);

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
        title: const Text(
          '关联MPR出版物（全媒版）',
          style: TextStyle(fontSize: 14),
        ),
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () {
            context.pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: _handleManage,
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
            onRefresh: () => _onRefresh(),
            onLoad: () => _onLoading(),
            header: RefreshConfig.buildHeader(),
            footer: RefreshConfig.buildFooter(),
            child: _error != null && _linkHistory.isEmpty
                ? ListView(
                    children: <Widget>[
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: DefaultStateView.fromError(
                          message: _error,
                          onRetry: () => _loadLinkHistory(isRefresh: true),
                        ),
                      ),
                    ],
                  )
                : _linkHistory.isEmpty
                    ? ListView(
                        children: <Widget>[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: DefaultStateView.empty(text: '暂无关联数据'),
                          ),
                        ],
                      )
                    : ListView(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 12,
                          top: 12,
                          bottom: _isManageMode
                              ? 70 + MediaQuery.of(context).padding.bottom
                              : 12,
                        ),
                        children: [
                          Wrap(
                            alignment: WrapAlignment.start,
                            spacing: 10,
                            runSpacing: 15,
                            children: _linkHistory.map((item) {
                              String? itemId = _getItemId(item);
                              bool isSelected = itemId != null &&
                                  _selectedItems.contains(itemId);

                              return GestureDetector(
                                onTap: () {
                                  if (_isManageMode && itemId != null) {
                                    // 编辑模式下响应选中事件
                                    _toggleItemSelection(itemId);
                                  } else {
                                    // 非编辑模式下响应其他事件
                                    // TODO: 跳转到详情页面或其他操作
                                  }
                                },
                                child: SizedBox(
                                  width: (MediaQuery.of(context).size.width -
                                          24 -
                                          20) /
                                      3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 封面
                                      Stack(
                                        children: [
                                          BookCover(
                                            imageUrl: item['goodsImage'] ?? '',
                                            width: (MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    24 -
                                                    20) /
                                                3,
                                            height: ((MediaQuery.of(context)
                                                            .size
                                                            .width -
                                                        24 -
                                                        20) /
                                                    3) *
                                                1.4,
                                          ),
                                          // 状态图标
                                          if (item.containsKey('goodsStatus'))
                                            _buildStatusIcon(
                                                item['goodsStatus']),
                                          // 选择框
                                          if (_isManageMode && itemId != null)
                                            Positioned(
                                              top: 8,
                                              left: 8,
                                              child: GestureDetector(
                                                onTap: () {
                                                  _toggleItemSelection(itemId);
                                                },
                                                child: Image.asset(
                                                  isSelected
                                                      ? 'assets/icons/item_selected.png'
                                                      : 'assets/icons/item_unselect.png',
                                                  width: 20,
                                                  height: 20,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // 名称
                                      Text(
                                        item['goodsName'] ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // 已扫码次数
                                      Text(
                                        '已扫码: ${item['linkSourceCount'] ?? 0}/${item['resourceCount'] ?? 0}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
          ),
          // 底部工具栏
          if (_isManageMode)
            Positioned(
              // 背景块紧贴屏幕底部，底部安全区高度只由内部 SafeArea 为内容让位
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                      // 全选按钮
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
                      // 已选择数量
                      Expanded(
                        child: Center(
                          child: Text('已选择 ${_selectedItems.length} 条'),
                        ),
                      ),
                      // 删除按钮
                      DeleteActionButton(
                        enabled: _selectedItems.isNotEmpty,
                        onPressed: _deleteSelectedItems,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
