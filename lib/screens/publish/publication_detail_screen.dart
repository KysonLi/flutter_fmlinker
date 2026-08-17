import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/services/publish_service.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:fmlink/models/publisher_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fmlink/screens/publish/update_history_dialog.dart';

class PublicationDetailScreen extends StatefulWidget {
  final String goodsId;

  const PublicationDetailScreen({super.key, required this.goodsId});

  @override
  State<PublicationDetailScreen> createState() =>
      _PublicationDetailScreenState();
}

class _PublicationDetailScreenState extends State<PublicationDetailScreen> {
  final PublishService _publishService = PublishService();

  bool _isLoading = true;
  Map<String, dynamic>? _publicationDetail;
  String? _errorMessage;

  bool _isVideoPlaying = false;
  VideoPlayerController? _videoController;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bookSectionKey = GlobalKey();
  final GlobalKey _sourceSectionKey = GlobalKey();
  final GlobalKey _descriptionSectionKey = GlobalKey();

  String _navBarTitle = '出版物详情';
  double _segmentOpacity = 0.0;
  int _selectedSegment = 0;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _loadPublicationDetail();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isUserScrolling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateNavBarAndSegment();
    });
  }

  void _updateNavBarAndSegment() {
    if (!mounted) return;

    final scrollOffset = _scrollController.offset;
    final screenHeight = MediaQuery.of(context).size.height;

    final bookContext = _bookSectionKey.currentContext;
    final descriptionContext = _descriptionSectionKey.currentContext;

    if (bookContext == null || descriptionContext == null) return;

    final bookBox = bookContext.findRenderObject() as RenderBox;
    final bookSectionHeight = bookBox.size.height;

    final descBox = descriptionContext.findRenderObject() as RenderBox;
    final descriptionSectionTop = descBox.localToGlobal(Offset.zero).dy;
    final descriptionSectionHeight = descBox.size.height;

    String newTitle = '出版物详情';
    final titleTriggerOffset = 250.0;
    if (scrollOffset > titleTriggerOffset) {
      newTitle = _publicationDetail!['goodsName'] ?? '出版物详情';
    }

    double newOpacity = 0.0;
    final segmentTriggerOffset = bookSectionHeight * 0.9;
    if (scrollOffset > segmentTriggerOffset) {
      newOpacity = ((scrollOffset - segmentTriggerOffset) / 100).clamp(0.0, 1.0);
    }

    int newSegment = 0;
    final descriptionMiddle = descriptionSectionTop + descriptionSectionHeight / 2;
    if (descriptionMiddle > 0 && descriptionMiddle < screenHeight) {
      newSegment = 1;
    } else {
      final sourceContext = _sourceSectionKey.currentContext;
      if (sourceContext != null) {
        final sourceBox = sourceContext.findRenderObject() as RenderBox;
        final sourceTop = sourceBox.localToGlobal(Offset.zero).dy;
        if (sourceTop > 0 && sourceTop < screenHeight) {
          newSegment = 0;
        }
      }
    }

    if (_navBarTitle != newTitle || _segmentOpacity != newOpacity || _selectedSegment != newSegment) {
      setState(() {
        _navBarTitle = newTitle;
        _segmentOpacity = newOpacity;
        _selectedSegment = newSegment;
      });
    }
  }

  Future<void> _loadPublicationDetail() async {
    try {
      EasyLoading.show(status: '加载中...');

      final response = await _publishService.getPublicationDetail(
        widget.goodsId,
      );

      if (response['status']) {
        setState(() {
          _publicationDetail = response['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['msg'] ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('加载出版物详情失败: $e');
      setState(() {
        _errorMessage = '加载失败，请稍后重试';
        _isLoading = false;
      });
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _initVideoPlayer(String videoUrl) async {
    if (_videoController != null) {
      await _videoController!.dispose();
    }

    _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    await _videoController!.initialize();
    setState(() {
      _isVideoPlaying = true;
    });
    await _videoController!.play();
  }

  Future<void> _toggleVideo(String videoUrl) async {
    if (_isVideoPlaying) {
      await _videoController?.pause();
      setState(() {
        _isVideoPlaying = false;
      });
    } else {
      if (_videoController == null ||
          _videoController!.dataSource != videoUrl) {
        await _initVideoPlayer(videoUrl);
      } else {
        setState(() {
          _isVideoPlaying = true;
        });
        await _videoController?.play();
      }
    }
  }

  void _scrollToSourceSection() {
    final sourceContext = _sourceSectionKey.currentContext;
    if (sourceContext != null) {
      _isUserScrolling = true;
      setState(() {
        _selectedSegment = 0;
      });
      final box = sourceContext.findRenderObject() as RenderBox;
      final offset =
          box.localToGlobal(Offset.zero).dy + _scrollController.offset - 100;
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        _isUserScrolling = false;
      });
    }
  }

  void _scrollToDescriptionSection() {
    final descriptionContext = _descriptionSectionKey.currentContext;
    if (descriptionContext != null) {
      _isUserScrolling = true;
      setState(() {
        _selectedSegment = 1;
      });
      final box = descriptionContext.findRenderObject() as RenderBox;
      final screenHeight = MediaQuery.of(context).size.height;
      final targetOffset =
          box.localToGlobal(Offset.zero).dy +
          _scrollController.offset -
          (screenHeight - box.size.height) / 2;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        _isUserScrolling = false;
      });
    }
  }

  String _stripHtmlAndSpecialChars(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _getPublicationTypeName(int type) {
    switch (type) {
      case 1:
        return 'ISBN';
      case 2:
        return 'CN';
      case 3:
        return 'ISSN';
      case 4:
        return 'ISRC';
      default:
        return 'ISBN';
    }
  }

  String _getEditionString(dynamic edition) {
    String editonStr = '未知';

    if (edition != null && edition.toString().isNotEmpty) {
      List<String> array = edition.toString().split(',');
      if (array.length == 2) {
        String version = '第${array[1]}版';
        String timeString = array[0];
        List<String> timeArray = timeString.split('-');
        if (timeArray.length == 2) {
          timeString = '${timeArray[0]}年${timeArray[1]}月';
        }
        editonStr = '$timeString $version';
      }
    }

    return '版次：$editonStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_navBarTitle, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () {
            context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: Image.asset('assets/icons/my_question.png', width: 20, height: 20),
            onPressed: () {
              context.push('/scan/book-help');
            },
          ),
        ],
        bottom:
            _segmentOpacity > 0
                ? PreferredSize(
                  preferredSize: const Size.fromHeight(40),
                  child: Opacity(
                    opacity: _segmentOpacity,
                    child: _buildSegmentControl(),
                  ),
                )
                : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildSegmentControl() {
    return Container(
      height: 40,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSegmentItem('关联资源', 0),
          const SizedBox(width: 40),
          _buildSegmentItem('MPR出版物', 1),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String title, int index) {
    final isSelected = _selectedSegment == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSegment = index;
        });
        if (index == 0) {
          _scrollToSourceSection();
        } else {
          _scrollToDescriptionSection();
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Colors.blue : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: 80,
            color: isSelected ? Colors.blue : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadPublicationDetail();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_publicationDetail == null) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: [
          // ==================== 板块1: 图书信息 ====================
          Container(key: _bookSectionKey, child: _buildBookSection()),

          // 板块间隔
          const SizedBox(height: 8),

          // ==================== 板块2: 关联资源信息 ====================
          Container(key: _sourceSectionKey, child: _buildSourceSection()),

          // 板块间隔
          const SizedBox(height: 8),

          // ==================== 板块3: 视频介绍 ====================
          _buildVideoSection(),

          // 板块间隔
          const SizedBox(height: 8),

          // ==================== 板块4: 关联阅读与点赞 ====================
          _buildStatisticsSection(),

          // 板块间隔
          const SizedBox(height: 8),

          // ==================== 板块5: 出版物简介 ====================
          Container(
            key: _descriptionSectionKey,
            child: _buildDescriptionSection(),
          ),

          // 板块间隔
          const SizedBox(height: 8),

          // ==================== 板块6: 第三方平台购买 ====================
          _buildPurchaseSection(),

          // 底部间距
          const SizedBox(height: 40),

          // 底部提示文字
          const Text(
            '祝您阅读愉快',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),

          // 最底部间距
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==================== 图书板块 ====================
  Widget _buildBookSection() {
    dynamic? publication = _publicationDetail!['publication'];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          // 提示文案
          const Text(
            '请扫书中[链码]',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // 图书封面
          BookCover(
            imageUrl: _publicationDetail!['goodsImage'] ?? '',
            width: 120,
            height: 160,
          ),
          const SizedBox(height: 12),

          // 图书名称
          Text(
            _publicationDetail!['goodsName'] ?? '未知出版物',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // 作者
          if (publication != null &&
              publication is Map &&
              publication.containsKey('author') &&
              publication['author'] != null)
            Text(
              '作者: ${publication['author']}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 4),

          // 出版社名称
          if (publication != null &&
              publication is Map &&
              publication.containsKey('publisher') &&
              publication['publisher'] != null)
            Text(
              '出版社: ${publication['publisher']}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),

          // 资源类型icons
          _buildResourceTypeIcons(),
        ],
      ),
    );
  }

  // ==================== 关联资源板块 ====================
  Widget _buildSourceSection() {
    String? shopName = _publicationDetail!['shopName'];
    String? shopId = _publicationDetail!['shopId']?.toString();
    String? shopDesc = _publicationDetail!['shopDesc']?.toString() ?? '';
    String? shopBrief = _publicationDetail!['shopBrief']?.toString() ?? '';
    String? shopLogo = _publicationDetail!['shopLogo']?.toString() ?? '';
    
    List<dynamic> sourceList = [];
    if (_publicationDetail!.containsKey('sourceList') &&
        _publicationDetail!['sourceList'] is List) {
      sourceList = _publicationDetail!['sourceList'];
    }
    int resourceCount = _publicationDetail!['resourceCount'] ?? 0;
    int sourceCount = _publicationDetail!['sourceCount'] ?? 0;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行: shopName + 右箭头
          _buildClickableRow(
            iconPath: 'assets/icons/publish_press.png',
            text: shopName ?? '',
            onTap: () {
              if (shopId != null && shopId.isNotEmpty && shopName != null && shopName.isNotEmpty) {
                final publisher = PublisherModel(
                  shopId: shopId,
                  shopName: shopName,
                  shopDesc: shopDesc,
                  shopBrief: shopBrief,
                  createTime: '',
                  nameInitial: shopName.isNotEmpty ? shopName.substring(0, 1) : '?',
                  logo: shopLogo,
                  isliLogo: '',
                  goodsCount: '0',
                );
                context.push('/publisher-detail', extra: publisher);
              }
            },
          ),

          const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // 第二行: 链码N(资源N) + 右箭头
          _buildClickableRow(
            iconPath: 'assets/icons/publish_code.png',
            text: '链码$sourceCount(资源$resourceCount)',
            onTap: () {
              String? serviceCode = _publicationDetail!['serviceCode']?.toString();
              String? prefixCode = _publicationDetail!['prefixCode']?.toString();
              int versionCode = _publicationDetail!['versionCode'] ?? 1;
              String? goodsImage = _publicationDetail!['goodsImage']?.toString();
              String? goodsName = _publicationDetail!['goodsName']?.toString();
              List<dynamic> resourceFormats = [];
              if (_publicationDetail!.containsKey('resourceForamt') &&
                  _publicationDetail!['resourceForamt'] is List) {
                resourceFormats = _publicationDetail!['resourceForamt'];
              }
              
              if (serviceCode != null && serviceCode.isNotEmpty && 
                  prefixCode != null && prefixCode.isNotEmpty) {
                context.push('/publication-source-list', extra: {
                  'goodsId': widget.goodsId,
                  'goodsName': goodsName ?? '',
                  'goodsImage': goodsImage ?? '',
                  'serviceCode': serviceCode,
                  'prefixCode': prefixCode,
                  'versionCode': versionCode,
                  'resourceFormats': resourceFormats,
                });
              }
            },
          ),

          if (sourceList.isNotEmpty)
            const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // sourceList列表
          ...sourceList.asMap().entries.map((entry) {
            int index = entry.key;
            dynamic source = entry.value;
            return Column(
              children: [
                _buildSourceItem(index + 1, source),
                if (index < sourceList.length - 1)
                  const Divider(height: 16, color: Color(0xFFEEEEEE)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ==================== 视频介绍板块 ====================
  Widget _buildVideoSection() {
    String? videoUrl = _publicationDetail!['goodsIntroduceVideo'];
    
    if (videoUrl == null || videoUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    String? videoCover = _publicationDetail!['goodsIntroduceCover'];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行: icon + "关联数字媒体资源介绍" (不可点击，无分割线，无箭头)
          Row(
            children: [
              Image.asset(
                'assets/icons/publish_video.png',
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '关联数字媒体资源介绍',
                  style: TextStyle(fontSize: 12, color: Colors.black),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 第二行: 视频内容
          GestureDetector(
            onTap: () => _toggleVideo(videoUrl),
            child:
                _isVideoPlaying && _videoController != null
                    ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoController!),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => _toggleVideo(videoUrl),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    : Stack(
                      alignment: Alignment.center,
                      children: [
                        videoCover != null && videoCover.isNotEmpty
                            ? Image.network(
                                videoCover,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/publish_video_cover.jpg',
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  );
                                },
                              )
                            : Image.asset(
                                'assets/images/publish_video_cover.jpg',
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                              ),
                        Image.asset(
                          'assets/icons/publish_play.png',
                          width: 50,
                          height: 50,
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  // ==================== 关联阅读与点赞板块 ====================
  Widget _buildStatisticsSection() {
    int readCount = _publicationDetail!['readCount'] ?? 0;
    int likeCount = _publicationDetail!['likeCount'] ?? 0;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行: icon + "关联阅读与点赞" (不可点击，无箭头)
          Row(
            children: [
              Image.asset(
                'assets/icons/publish_statistic.png',
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '关联阅读与点赞',
                  style: TextStyle(fontSize: 12, color: Colors.black),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 中间部分: 左右两部分
          Row(
            children: [
              // 左侧: 阅读
              Expanded(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/icons/publish_read.png',
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$readCount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '关联阅读次数',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              // 右侧: 点赞
              Expanded(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/icons/publish_like.png',
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$likeCount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '关联点赞次数',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // 最下面一行: 更新记录
          _buildClickableRow(
            iconPath: 'assets/icons/publish_update.png',
            text: '更新记录',
            onTap: () {
              _showUpdateHistoryDialog();
            },
          ),
        ],
      ),
    );
  }

  // ==================== 出版物简介板块 ====================
  Widget _buildDescriptionSection() {
    dynamic? publication = _publicationDetail!['publication'];
    String? goodsDesc = _publicationDetail!['goodsDesc'];
    String? goodsName = _publicationDetail!['goodsName'];
    String? edition = publication?['edition'];

    String? publicationIdentifier = publication?['publicationIdentifier'];
    int? publicationType = publication?['publicationType'];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行: icon + "出版物简介" + 右箭头
          _buildClickableRow(
            iconPath: 'assets/icons/publish_info.png',
            text: '出版物简介',
            onTap: () {
              if (goodsDesc != null && goodsDesc.isNotEmpty) {
                context.push('/publication-desc', extra: {
                  'title': goodsName ?? '出版物简介',
                  'content': goodsDesc,
                });
              }
            },
          ),

          const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // 第二行: 出版物简介信息 (去除特殊字符，最多显示5行)
          if (goodsDesc != null && goodsDesc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 25, right: 25),
              child: Text(
                _stripHtmlAndSpecialChars(goodsDesc),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // 第三行: 出版编号
          if (publicationIdentifier != null && publicationIdentifier.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 25, right: 25),
              child: Text(
                '${_getPublicationTypeName(publicationType ?? 1)}: $publicationIdentifier',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),

          // 第四行: 版次
          if (edition != null && edition.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 25, right: 25),
              child: Text(
                _getEditionString(edition),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 构建可点击的行 ====================
  Widget _buildClickableRow({
    required String iconPath,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Image.asset(iconPath, width: 16, height: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.black),
            ),
          ),
          Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
        ],
      ),
    );
  }

  // ==================== 构建单个资源项 ====================
  Widget _buildSourceItem(int index, dynamic source) {
    String sourceIdentifier = source['sourceIdentifier'] ?? '';
    String sourceNo = source['sourceNo']?.toString() ?? '';
    int? resourceCount = source['resourceCount'];
    int? bookPageNo;

    if (source['bookPageNo'] != null) {
      if (source['bookPageNo'] is int) {
        bookPageNo = source['bookPageNo'];
      } else if (source['bookPageNo'] is String) {
        bookPageNo = int.tryParse(source['bookPageNo']);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 5, 0, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号
          SizedBox(
            width: 30,
            child: Text(
              sourceNo,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 源信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行: sourceIdentifier
                Text(
                  sourceIdentifier,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // 第二行: 资源N | 页码 PN
                Row(
                  children: [
                    Text(
                      '资源${resourceCount ?? '?'}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '页码 P${bookPageNo ?? '?'}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 构建资源类型图标 ====================
  Widget _buildResourceTypeIcons() {
    List<Widget> icons = [];

    if (_publicationDetail!.containsKey('resourceForamt') &&
        _publicationDetail!['resourceForamt'] is List) {
      List<dynamic> formatList = _publicationDetail!['resourceForamt'];

      for (var format in formatList) {
        int? typeValue;
        if (format is int) {
          typeValue = format;
        } else if (format is String) {
          typeValue = int.tryParse(format);
        }

        if (typeValue != null) {
          icons.add(_getResourceIcon(typeValue));
        }
      }
    }

    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: icons);
  }

  // 根据资源类型值获取对应的图标
  Widget _getResourceIcon(int typeValue) {
    switch (typeValue) {
      case 1:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_text.png',
            width: 20,
            height: 20,
          ),
        );
      case 2:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_img.png',
            width: 20,
            height: 20,
          ),
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_audio.png',
            width: 20,
            height: 20,
          ),
        );
      case 4:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_video.png',
            width: 20,
            height: 20,
          ),
        );
      case 5:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_html.png',
            width: 20,
            height: 20,
          ),
        );
      case 6:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Image.asset(
            'assets/icons/resource_obj.png',
            width: 20,
            height: 20,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ==================== 第三方平台购买板块 ====================
  Widget _buildPurchaseSection() {
    List<dynamic> platformGoodsURLs = [];
    if (_publicationDetail!.containsKey('platformGoodsURLS') &&
        _publicationDetail!['platformGoodsURLS'] is List) {
      platformGoodsURLs = _publicationDetail!['platformGoodsURLS'];
    }

    if (platformGoodsURLs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 提示文案
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/icons/publish_tip.png',
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '扫书中链码，获取更多阅读资源。可在第三方平台购买纸书，购买时请核对书籍版次和封面标识',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // mpr_logo与文字左对齐显示在文字下面
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 25),
            child: Image.asset(
              'assets/icons/mpr_logo.png',
              width: 40,
              height: 16,
            ),
          ),

          const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // 平台列表
          ...platformGoodsURLs.asMap().entries.map((entry) {
            int index = entry.key;
            dynamic platformItem = entry.value;
            String? platformName = platformItem['name']?.toString();
            String? platformUrl = platformItem['url']?.toString();

            return Column(
              children: [
                _buildPlatformRow(name: platformName ?? '', url: platformUrl ?? ''),
                if (index < platformGoodsURLs.length - 1)
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ==================== 构建平台行 ====================
  Widget _buildPlatformRow({
    required String name,
    required String url,
  }) {
    return GestureDetector(
      onTap: () async {
        if (url.isNotEmpty) {
          try {
            String urlToLaunch = url.trim();
            if (!urlToLaunch.startsWith('http://') && !urlToLaunch.startsWith('https://')) {
              urlToLaunch = 'https://$urlToLaunch';
            }
            final uri = Uri.parse(urlToLaunch);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          } catch (e) {
            print('Failed to launch URL: $e');
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 12, 0, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 12, color: Colors.black),
              ),
            ),
            Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
          ],
        ),
      ),
    );
  }

  void _showUpdateHistoryDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return UpdateHistoryDialog(
          goodsId: widget.goodsId,
          goodsName: _publicationDetail!['goodsName']?.toString() ?? '',
        );
      },
    );
  }
}
