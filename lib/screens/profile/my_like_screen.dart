import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:fmlink/widgets/default_state_view.dart';

class MyLikeScreen extends StatefulWidget {
  const MyLikeScreen({super.key});

  @override
  State<MyLikeScreen> createState() => _MyLikeScreenState();
}

class _MyLikeScreenState extends State<MyLikeScreen> {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
  );

  List<dynamic> _likeList = [];
  bool _isLoading = true;

  /// 加载失败原因（为空表示未失败），用于展示统一失败占位
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLikeList();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadLikeList() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _userService.refreshToken();

      String unificationId = await _userService.getUnificationId();
      if (unificationId.isEmpty) {
        EasyLoading.showToast('用户未登录');
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic> response = await _apiService.get(
        '/target-goods/app/v1/resource/mylike',
        queryParameters: {'unificationId': unificationId},
      );

      if (response['status'] && response['data'] != null) {
        List<dynamic> myLikeRecord = response['data']['myLikeRcord'] ?? [];
        _likeList = myLikeRecord.where((item) {
          int status = item['goodsStatus'] ?? 0;
          return status == 1;
        }).toList();
      } else {
        _error = response['msg']?.toString() ?? '';
      }
    } catch (e) {
      final String msg = ErrorHandler().fromError(e, fallback: '获取点赞列表失败');
      _error = msg;
      EasyLoading.showError(msg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _refreshController.finishRefresh();
    }
  }

  Widget _buildLikeItem(dynamic item) {
    String coverUrl = item['goodsPicUrl'] ?? '';
    String goodsName = item['goodsName'] ?? '';
    int likeCount = item['myLikeCount'] ?? 0;
    String goodsId = item['goodsId']?.toString() ?? '';

    return GestureDetector(
      onTap: () {
        if (goodsId.isNotEmpty) {
          context.push('/publication-detail?goodsId=$goodsId');
        }
      },
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            BookCover(
              imageUrl: coverUrl,
              width: 80,
              height: 110,
              showShadow: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goodsName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '点赞：$likeCount',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的点赞', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? DefaultStateView.fromError(
                    message: _error,
                    onRetry: _loadLikeList,
                  )
                : _likeList.isEmpty
                    ? DefaultStateView.empty(text: '暂无点赞内容')
                    : EasyRefresh(
                        controller: _refreshController,
                        onRefresh: () => _loadLikeList(),
                        header: RefreshConfig.buildHeader(),
                        child: ListView.separated(
                          itemCount: _likeList.length,
                          separatorBuilder: (context, index) => const Divider(
                              height: 1, color: Color(0xFFEEEEEE)),
                          itemBuilder: (context, index) =>
                              _buildLikeItem(_likeList[index]),
                        ),
                      ),
      ),
    );
  }
}
