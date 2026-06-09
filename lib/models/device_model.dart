class DeviceModel {
  String name;
  String deviceID;
  String time;
  String serverID;
  bool isLocal;

  DeviceModel({
    required this.name,
    required this.deviceID,
    required this.time,
    required this.serverID,
    this.isLocal = false,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      name: json['device_name']?.toString() ?? '',
      deviceID: json['device_id']?.toString() ?? '',
      time: json['last_login_time']?.toString() ?? '',
      serverID: json['id']?.toString() ?? '',
    );
  }
}
