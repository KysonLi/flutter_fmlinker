import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/services/feedback_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:image_picker/image_picker.dart';

/// 意见反馈页（与小程序实现一致）
///
/// 问题类型 / 反馈内容 / 问题截图（最多9张）/ 联系方式
/// 提交时：有图片则并行上传拿 pathid，再提交反馈 JSON。
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  // 问题类型选项（与小程序 questionArray 一致）
  static const List<String> _typeOptions = [
    '扫码问题',
    '缓存问题',
    '内容问题',
    '充值与购买',
    '登录问题',
    '优化建议',
    '其他',
  ];

  static const int _maxImages = 9;
  static const int _maxContentLength = 500;

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  String _selectedType = _typeOptions.first;
  final List<String> _images = [];
  bool _submitting = false;

  final RegExp _phoneReg = RegExp(r'^1[3-9]\d{9}$');
  final RegExp _emailReg = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _contentController.text.trim().isNotEmpty && !_submitting;

  // 选择图片（拍照 / 相册）
  Future<void> _chooseImage() async {
    final remain = _maxImages - _images.length;
    if (remain <= 0) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildSheetItem('拍照', () => _pickFromCamera(sheetContext)),
              const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 16),
              _buildSheetItem('从相册选择', () => _pickFromGallery(sheetContext)),
              const SizedBox(height: 10),
              _buildSheetItem('取消', () => Navigator.pop(sheetContext),
                  isCancel: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetItem(String title, VoidCallback onTap,
      {bool isCancel = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: isCancel ? Colors.grey : Colors.black,
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromCamera(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (file != null && _images.length < _maxImages) {
        setState(() => _images.add(file.path));
      }
    } catch (e) {
      EasyLoading.showToast('拍照失败');
    }
  }

  Future<void> _pickFromGallery(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    try {
      final remain = _maxImages - _images.length;
      final files = await _imagePicker.pickMultiImage(
        imageQuality: 80,
        limit: remain,
      );
      if (files.isNotEmpty) {
        setState(() {
          for (final f in files) {
            if (_images.length >= _maxImages) break;
            _images.add(f.path);
          }
        });
      }
    } catch (e) {
      EasyLoading.showToast('选择图片失败');
    }
  }

  // 预览图片（全屏查看）
  void _previewImage(int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return GestureDetector(
          onTap: () => Navigator.pop(dialogContext),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: InteractiveViewer(
                maxScale: 4.0,
                child: Image.file(
                  File(_images[index]),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  // 提交反馈
  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final text = _contentController.text.trim();
    if (text.isEmpty) {
      EasyLoading.showToast('问题描述不能为空');
      return;
    }

    String phone = '';
    String mail = '';
    final contact = _contactController.text.trim();
    if (contact.isNotEmpty) {
      if (_phoneReg.hasMatch(contact)) {
        phone = contact;
      } else if (_emailReg.hasMatch(contact)) {
        mail = contact;
      } else {
        EasyLoading.showToast('请输入正确的手机号或邮箱');
        return;
      }
    }

    setState(() => _submitting = true);
    EasyLoading.show(status: '提交中...');

    // 在异步操作前捕获屏幕尺寸，避免跨 async 使用 BuildContext
    final size = MediaQuery.of(context).size;

    try {
      // 组装请求体（与小程序一致）
      final deviceId = await DeviceInfoUtil.getDeviceId();
      final systemVersion = await DeviceInfoUtil.getSystemVersion();
      final nickName = await UserService().getNickName();

      final body = <String, dynamic>{
        'source': 103,
        'type': _selectedType,
        'string': '#$_selectedType# $text',
        'name': nickName.isEmpty ? deviceId : nickName,
        'version': '1.0.0',
        'os': 0,
        'osstring': systemVersion,
        'resolution': '${size.width.round()}*${size.height.round()}',
      };
      if (phone.isNotEmpty) body['phone'] = phone;
      if (mail.isNotEmpty) body['mail'] = mail;

      // 有图片：并行上传，收集 pathid
      if (_images.isNotEmpty) {
        final pathids = await Future.wait(
          _images.map((p) => FeedbackService().uploadImage(p)),
        );
        body['pathids'] = pathids;
      }

      await FeedbackService().submitFeedback(body);

      EasyLoading.dismiss();
      EasyLoading.showToast('反馈已提交');
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      print('反馈提交失败: $e');
      EasyLoading.dismiss();
      EasyLoading.showToast('提交失败，请稍后再试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('意见反馈', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 问题类型
            _buildCard(
              title: '问题类型',
              child: _buildTypeTags(),
            ),
            // 反馈内容
            _buildCard(
              title: '反馈内容',
              required: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _contentController,
                    maxLines: 6,
                    maxLength: _maxContentLength,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    decoration: InputDecoration(
                      hintText: '请描述您遇到的问题或建议（最多500字）',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: Color(0xFFBBBBBB)),
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      counterText: '',
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF2376E3),
                          width: 1.2,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_contentController.text.length}/$_maxContentLength',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFBFBFBF)),
                    ),
                  ),
                ],
              ),
            ),
            // 问题截图
            _buildCard(
              title: '问题截图（最多 9 张）',
              child: _buildImageGrid(),
            ),
            // 联系方式
            _buildCard(
              title: '联系方式',
              child: TextField(
                controller: _contactController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '手机号或邮箱（选填）',
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
                  filled: true,
                  fillColor: const Color(0xFFF5F7FA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF2376E3),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 提交按钮
            SizedBox(
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF2376E3), Color(0xFF4A9DFF)],
                  ),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2376E3).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(23),
                    onTap: _canSubmit ? _handleSubmit : null,
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _canSubmit ? '提交反馈' : '请填写反馈内容',
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 卡片容器
  Widget _buildCard({
    required String title,
    required Widget child,
    bool required = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(fontSize: 14, color: Color(0xFFFF4D4F)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // 问题类型标签
  Widget _buildTypeTags() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _typeOptions.map((item) {
        final bool active = _selectedType == item;
        return GestureDetector(
          onTap: () {
            setState(() => _selectedType = item);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF2376E3).withValues(alpha: 0.1)
                  : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 12,
                color:
                    active ? const Color(0xFF2376E3) : const Color(0xFF595959),
                fontWeight: active ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // 问题截图网格
  Widget _buildImageGrid() {
    const double itemSize = 88;
    const double spacing = 8;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (int i = 0; i < _images.length; i++)
          SizedBox(
            width: itemSize,
            height: itemSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _previewImage(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_images[i]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                // 删除按钮
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => _removeImage(i),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 添加按钮
        if (_images.length < _maxImages)
          GestureDetector(
            onTap: _chooseImage,
            child: Container(
              width: itemSize,
              height: itemSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFD9D9D9),
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined,
                      size: 26, color: Color(0xFFBFBFBF)),
                  const SizedBox(height: 4),
                  Text(
                    '${_images.length}/$_maxImages',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
