// 生成 `ohos/build-profile.json5`（脚本不含任何密钥信息，可安全提交）
//
// 用法：
//   dart run tool/gen_ohos_build_profile.dart            # 发布签名（AGC 发布证书）
//   dart run tool/gen_ohos_build_profile.dart --debug    # 调试签名（真机 hdc 安装用）
//
// 读取顺序（后者覆盖前者）：
//   1. 默认值：signature/ 下的 debug 证书（本地联调即可用）
//   2. signature/signing.env（KEY=VALUE，已在 .gitignore 中）
//   3. 进程环境变量（CI 用）
//
// 支持的键：
//   SIGNING_STORE_FILE / SIGNING_STORE_PASSWORD / SIGNING_KEY_ALIAS /
//   SIGNING_KEY_PASSWORD / SIGNING_PROFILE / SIGNING_CERT_PATH
//
// 详细说明见 docs/ohos-release-build.md
import 'dart:io';

const String _repoRootMarker = 'pubspec.yaml';
const String _template = 'ohos/build-profile.template.json5';
const String _output = 'ohos/build-profile.json5';
const String _envFile = 'signature/signing.env';

/// 调试签名（`--debug`）：真机 hdc 安装只信任设备绑定的 debug 证书
const Map<String, String> _debugSigning = <String, String>{
  'SIGNING_STORE_FILE': 'signature/fmlinker-debug.p12',
  'SIGNING_KEY_ALIAS': 'fmlinker',
  'SIGNING_PROFILE': 'signature/fmlinker-debug.p7b',
  'SIGNING_CERT_PATH': 'signature/fmlinker-debug.cer',
};

const List<String> _allKeys = <String>[
  'SIGNING_STORE_FILE',
  'SIGNING_STORE_PASSWORD',
  'SIGNING_KEY_ALIAS',
  'SIGNING_KEY_PASSWORD',
  'SIGNING_PROFILE',
  'SIGNING_CERT_PATH',
];

void main(List<String> args) {
  final Directory root = _findRepoRoot();
  final bool useDebugSigning = args.contains('--debug');
  final Map<String, String> values = <String, String>{
    ..._readEnvFile(root),
    ..._readProcessEnv(),
    // --debug 最高优先级：切回调试证书（密码密文沿用，因为明文密码相同）
    if (useDebugSigning) ..._debugSigning,
  };

  final List<String> missing = <String>[
    for (final String key in <String>[
      'SIGNING_STORE_PASSWORD',
      'SIGNING_KEY_PASSWORD',
    ])
      if ((values[key] ?? '').isEmpty) key,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
      '缺少签名密码：${missing.join(', ')}\n'
      '请创建 $_envFile（格式见 docs/ohos-release-build.md），或通过环境变量传入。',
    );
    exit(2);
  }

  // hvigor 只会用 signature/material 解密「DevEco 加密后的密文」，明文密码会直接报
  // INVALID_DATA（构建退出码 255），这里提前拦截并给出可操作的提示。
  for (final String key in <String>[
    'SIGNING_STORE_PASSWORD',
    'SIGNING_KEY_PASSWORD',
  ]) {
    final String pwd = values[key]!;
    if (!_looksEncrypted(pwd)) {
      stderr.writeln(
        '$key 必须是 DevEco 加密后的密文（十六进制、长度≥32），当前值不是。\n'
        '请在 DevEco Studio → Project Structure → Signing Configs 里配置签名后，\n'
        '把生成的 storePassword / keyPassword 密文填到 $_envFile。',
      );
      exit(2);
    }
  }

  final File template = File('${root.path}/$_template');
  if (!template.existsSync()) {
    stderr.writeln('模板不存在：${template.path}');
    exit(2);
  }
  String content = template.readAsStringSync();

  for (final String key in _allKeys) {
    final String raw = values[key] ?? '';
    if (raw.isEmpty) {
      stderr.writeln('缺少签名配置：$key');
      exit(2);
    }
    content = content.replaceAll(
      '\${$key}',
      _escape(_resolvePath(root, key, raw)),
    );
  }

  final File output = File('${root.path}/$_output');
  output.writeAsStringSync(content);
  stdout.writeln('已生成 ${output.path}（${useDebugSigning ? '调试签名' : '发布签名'}）');
  stdout.writeln(
    '密钥库：${_resolvePath(root, 'SIGNING_STORE_FILE', values['SIGNING_STORE_FILE']!)}',
  );
}

Directory _findRepoRoot() {
  Directory dir = Directory.current;
  while (true) {
    if (File('${dir.path}/$_repoRootMarker').existsSync()) return dir;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('未找到项目根目录（缺少 pubspec.yaml）');
      exit(2);
    }
    dir = parent;
  }
}

/// 密钥库 / Profile / 证书需要绝对路径；密码与别名保持原值
String _resolvePath(Directory root, String key, String value) {
  if (key == 'SIGNING_STORE_PASSWORD' ||
      key == 'SIGNING_KEY_PASSWORD' ||
      key == 'SIGNING_KEY_ALIAS') {
    return value;
  }
  final String trimmed = value.trim();
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return '${root.path}/$trimmed';
}

Map<String, String> _readEnvFile(Directory root) {
  final File file = File('${root.path}/$_envFile');
  if (!file.existsSync()) return const <String, String>{};

  final Map<String, String> result = <String, String>{};
  for (final String line in file.readAsLinesSync()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final int idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    result[trimmed.substring(0, idx).trim()] =
        trimmed.substring(idx + 1).trim();
  }
  return result;
}

Map<String, String> _readProcessEnv() {
  final Map<String, String> result = <String, String>{};
  for (final String key in _allKeys) {
    final String? v = Platform.environment[key];
    if (v != null && v.isNotEmpty) result[key] = v;
  }
  return result;
}

String _escape(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('"', r'\"');

/// DevEco 加密后的密码是十六进制串，长度 ≥32 且为偶数
bool _looksEncrypted(String value) =>
    value.length >= 32 &&
    value.length.isEven &&
    RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
