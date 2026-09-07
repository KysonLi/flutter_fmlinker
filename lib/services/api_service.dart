import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/common/app_navigator.dart';
import 'package:fmlink/common/constants.dart';
import 'package:fmlink/common/error_strings.dart';
import 'package:fmlink/services/user_service.dart';

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
  Map<String, dynamic> _handleResponse(dynamic responseData,
      {int? statusCode}) {
    // token 过期（HTTP 401 或响应体为 Unauthorized）：清除登录态并跳转登录页
    if (statusCode == Constants.errorCodeTokenExpired ||
        responseData == 'Unauthorized') {
      _handleTokenExpired();
      return {'status': false, 'data': null, 'msg': '登录已过期，请重新登录'};
    }

    if (responseData is Map) {
      String resultCode =
          responseData['resultCode'] ?? responseData['status'] ?? '';

      if (resultCode == '00000000' || resultCode == '0') {
        // 成功
        return {
          'status': true,
          'data': responseData['data'],
          'msg': responseData['resultMsg'] ?? responseData['message'] ?? '请求成功'
        };
      } else {
        // 失败
        String errorMsg =
            responseData['resultMsg'] ?? responseData['message'] ?? '';
        if (errorMsg.isEmpty) {
          errorMsg = ErrorStrings.getErrorMsg(resultCode);
        }
        return {'status': false, 'data': null, 'msg': errorMsg};
      }
    }
    // 非预期的响应格式
    return {'status': false, 'data': null, 'msg': '请求失败: 响应格式错误'};
  }

  /// 是否正在处理 token 过期（防止多个请求同时 401 导致重复弹窗/跳转）
  bool _handlingUnauthorized = false;

  /// token 过期处理：清除本地登录信息，提示后跳转登录页
  Future<void> _handleTokenExpired() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      // 清除本地登录信息（token、用户信息），同步 Constants.token
      await UserService().clearUserInfo();

      final BuildContext? ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('登录已过期', style: TextStyle(fontSize: 16)),
          content: const Text('请重新登录'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );

      if (ctx.mounted) {
        // 清空导航栈并进入登录页
        GoRouter.of(ctx).go('/login');
      }
    } finally {
      _handlingUnauthorized = false;
    }
  }

  // GET请求
  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      print('GET请求: $path');
      print('请求参数: $queryParameters');
      Response response =
          await _dio.get(path, queryParameters: queryParameters);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data, statusCode: response.statusCode);
    } catch (e) {
      print('GET请求失败: $e');
      // 网络错误
      return {'status': false, 'data': null, 'msg': '网络请求失败: $e'};
    }
  }

  // POST请求
  Future<Map<String, dynamic>> post(String path,
      {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      print('POST请求: $path');
      print('请求参数: $data');
      print('Query参数: $queryParameters');
      Response response =
          await _dio.post(path, data: data, queryParameters: queryParameters);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data, statusCode: response.statusCode);
    } catch (e) {
      print('POST请求失败: $e');
      // 网络错误
      return {'status': false, 'data': null, 'msg': '网络请求失败: $e'};
    }
  }

  // 上传文件
  Future<Map<String, dynamic>> upload(String path, FormData formData) async {
    try {
      print('上传文件: $path');
      Response response = await _dio.post(path, data: formData);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data, statusCode: response.statusCode);
    } catch (e) {
      print('文件上传失败: $e');
      // 网络错误
      return {'status': false, 'data': null, 'msg': '文件上传失败: $e'};
    }
  }

  // 下载文件
  Future<void> download(
    String url,
    String savePath, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      await _dio.download(url, savePath, onReceiveProgress: onProgress);
    } catch (e) {
      throw Exception('文件下载失败: $e');
    }
  }

  // DELETE请求
  Future<Map<String, dynamic>> delete(String path,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      print('DELETE请求: $path');
      print('请求参数: $queryParameters');
      Response response =
          await _dio.delete(path, queryParameters: queryParameters);
      print('响应数据: ${response.data}');
      return _handleResponse(response.data, statusCode: response.statusCode);
    } catch (e) {
      print('DELETE请求失败: $e');
      // 网络错误
      return {'status': false, 'data': null, 'msg': '网络请求失败: $e'};
    }
  }
}
