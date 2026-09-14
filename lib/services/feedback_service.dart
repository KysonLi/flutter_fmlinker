import 'package:dio/dio.dart';

/// 意见反馈服务（与小程序专用接口一致）
///
/// baseURL：https://customer.ilikereader.com:10010
/// 流程：① 并行上传各张图片 → 各自拿到 pathid
///       ② 提交反馈 JSON（含 pathids 数组）
class FeedbackService {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;

  static const String _baseUrl = 'https://customer.ilikereader.com:10010';

  late Dio _dio;

  FeedbackService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (status) {
        // 仅 2xx 视为成功，其余由业务逻辑处理
        return status != null && status >= 200 && status < 300;
      },
    ));
  }

  /// 上传单张图片，成功返回 pathid
  Future<String> uploadImage(String filePath) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      Response response =
          await _dio.post('/feedback/miniprogram/picture', data: formData);
      final data = response.data;
      if (data is Map && data['status'] == 0 && data['pathid'] != null) {
        return data['pathid'].toString();
      }
      throw Exception(data is Map && data['msg'] != null
          ? data['msg'].toString()
          : '图片上传失败');
    } catch (e) {
      print('反馈图片上传失败: $e');
      rethrow;
    }
  }

  /// 提交反馈数据（JSON body），成功返回 void
  Future<void> submitFeedback(Map<String, dynamic> body) async {
    try {
      Response response = await _dio.post(
        '/feedback/miniprogram/data',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = response.data;
      if (data is Map && data['status'] == 0) {
        return;
      }
      throw Exception(
          data is Map && data['msg'] != null ? data['msg'].toString() : '提交失败');
    } catch (e) {
      print('反馈提交失败: $e');
      rethrow;
    }
  }
}
