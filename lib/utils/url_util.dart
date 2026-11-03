/// 资源地址统一升级为 HTTPS
///
/// 背景：服务端已全量支持 HTTPS 访问，但接口返回的图片 / 音视频 / 网页地址
/// 仍然是 `http://`。Android 9+ 默认禁止明文、iOS ATS 也限制明文，
/// 因此客户端在拿到数据后统一做一次兼容转换。
///
/// 规则：
/// - 只处理 `http://` 开头的绝对地址，其余（https / 相对路径 / 本地文件）原样返回
/// - 本机与局域网地址（127.0.0.1 / localhost / 私有网段 / *.local）保持不变，
///   否则本地缓存媒体服务 `http://127.0.0.1:<port>` 会失效
/// - 顺带清理后端常见的反引号包裹与首尾空白
library;

String toHttpsUrl(dynamic raw) {
  if (raw == null) return '';
  final String url = raw.toString().trim().replaceAll('`', '');
  if (url.isEmpty) return '';
  if (!url.toLowerCase().startsWith('http://')) return url;

  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  if (_isLocalHost(uri.host)) return url;

  return 'https://${url.substring('http://'.length)}';
}

/// 递归升级 Map/List 中的 http 地址（用于接口返回数据的统一处理）
///
/// 仅处理「纯 URL 字符串」；含 `<`、空白、换行的富文本（HTML 正文等）保持原样，
/// 避免误改正文里的第三方链接或文案。
dynamic upgradeUrlsToHttps(dynamic value) {
  if (value is String) {
    if (!value.startsWith('http://')) return value;
    if (value.contains('<') || value.contains('\n') || value.contains(' ')) {
      return value;
    }
    return toHttpsUrl(value);
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (dynamic key, dynamic v) => MapEntry<String, dynamic>(
        key.toString(),
        upgradeUrlsToHttps(v),
      ),
    );
  }
  if (value is List) {
    return value.map<dynamic>(upgradeUrlsToHttps).toList();
  }
  return value;
}

bool _isLocalHost(String host) {
  final String h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local')) return true;
  if (h == '0.0.0.0' || h == '127.0.0.1' || h == '::1' || h == '[::1]') {
    return true;
  }
  if (h.startsWith('127.') || h.startsWith('10.') || h.startsWith('192.168.')) {
    return true;
  }
  if (h.startsWith('169.254.')) return true;
  // 172.16.0.0 ~ 172.31.255.255
  final List<String> parts = h.split('.');
  if (parts.length == 4) {
    final int? a = int.tryParse(parts[0]);
    final int? b = int.tryParse(parts[1]);
    if (a == 172 && b != null && b >= 16 && b <= 31) return true;
  }
  return false;
}
