import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 导入 services.dart 包以使用 SystemChrome 和 SystemUiOverlayStyle
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:fmlink/services/link_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/widgets/book_cover_widgets.dart';
import 'package:fmlink/provider/tab_provider.dart';
import 'package:fmlink/screens/history/scan_history_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  List<dynamic> _linkHistory = [];
  int _linkCount = 0;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // 检查登录状态
  void _checkLoginStatus() async {
    try {
      bool isLoggedIn = await UserService().checkLoginStatus();

      if (isLoggedIn) {
        // 已登录
        setState(() {
          _isLoggedIn = true;
        });
        // 获取历史关联数据
        _loadLinkHistory();
      } else {
        // 未登录
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('检查登录状态失败: $e');
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  // 获取历史关联数据
  void _loadLinkHistory() async {
    try {
      // 获取unificationId
      String unificationId = await UserService().getUnificationId();

      if (unificationId.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      EasyLoading.show(status: '加载中...');
      final response = await LinkService().getGoodsScanHistory(
        unificationId,
        page: 1,
        pageSize: 20,
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
          // 获取linkCount
          int linkCount = 0;
          if (data.containsKey('linkCount')) {
            linkCount = int.tryParse(data['linkCount'].toString()) ?? 0;
          }

          setState(() {
            _linkHistory = linkInfoList;
            _linkCount = linkCount;
          });
        }
      } else {
        EasyLoading.showError(response['msg']);
      }
    } catch (e) {
      print('加载历史关联数据失败: $e');
      EasyLoading.showError('加载失败，请稍后重试');
    } finally {
      EasyLoading.dismiss();
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 跳转到扫码帮助页面
  void _goToScanHelp() {
    // TODO: 实现扫码帮助页面
    print('跳转到扫码帮助页面');
  }

  // 根据资源类型构建图标
  List<Widget> _buildResourceIcons(dynamic resourceForamt) {
    List<Widget> icons = [];

    // 确保resourceForamt是一个列表
    List<dynamic> formatList = [];
    if (resourceForamt is List) {
      formatList = resourceForamt;
    } else if (resourceForamt != null) {
      formatList = [resourceForamt];
    }

    for (var format in formatList) {
      int? typeValue;
      if (format is int) {
        typeValue = format;
      } else if (format is String) {
        typeValue = int.tryParse(format);
      }

      if (typeValue != null) {
        // 根据类型值添加对应的图标
        Widget iconWidget = _getResourceIcon(typeValue);
        icons.add(iconWidget);
        // 添加图标之间的间距
        if (format != formatList.last) {
          icons.add(const SizedBox(width: 5));
        }
      }
    }

    // 如果没有资源类型，显示默认图标
    if (icons.isEmpty) {
      icons.add(Icon(Icons.insert_drive_file, size: 16, color: Colors.grey));
    }

    return icons;
  }

  // 根据资源类型值获取对应的图标
  Widget _getResourceIcon(int typeValue) {
    // 这里根据ISLITargetType枚举来匹配图标
    switch (typeValue) {
      case 1: // text
        return Image.asset(
          'assets/icons/resource_text.png',
          width: 16,
          height: 16,
        );
      case 2: // image
        return Image.asset(
          'assets/icons/resource_img.png',
          width: 16,
          height: 16,
        );
      case 3: // audio
        return Image.asset(
          'assets/icons/resource_audio.png',
          width: 16,
          height: 16,
        );
      case 4: // video
        return Image.asset(
          'assets/icons/resource_video.png',
          width: 16,
          height: 16,
        );
      case 5: // html
        return Image.asset(
          'assets/icons/resource_html.png',
          width: 16,
          height: 16,
        );
      case 6: // obj
        return Image.asset(
          'assets/icons/resource_obj.png',
          width: 16,
          height: 16,
        );
      default:
        return Icon(Icons.insert_drive_file, size: 16, color: Colors.grey);
    }
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
      icon = Image.asset(
        'assets/icons/order_status_soldout.png',
        width: 32,
        height: 32,
      );
    } else if (statusInt == 2 || statusInt == 3) {
      // 删除图标
      icon = Image.asset(
        'assets/icons/order_status_delete.png',
        width: 32,
        height: 32,
      );
    }

    if (icon != null) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(child: icon),
        ),
      );
    }

    return Container();
  }

  @override
  Widget build(BuildContext context) {
    // 设置状态栏样式，与有导航栏时一致
    if (!_isLoggedIn) {
      // 未登录状态下，设置状态栏为半透明，字体为深色
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    return Scaffold(
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _isLoggedIn
              ? _buildLoggedInUI()
              : _buildNotLoggedInUI(),
    );
  }

  // 未登录状态的UI
  Widget _buildNotLoggedInUI() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 顶部标题
              const Text(
                '泛媒关联',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              // 中间图片
              Container(
                width: 160,
                height: 160,
                child: Image.asset(
                  'assets/images/link_unlogin.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 30),

              // Tips提示
              GestureDetector(
                onTap: _goToScanHelp,
                child: const Text(
                  'Tips: 扫描链码添加关联 ?',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 30),

              // 查看支持扫链码的出版物按钮
              Center(
                child: Container(
                  width: 280, // 固定宽度，确保两个按钮宽度一致
                  child: OutlinedButton(
                    onPressed: () {
                      // 进入出版页面
                      Provider.of<TabProvider>(
                        context,
                        listen: false,
                      ).switchTab(1);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20), // 半圆角
                      ),
                    ),
                    child: const Text(
                      '查看支持扫链码的出版物',
                      style: TextStyle(color: Colors.blue, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 登录按钮
              Center(
                child: Container(
                  width: 280, // 固定宽度，确保两个按钮宽度一致
                  child: ElevatedButton(
                    onPressed: () {
                      // 正常全屏进入登录页面
                      context.push('/login').then((value) {
                        // 登录成功后刷新页面
                        _checkLoginStatus();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20), // 半圆角
                      ),
                    ),
                    child: const Text(
                      '[登录] 同步关联数据',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20), // 添加底部间距，确保内容不会紧贴底部
            ],
          ),
        ),
      ),
    );
  }

  // 已登录状态的UI
  Widget _buildLoggedInUI() {
    return Container(
      child: Column(
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左侧占位，保持标题居中
                const SizedBox(width: 24),
                // 标题文本
                const Text(
                  '关联的MPR出版物',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                // 右侧按钮
                GestureDetector(
                  onTap: () {
                    // 跳转到关联出版物管理页面
                    context.push('/link-management');
                  },
                  child: Image.asset(
                    'assets/icons/history_more.png',
                    width: 35,
                    height: 35,
                  ),
                ),
              ],
            ),
          ),
          // 关联卡片
          Expanded(
            child:
                _linkHistory.isEmpty
                    ? SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 顶部标题
                          const Text(
                            '泛媒关联',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // 中间图片
                          Container(
                            width: 160,
                            height: 160,
                            child: Image.asset(
                              'assets/images/link_unlogin.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // Tips提示
                          GestureDetector(
                            onTap: _goToScanHelp,
                            child: const Text(
                              'Tips: 扫描链码添加关联 ?',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),

                          // 查看支持扫链码的出版物按钮
                          Center(
                            child: Container(
                              width: 280, // 固定宽度，确保两个按钮宽度一致
                              child: OutlinedButton(
                                onPressed: () {
                                  // 进入出版页面
                                  Provider.of<TabProvider>(
                                    context,
                                    listen: false,
                                  ).switchTab(1);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  side: const BorderSide(color: Colors.blue),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      20,
                                    ), // 半圆角
                                  ),
                                ),
                                child: const Text(
                                  '查看支持扫链码的出版物',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 去扫码按钮
                          Center(
                            child: Container(
                              width: 280, // 固定宽度，确保两个按钮宽度一致
                              child: ElevatedButton(
                                onPressed: () {
                                  // 跳转到扫码页面
                                  Provider.of<TabProvider>(
                                    context,
                                    listen: false,
                                  ).switchTab(2);
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  backgroundColor: Colors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      20,
                                    ), // 半圆角
                                  ),
                                ),
                                child: const Text(
                                  '去扫码',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20), // 添加底部间距，确保内容不会紧贴底部
                        ],
                      ),
                    )
                    : Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: CarouselSlider(
                        options: CarouselOptions(
                          height: double.infinity,
                          viewportFraction: 0.8,
                          initialPage: 0,
                          enableInfiniteScroll: false,
                          reverse: false,
                          autoPlay: false,
                          enlargeCenterPage: true,
                          scrollDirection: Axis.horizontal,
                        ),
                        items:
                            _linkHistory.map((item) {
                              var linkSource = item['linkSource'] ?? {};
                              var linkCode =
                                  linkSource['sourceFragment'] != null &&
                                          linkSource['sourceFragment']
                                              .toString()
                                              .isNotEmpty
                                      ? linkSource['sourceFragment']
                                      : linkSource['sourceIdentifier'];
                              return Builder(
                                builder: (BuildContext context) {
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ScanHistoryScreen(
                                            goodsId: item['goodsId']?.toString() ?? '',
                                            goodsName: item['goodsName'] ?? '',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width:
                                          MediaQuery.of(context).size.width * 0.8,
                                      margin: const EdgeInsets.only(
                                        left: 5,
                                        right: 5,
                                        bottom: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.withValues(
                                              alpha: 0.2,
                                            ),
                                            spreadRadius: 2,
                                            blurRadius: 5,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(15),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // 上半部分
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  // 出版物封面
                                                  Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      BookCover(
                                                        imageUrl:
                                                            item['goodsImage'] ??
                                                                '',
                                                        width: 100,
                                                        height: 140,
                                                        showShadow: false,
                                                      ),
                                                      // 状态图标
                                                      if (item.containsKey(
                                                        'goodsStatus',
                                                      ))
                                                        _buildStatusIcon(
                                                          item['goodsStatus'],
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // 出版物名称
                                                  Text(
                                                    item['goodsName'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // 链码数 | 资源数
                                                  Text(
                                                    '链码: ${item['sourceCount'] ?? 0} | 资源: ${item['resourceCount'] ?? 0}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // 资源类型icons
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                    children: [
                                                      // 根据resourceForamt显示对应的图标
                                                      ..._buildResourceIcons(
                                                        item['resourceForamt'] ??
                                                            [],
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // 下半部分
                                            Expanded(
                                              flex: 1,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 10),
                                                  const Divider(),
                                                  const SizedBox(height: 10),
                                                  // 已扫码数
                                                  Text(
                                                    '已扫码: ${item['linkSourceCount'] ?? 0}',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // 上传扫码pageNo | 上次的关联编码
                                                  Text(
                                                    '上次扫链码: P${linkSource['bookPageNo'] ?? '未知'} | ${linkCode ?? '未知'}',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
