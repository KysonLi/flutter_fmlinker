import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fmlink/models/device_model.dart';
import 'package:fmlink/models/user_info.dart';
import 'package:fmlink/services/api_service.dart';
import 'package:fmlink/services/user_service.dart';
import 'package:fmlink/utils/device_info_util.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fmlink/common/refresh_config.dart';
import 'package:fmlink/utils/error_handler.dart';
import 'package:fmlink/widgets/default_state_view.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  List<DeviceModel> _devices = [];
  bool _isEditing = false;

  /// 加载失败原因（为空表示未失败），用于展示统一失败占位
  String? _error;
  final EasyRefreshController _refreshController = EasyRefreshController(
    controlFinishRefresh: true,
  );

  @override
  void initState() {
    super.initState();
    _loadDeviceList();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceList() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      await _userService.refreshToken();

      UserInfo? userInfo = await _userService.getUserInfo();
      String unificationId = userInfo?.unificationId ?? '';

      Map<String, dynamic> response = await _apiService.get(
        '/chain-server/api/link_code_system/login/v2/userdevice_list',
        queryParameters: {'account': unificationId},
      );

      List<DeviceModel> devices = [];
      String localDeviceId = await DeviceInfoUtil.getDeviceId();
      bool hasLocal = false;

      if (response['status'] && response['data'] is List) {
        for (var item in response['data']) {
          DeviceModel device = DeviceModel.fromJson(item);
          if (device.deviceID == localDeviceId) {
            hasLocal = true;
            device.isLocal = true;
            device.name = '${device.name}（本机）';
            devices.insert(0, device);
          } else {
            devices.add(device);
          }
        }
      } else {
        _error = response['msg']?.toString() ?? '';
      }

      if (!hasLocal) {
        String deviceName = await DeviceInfoUtil.getDeviceName();
        DateTime now = DateTime.now();
        String time =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        DeviceModel localDevice = DeviceModel(
          name: '$deviceName（本机）',
          deviceID: localDeviceId,
          time: time,
          serverID: '',
          isLocal: true,
        );
        devices.insert(0, localDevice);
      }

      setState(() {
        _devices = devices;
      });
    } catch (e) {
      final String msg = ErrorHandler().fromError(e, fallback: '获取设备列表失败');
      if (mounted) {
        setState(() => _error = msg);
      }
      EasyLoading.showError(msg);
    } finally {
      _refreshController.finishRefresh();
    }
  }

  Future<void> _deleteDevice(DeviceModel device) async {
    setState(() {});

    try {
      Map<String, dynamic> response = await _apiService.post(
        '/chain-server/api/link_code_system/login/v2/userdevice_delete',
        data: {'id': device.serverID},
      );

      if (response['status']) {
        EasyLoading.showToast('删除成功！');
        await _loadDeviceList();
      } else {
        EasyLoading.showToast(response['msg'] ?? '删除失败');
      }
    } catch (e) {
      EasyLoading.showError(ErrorHandler().fromError(e, fallback: '删除失败'));
    } finally {
      setState(() {});
    }
  }

  void _confirmDelete(DeviceModel device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text('删除后将清除设备上的数据，请谨慎操作'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDevice(device);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备管理', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 20, height: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
              });
            },
            child: Text(
              _isEditing ? '完成' : '编辑',
              style: const TextStyle(fontSize: 13, color: Color(0xFF2376E3)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: EasyRefresh(
              controller: _refreshController,
              onRefresh: () => _loadDeviceList(),
              header: RefreshConfig.buildHeader(),
              child: _error != null
                  ? DefaultStateView.fromError(
                      message: _error,
                      onRetry: _loadDeviceList,
                    )
                  : _devices.isEmpty
                      ? DefaultStateView.empty(text: '暂无登录设备')
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            DeviceModel device = _devices[index];
                            bool isFirst = index == 0;
                            bool isLocal = device.isLocal;

                            return Column(
                              children: [
                                if (isFirst && _devices.length > 1)
                                  const SizedBox(height: 16),
                                Container(
                                  color: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 16),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: const Color(0xFFEEEEEE)),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              device.name,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              device.time,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isEditing && !device.isLocal)
                                        TextButton(
                                          onPressed: () =>
                                              _confirmDelete(device),
                                          child: const Text(
                                            '移除',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.red),
                                          ),
                                        ),
                                      const SizedBox(width: 16),
                                    ],
                                  ),
                                ),
                                if (isLocal && _devices.length > 1)
                                  const SizedBox(height: 16),
                                if (!isFirst && !isLocal)
                                  const Divider(
                                      height: 1, color: Color(0xFFEEEEEE)),
                              ],
                            );
                          },
                        ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: const Text(
              '1、一个帐号最多可登录5台设备；\n2、可对列表中的设备进行删除(本机除外)，删除后将清除设备上的数据，请谨慎操作。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
