import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({Key? key}) : super(key: key);

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();
  
  String _nickname = '用户';
  String _phone = '';
  String _avatarUrl = '';
  bool _hasSetUserName = false;
  bool _needRefresh = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    _nickname = await _userService.getNickName();
    _phone = await _userService.getMaskedPhone();
    _avatarUrl = await _userService.getAvatarUrl();
    _hasSetUserName = await _userService.hasSetUserName();
    setState(() {});
  }

  Future<void> _logout() async {
    await _userService.clearUserInfo();
    _needRefresh = true;
    Navigator.pop(context, {'refresh': true});
  }

  Future<void> _handleBindPhone() async {
    final result = await context.push('/profile/bind-phone');
    if (result is Map && result['refresh'] == true) {
      _needRefresh = true;
      await _loadUserInfo();
    }
  }

  Future<void> _handleNicknameTap() async {
    if (_hasSetUserName) {
      EasyLoading.showToast('用户名已设置，无法修改');
      return;
    }

    TextEditingController controller = TextEditingController(text: _nickname);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '修改用户名',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '用户名只能修改一次，确认后不能修改',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: '4-20个字符',
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2376E3)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    counterText: '',
                  ),
                  maxLength: 20,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 13),
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消', style: TextStyle(fontSize: 14)),
            ),
            TextButton(
              onPressed: () async {
                String userName = controller.text.trim();
                if (userName.length < 4 || userName.length > 20) {
                  EasyLoading.showToast('请输入4-20个字符的用户名');
                  return;
                }

                Navigator.pop(context);
                EasyLoading.show(status: '设置中...');

                bool success = await _userService.setUserName(userName);
                if (success) {
                  EasyLoading.showToast('设置成功');
                  _needRefresh = true;
                  await _loadUserInfo();
                } else {
                  EasyLoading.showToast('设置失败');
                }

                EasyLoading.dismiss();
              },
              child: const Text('确定', style: TextStyle(fontSize: 14, color: Color(0xFF2376E3))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleAvatarTap() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildBottomSheetItem('拍照', () => _handleImageSource(ImageSource.camera)),
              const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 16),
              _buildBottomSheetItem('从相册选择', () => _handleImageSource(ImageSource.gallery)),
              const SizedBox(height: 10),
              _buildBottomSheetItem('取消', () => Navigator.pop(context), isCancel: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetItem(String title, VoidCallback onTap, {bool isCancel = false}) {
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

  Future<void> _handleImageSource(ImageSource source) async {
    Navigator.pop(context);
    
    Permission permission;
    if (source == ImageSource.camera) {
      permission = Permission.camera;
    } else {
      if (Platform.isAndroid) {
        permission = Permission.storage;
      } else if (Platform.isOhos) {
        // ohos：相册访问走 storage（permission_handler_ohos 映射）
        permission = Permission.storage;
      } else {
        permission = Permission.photos;
      }
    }

    bool hasPermission = await _checkAndRequestPermission(permission, source);
    if (hasPermission) {
      await _pickImage(source);
    }
  }

  Future<bool> _checkAndRequestPermission(Permission permission, ImageSource source) async {
    PermissionStatus status = await permission.status;
    
    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      PermissionStatus result = await permission.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      await _showPermissionDeniedDialog(source);
      return false;
    }

    return false;
  }

  Future<void> _showPermissionDeniedDialog(ImageSource source) async {
    String permissionName = source == ImageSource.camera ? '相机' : '相册';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('权限提示'),
          content: Text('需要访问$permissionName权限才能继续操作，请在设置中开启权限'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('去设置'),
              onPressed: () async {
                Navigator.pop(context);
                await _openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAppSettings() async {
    try {
      if (Platform.isOhos) {
        // TODO(ohos): 确认 url_launcher_ohos 是否支持打开应用设置页；
        // 若不支持，需在 EntryAbility 增加 platform channel 调用系统 AbilityContext.startAbility。
        final opened = await launchUrl(Uri.parse('app-settings:'));
        if (!opened) {
          EasyLoading.showToast('无法打开设置页面');
        }
      } else if (Platform.isIOS) {
        const String url = 'app-settings:';
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url));
        } else {
          throw '无法打开设置页面';
        }
      } else {
        await launchUrl(
          Uri.parse('package:com.isli.fmlink'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      EasyLoading.showToast('无法打开设置页面');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (pickedFile != null) {
        await _cropImage(pickedFile.path);
      }
    } catch (e) {
      EasyLoading.showToast('图片选择失败');
    }
  }

  Future<void> _cropImage(String imagePath) async {
    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪头像',
            toolbarColor: Colors.blue,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: '裁剪头像',
            minimumAspectRatio: 1.0,
          ),
          // TODO(ohos): image_cropper v11 ohos Fork 若暴露 OhosUiSettings，在此追加：
          //   if (Platform.isOhos) OhosUiSettings(title: '裁剪头像'),
        ],
      );

      if (croppedFile != null) {
        await _uploadAvatar(croppedFile.path);
      }
    } catch (e) {
      EasyLoading.showToast('图片裁剪失败');
    }
  }

  Future<void> _uploadAvatar(String imagePath) async {
    EasyLoading.show(status: '上传中...');
    try {
      bool success = await _userService.uploadAvatar(imagePath);
      if (success) {
        EasyLoading.showToast('头像上传成功');
        _needRefresh = true;
        await _loadUserInfo();
      } else {
        EasyLoading.showToast('头像上传失败');
      }
    } catch (e) {
      EasyLoading.showToast('头像上传失败');
    } finally {
      EasyLoading.dismiss();
    }
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildArrowRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
          Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号与安全', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () {
            if (_needRefresh) {
              Navigator.pop(context, {'refresh': true});
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: _handleAvatarTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: Row(
                      children: <Widget>[
                        const Text('头像', style: TextStyle(fontSize: 13)),
                        const Spacer(),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: _avatarUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _avatarUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        Image.asset('assets/images/default_avatar.png', fit: BoxFit.cover),
                                  )
                                : Image.asset('assets/images/default_avatar.png', fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 16),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: _handleNicknameTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        const Text('用户名', style: TextStyle(fontSize: 13)),
                        const Spacer(),
                        Row(
                          children: [
                            Text(_nickname, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                            if (!_hasSetUserName)
                              const SizedBox(width: 4),
                            if (!_hasSetUserName)
                              Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 16),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: _phone.isEmpty ? _handleBindPhone : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        const Text('手机号', style: TextStyle(fontSize: 13)),
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              _phone.isEmpty ? '未绑定' : _phone,
                              style: TextStyle(
                                fontSize: 13,
                                color: _phone.isEmpty ? Colors.blue : Colors.grey,
                              ),
                            ),
                            if (_phone.isEmpty)
                              const SizedBox(width: 4),
                            if (_phone.isEmpty)
                              Image.asset('assets/icons/right_arrow.png', width: 12, height: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: () => context.push('/profile/set-password'),
                  child: _buildArrowRow('登录密码'),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: () => context.push('/profile/device-management'),
                  child: _buildArrowRow('设备管理'),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                child: GestureDetector(
                  onTap: () => context.push('/profile/delete-account'),
                  child: _buildArrowRow('注销账户'),
                ),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text('退出登录', style: TextStyle(fontSize: 14, color: Colors.black)),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}