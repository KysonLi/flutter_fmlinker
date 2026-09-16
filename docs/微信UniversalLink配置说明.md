# 微信 Universal Link 配置说明

> 目标 Universal Link：`https://apigateway.mpreader.com/wxul/`
> 适用：iOS 微信登录（`/login` 页「微信登录」）。Android / HarmonyOS 不使用 Universal Link。

## 1. 三处配置必须一致

Universal Link 生效依赖三个环节指向同一个域名，任何一处不一致都会导致 iOS 微信授权回调丢失（表现为「微信登录后回到 App 无响应」或 `errCode = -1`）：

| 位置 | 值 | 本次状态 |
|---|---|---|
| App 代码 | `ThirdPartyManager.weChatUniversalLink` | ✅ `lib/services/third_party_manager.dart` |
| pubspec 声明 | `fluwx.ios.universal_link` | ✅ `pubspec.yaml` |
| iOS 工程能力 | `applinks:apigateway.mpreader.com` | ✅ `ios/Runner/Runner.entitlements`（已接入 3 个构建配置） |
| 微信开放平台 | 「移动应用 → iOS → Universal Link」 | ⏳ 需在开放平台后台填写同一链接 |
| 服务端 AASA | `apple-app-site-association` 文件 | ⏳ 需部署（见第 3 节） |

## 2. 本次已完成的改动

| 文件 | 变更 |
|---|---|
| `lib/services/third_party_manager.dart` | 占位值 `https://your-domain.com/wechat` → 正式链接；抽出 `weChatUniversalLink` 常量并补注释 |
| `pubspec.yaml` | 新增 `fluwx` 配置段：`app_id` + `ios.universal_link`（fluwx 在 `pod install` 时读取，可自动同步 iOS 工程配置） |
| `ios/Runner/Runner.entitlements` | **新增**：`com.apple.developer.associated-domains = applinks:apigateway.mpreader.com` |
| `ios/Runner.xcodeproj/project.pbxproj` | Runner target 的 Debug / Release / Profile 均设置 `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`；加入文件引用；`TargetAttributes` 声明 Associated Domains 能力 |

> 说明：fluwx 自 v4 起附带 `ios/wechat_setup.rb`，会在 `pod install` 时自动写 Info.plist 与 entitlements。
> 本机缺少 `plist` gem（`sudo gem install plist`）时该脚本会静默失败（`system()` 不阻断 `pod install`），
> 因此这里采用**手工配置 + pubspec 声明**双保险；脚本对已存在的配置是幂等的，不会重复写入。
> `Info.plist` 中的 `CFBundleURLTypes`（`wxdcb4f64316ee1d04`）与 `LSApplicationQueriesSchemes`（`weixin` / `weixinULAPI`）此前已配置，无需改动。

## 3. 仍需完成的平台 / 服务端配置

### 3.1 微信开放平台（必做）

1. 登录 [微信开放平台](https://open.weixin.qq.com/) → 管理中心 → 移动应用 → 本应用（AppID `wxdcb4f64316ee1d04`）。
2. iOS 应用信息中填入 **Universal Link**：`https://apigateway.mpreader.com/wxul/`
   - 必须以 `https://` 开头、以 `/` 结尾，且域名不能带端口。
3. Android 应用信息中填写**包名 + 签名**：包名 `com.mpr.chaincode`，签名为 release 签名的 MD5（去掉冒号、小写）。
   调试签名与正式签名不同，签名不对会在微信回调时返回 `errCode = -1`。

### 3.2 服务端 AASA 文件（必做）

在 `apigateway.mpreader.com` 上放置 Apple 应用站点关联文件：

- 地址：`https://apigateway.mpreader.com/.well-known/apple-app-site-association`
  （兼容老系统可同时提供 `https://apigateway.mpreader.com/apple-app-site-association`）
- 要求：HTTPS、**无 302 跳转**、无需鉴权、`Content-Type: application/json`、文件大小 < 128KB。

内容（`appID` = `TeamID.BundleID`，本项目为 `K57V7V2MH5.com.fanmei.Linker`）：

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "K57V7V2MH5.com.fanmei.Linker",
        "paths": ["/wxul/*"]
      }
    ]
  }
}
```

- `paths` 必须覆盖微信配置的 Universal Link 路径（`/wxul/` 及子路径）。
- 建议 `https://apigateway.mpreader.com/wxul/` 本身返回一个轻量落地页：微信会在校验时请求该链接，
  未安装 App 的用户在浏览器打开时也应看到正常内容（404 会影响校验体验）。
- ⚠️ 注意该域名当前同时作为生产 API 网关（`:11999`），AASA 必须挂在 **443** 端口的默认站点根路径下。

### 3.3 Apple Developer 账号（必做）

- App ID（`com.fanmei.Linker`）需勾选 **Associated Domains** 能力。
- 使用自动签名时 Xcode 会自动更新 Provisioning Profile；手动签名需重新生成并下载描述文件。

## 4. 生效链路

```text
用户点击「微信登录」
  → fluwx.authBy(NormalAuth)                     // 跳转微信客户端
      └─ 微信依据开放平台配置的 Universal Link 发起回调
          └─ iOS 通过 Associated Domains 拉起 App（applinks:apigateway.mpreader.com）
              └─ fluwx 插件（FlutterPlugin 已注册为 AppDelegate）接收 continueUserActivity
                  → WXApi.handleOpenURL → 回传 code
                      → AuthService.loginWithThirdParty(errCode == 0)
                          → UserService.saveToken() 写入 SharedPreferences + Constants.token
                              └─ Navigator.pop(context, {'refresh': true})
```

## 5. 自检清单

1. `xcrun simctl` / 真机安装后，用系统「备忘录」输入 `https://apigateway.mpreader.com/wxul/` 长按预览，应出现「在 fmlink 中打开」。
2. 真机访问 `https://apigateway.mpreader.com/.well-known/apple-app-site-association`，应直接返回 JSON。
3. 在 `pubspec.yaml` 设置 `fluwx.debug_logging: true` 可打开微信 SDK 日志，观察 `WXULCheckStep` 相关输出。
4. 微信登录失败常见码：`-1` 签名 / Universal Link 不匹配；`-2` 用户取消；`-4` 授权被拒绝。

## 6. 修改域名时的同步点

若日后更换域名（例如切换到正式域名），需同时改：

1. `lib/services/third_party_manager.dart` → `weChatUniversalLink`
2. `pubspec.yaml` → `fluwx.ios.universal_link`
3. `ios/Runner/Runner.entitlements` → `applinks:<新域名>`
4. 微信开放平台 iOS Universal Link
5. 服务端 AASA 的 `paths` 与部署域名
