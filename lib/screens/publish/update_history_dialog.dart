import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';

class UpdateHistoryDialog extends StatefulWidget {
  final String goodsId;
  final String goodsName;

  const UpdateHistoryDialog({super.key, required this.goodsId, required this.goodsName});

  @override
  State<UpdateHistoryDialog> createState() => _UpdateHistoryDialogState();
}

class _UpdateHistoryDialogState extends State<UpdateHistoryDialog> {
  final PublishService _publishService = PublishService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
  );
  
  List<dynamic> _historyList = [];

  Future<void> _loadHistory({bool isRefresh = false}) async {
    if (!isRefresh) {
      EasyLoading.show();
    }

    try {
      await _userService.refreshToken();
      
      Map<String, dynamic> response = await _publishService.getPublicationUpdateRecord(widget.goodsId);
      
      if (response['status'] && response['data'] != null && response['data'] is List) {
        List<dynamic> data = response['data'];
        // 为每条记录添加更新描述
        for (int i = data.length - 1; i >= 0; i--) {
          data[i]['updateDesc'] = _generateUpdateDesc(data, i);
        }
        setState(() {
          _historyList = data;
        });
      }
    } catch (e) {
      EasyLoading.showToast('获取更新记录失败: $e');
    } finally {
      EasyLoading.dismiss();
      if (isRefresh) {
        _refreshController.finishRefresh();
      }
    }
  }

  String _generateUpdateDesc(List<dynamic> data, int index) {
    if (index == data.length - 1) {
      return '发布资源';
    }
    
    int currentCount = int.tryParse(data[index]['resourceCount']?.toString() ?? '0') ?? 0;
    int prevCount = int.tryParse(data[index + 1]['resourceCount']?.toString() ?? '0') ?? 0;
    
    if (currentCount > prevCount) {
      return '新增优质资源';
    } else if (currentCount < prevCount) {
      return '精简资源';
    } else {
      return '优化原有资源';
    }
  }

  void _onRefresh() {
    _loadHistory(isRefresh: true);
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.only(bottom: 20),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // 顶部标题栏
            Container(
              height: 50,
              decoration: const BoxDecoration(
                color: Color(0xFF4A90E2),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Text(
                      '更新记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: EasyRefresh(
                controller: _refreshController,
                onRefresh: () => _onRefresh(),
                header: RefreshConfig.buildHeader(),
                child: SingleChildScrollView(
                        child: Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 图书名称
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  child: Text(
                                    widget.goodsName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                                const SizedBox(height: 16),
                                // 更新记录列表
                                if (_historyList.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Text('暂无更新记录'),
                                  )
                                else
                                  ..._buildTimeline(),
                              ],
                            ),
                        ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(int index, dynamic item) {
    DateTime? updateTime;
    try {
      String timeStr = item['createTime']?.toString() ?? '';
      if (timeStr.isNotEmpty) {
        if (timeStr.contains(' ')) {
          timeStr = timeStr.split(' ')[0];
        }
        updateTime = DateTime.parse(timeStr);
      }
    } catch (e) {
      print('Parse time error: $e');
    }

    String dateStr = '--';
    String yearStr = '--';
    if (updateTime != null) {
      dateStr = '${updateTime.month.toString().padLeft(2, '0')}-${updateTime.day.toString().padLeft(2, '0')}';
      yearStr = updateTime.year.toString();
    }

    String resourceCount = item['resourceCount']?.toString() ?? '0';
    String updateDesc = item['updateDesc']?.toString() ?? '';
    bool isFirst = index == 0;
    bool isLast = index == _historyList.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 左侧时间
          SizedBox(
            width: 60,
            child: Column(
              children: [
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: isFirst ? Colors.black : Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  yearStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isFirst ? Colors.black : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 中间时间轴（竖线+圆点）
          SizedBox(
            width: 20,
            child: Column(
              children: [
                // 上竖线（第一条记录不显示）
                Container(width: 1, height: 25, color: !isFirst ? Colors.grey : Colors.transparent),
                // 圆点
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    border: Border.all(color: isFirst ? const Color(0xFF4A90E2) : Colors.grey, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
                // 下竖线（最后一条不显示）
                Container(width: 1, height: 25, color: !isLast ? Colors.grey : Colors.transparent),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 右侧内容
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 资源数量
                Text(
                  '资源数量: $resourceCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isFirst ? Colors.black : Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                // 更新描述
                Text(
                  '更新说明: $updateDesc',
                  style: TextStyle(fontSize: 8, color: isFirst ? Colors.black : Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline() {
    return _historyList.asMap().entries.map((entry) {
      return _buildTimelineItem(entry.key, entry.value);
    }).toList();
  }
}
