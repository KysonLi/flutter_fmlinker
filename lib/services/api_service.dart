import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/common/error_strings.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  
  late Dio _dio;
  
  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: Constants.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
      },
      validateStatus: (status) {
        // 允许所有状态码，不抛出异常，由业务逻辑处理
        return true;
      },
    ));
    
    // 添加请求拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 添加token
        String? token = Constants.token;
        if (token != null) {
          options.headers['token'] = token;
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        return handler.next(e);
      },
    ));
  }
  
  // 统一处理API响应
  Map<String, dynamic> _handleResponse(dynamic responseData) {
    if (responseData is Map) {
      String resultCode = responseData['resultCode'] ?? responseData['status'] ?? '';
      
      if (resultCode == '00000000' || resultCode == '0') {
        // 成功
        return {
          'status': true,
          'data': responseData['data'],
          'msg': responseData['resultMsg'] ?? responseData['message'] ?? '请求成功'
        };
      } else {
        // 失败
        String errorMsg = responseData['resultMsg'] ?? responseData['message'] ?? '';
        if (errorMsg.isEmpty) {
          errorMsg = ErrorStrings.getErrorMsg(resultCode);
        }
        return {
          'status': false,
          'data': null,
          'msg': errorMsg
        };
      }
    }
    // 非预期的响应格式
    return {
      'status': false,
      'data': null,
      'msg': '请求失败: 响应格式错误'
    };
  }

  // GET请求
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      print('GET请求: $path');
      print('请求参数: $queryParameters');
      Response response = await _dio.get(path, queryParameters: queryParameters);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data);
    } catch (e) {
      print('GET请求失败: $e');
      // 网络错误
      return {
        'status': false,
        'data': null,
        'msg': '网络请求失败: $e'
      };
    }
  }
  
  // POST请求
  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    try {
      print('POST请求: $path');
      print('请求参数: $data');
      Response response = await _dio.post(path, data: data);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data);
    } catch (e) {
      print('POST请求失败: $e');
      // 网络错误
      return {
        'status': false,
        'data': null,
        'msg': '网络请求失败: $e'
      };
    }
  }
  
  // 上传文件
  Future<Map<String, dynamic>> upload(String path, FormData formData) async {
    try {
      print('上传文件: $path');
      Response response = await _dio.post(path, data: formData);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data);
    } catch (e) {
      print('文件上传失败: $e');
      // 网络错误
      return {
        'status': false,
        'data': null,
        'msg': '文件上传失败: $e'
      };
    }
  }
  
  // 下载文件
  Future<void> download(String url, String savePath, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      await _dio.download(url, savePath, onReceiveProgress: onProgress);
    } catch (e) {
      throw Exception('文件下载失败: $e');
    }
  }
  
  // DELETE请求
  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      print('DELETE请求: $path');
      print('请求参数: $queryParameters');
      Response response = await _dio.delete(path, queryParameters: queryParameters);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data);
    } catch (e) {
      print('DELETE请求失败: $e');
      // 网络错误
      return {
        'status': false,
        'data': null,
        'msg': '网络请求失败: $e'
      };
    }
  }
}
