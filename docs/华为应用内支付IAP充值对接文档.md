# 华为应用内支付（IAP）充值对接文档

| 项 | 说明 |
|---|---|
| 适用端 | HarmonyOS NEXT（Flutter 鸿蒙版）客户端 |
| 服务端 | 泛媒关联订单服务（com.mpr.panmedia.server） |
| 华为侧 | IAP Kit（HarmonyOS 5.0+）+ 服务端 REST API |
| 接口基址 | 与现有充值接口同域名同服务（`/pos` 前缀） |
| 文档版本 | v1.0（2026-09-30） |

---

## 1. 整体流程

```
Flutter App                          服务端                        华为
    │                                   │                            │
    │ ① GET /pos/v1/prepay/prepay_products_huawei（可选，拿商品列表）     │
    │──────────────────────────────────>│                            │
    │ ② iap.queryProducts([商品ID])      │                            │
    │─────────────────────────────────────────────────────────────────>│
    │ ③ iap.purchase(product) 拉起华为收银台                             │
    │─────────────────────────────────────────────────────────────────>│
    │ <── PurchaseResultInfo: purchaseToken + purchaseOrderId ─────────│
    │                                   │                            │
    │ ④ POST /pos/v1/prepay/prepay_huawei {unification_id,             │
    │    purchase_token, purchase_order_id}                            │
    │──────────────────────────────────>│ ⑤ 订单状态查询+JWS验签      │
    │                                   │ ⑥ 校验+事务入账            │
    │                                   │ ⑦ 订单确认发货(confirm) ──>│
    │ <── {resultCode:"00000000"} ──────│                            │
```

**职责边界**：客户端只负责发起购买并回传两个凭据；订单真伪校验、入账、发货确认全部由服务端完成。客户端不得以支付成功页截图等作为入账依据。

---

## 2. 服务端接口

### 2.1 获取华为商品列表

```
GET /pos/v1/prepay/prepay_products_huawei
```

**请求参数**：无

**响应**：

```json
{
  "resultCode": "00000000",
  "resultMsg": "SUCCESS",
  "data": [
    { "pro_id": "com.xxx.huawei.1", "price": 6.0 },
    { "pro_id": "com.xxx.huawei.2", "price": 18.0 }
  ]
}
```

> `price` 单位为元。`pro_id` 即华为 AGC 后台配置的商品 ID，用于 `iap.queryProducts`。

### 2.2 华为充值验证入账（核心接口）

```
POST /pos/v1/prepay/prepay_huawei
Content-Type: application/json
```

**请求参数**（三个均必填）：

| 参数 | 类型 | 说明 |
|---|---|---|
| unification_id | string | 用户统一平台 ID |
| purchase_token | string | `PurchaseResultInfo.purchaseToken` |
| purchase_order_id | string | `PurchaseResultInfo.purchaseOrderId` |

```json
{
  "unification_id": "123456",
  "purchase_token": "xxxx.yyyy.zzzz...",
  "purchase_order_id": "WX2026xxxxx..."
}
```

**响应**：

| resultCode | 含义 | 客户端处理 |
|---|---|---|
| `00000000` | 充值成功 | 刷新余额，提示成功 |
| `88888822` | 华为支付凭证已验证（重复提交） | **按成功处理**（幂等），刷新余额即可 |
| `88888821` | 华为支付验证失败 | 凭据存本地待补发，可重试 |
| `88888823` | 获取华为服务端凭证失败 | 服务端配置问题，可重试 |
| `88888824` | 华为充值商品不存在 | 商品配置不一致，联系服务端 |
| `88888825` | 华为订单状态非已购买（含线上拒绝沙盒单、已退款单） | 提示用户，不重试 |
| `POS-000600021` | 参数错误 | 检查三参数是否齐全 |
| `01111111` | 系统异常 | 凭据存本地待补发，可重试 |

### 2.3 查询余额

```
GET /pos/v1/prepay/total_balance?unification_id={}&platform=3
```

**响应 data**：`{ "total_amount": 30.0, "platform": 3, ... }`（`total_amount` 单位元）

> `platform=3` 固定代表华为渠道。余额**按平台独立账户**，华为充的钱只在华为下单时扣。

### 2.4 查询充值记录

```
GET /pos/v1/prepay/prepay_record?unification_id={}&platform=3
```

**响应 data**：`[{ "id": "...", "amount": 6.0, "create_time": "2026-09-30 10:00:00" }]`（仅已入账记录，倒序）

### 2.5 余额支付下单（扣华为余额）

与现有苹果余额下单**同一接口**，两个参数不同：

| 参数 | 值 |
|---|---|
| `pay_type` | `3`（余额支付） |
| `platform` | `3`（华为） |

服务端按 `unification_id + platform=3` 查余额、扣款，余额不足返回 `88888803`。

---

## 3. 客户端对接步骤

### 3.1 AGC 后台前置（客户端/运营）

1. AGC 开通「应用内支付」服务
2. 配置 6 个**消耗型**商品，商品 ID 必须与服务端商品表、客户端 `queryProducts` 三方一致
3. AGC 配置**沙盒测试账号**（联调用），并在手机 AppGallery 用该账号登录
4. App 签名证书指纹已在 AGC 登记

> ⚠️ **未上架商品的可见性**：应用/商品未上架时，真实华为账号查询商品会报 `1001860003 商品信息无效`
> （`iap.queryProducts` 整批失败，一个商品都拿不到），只有 AGC「沙盒测试」名单里的账号才能查到并购买。
> 联调期必须保持沙盒账号登录；正式对外则要求商品已上架。

### 3.2 购买调用（ArkTS IAP Kit）

```typescript
import { iap } from '@kit.IAPKit';

// 查商品
let products = await iap.queryProducts({ productIds: ['com.xxx.huawei.1'] });

// 发起购买
let result: iap.PurchaseResultInfo = await iap.purchase({ product: products.productList[0] });

if (result.returnCode === 0) {
  // 回传服务端两个字段：
  //   result.purchaseToken    → purchase_token
  //   result.purchaseOrderId  → purchase_order_id
}
```

### 3.3 Flutter 桥接

pub.dev 的 `huawei_iap` 插件是安卓 HMS 版，**不适用于鸿蒙 NEXT**。Flutter 鸿蒙版需自建 MethodChannel 桥接 ArkTS：

```dart
// Flutter 侧
static const _channel = MethodChannel('com.fanmeilinker/iap');

Future<void> buy(String productId, String unificationId) async {
  final r = await _channel.invokeMethod('purchase', {'productId': productId});
  final resp = await dio.post('/pos/v1/prepay/prepay_huawei', data: {
    'unification_id': unificationId,
    'purchase_token': r['purchaseToken'],
    'purchase_order_id': r['purchaseOrderId'],
  });
  if (resp.data['resultCode'] == '00000000' || resp.data['resultCode'] == '88888822') {
    // 成功（88888822 = 幂等命中，同样算成功）
  } else {
    // 存本地待补发
  }
}
```

```typescript
// ohos 侧：Flutter ohos 工程内注册 channel，封装 iap.queryProducts / iap.purchase
// MethodChannel handler 返回 Map: { returnCode, purchaseToken, purchaseOrderId }
```

---

## 4. 客户端必做事项

1. **回传凭据本地持久化**：调用 `prepay_huawei` 前先把 `purchase_token + purchase_order_id + unification_id` 写入本地存储，服务端返回成功/88888822 后删除。App 启动时遍历补发——**保证用户不丢单**。
2. **幂等可安全重试**：服务端以 `purchaseOrderId` 幂等，同一订单重复提交只会入账一次（第二次返回 `88888822`），网络超时可大胆重试。
3. **`returnCode !== 0` 不调服务端**（用户取消等场景）。
4. **空值防御**：`purchaseToken` / `purchaseOrderId` 为空时不调服务端。
5. **余额按平台区分**：华为余额（platform=3）与 iOS 余额相互独立，界面展示与下单传参注意区分。

---

## 5. 联调环境说明

- 沙盒订单（`environment=SANDBOX`）：**开发/测试环境放行入账**（供联调），**高仿/线上环境拒绝**（返回 `88888825`）
- 服务端依赖配置（联调前确认已就位）：`thirdParty.properties` 中 `iap_kid_huawei`、`iap_issuer_huawei`、`iap_pri_key_path_huawei`（AGC「项目设置→API密钥→配置密钥」下载）、`iap_root_ca_path_huawei`（华为根证书 RootCaG2Ecdsa.cer）
- 私钥/证书文件只放服务器，**不要提交到代码仓库**

---

## 6. 常见问题

| 现象 | 原因与处理 |
|---|---|
| 服务端日志 `responseCode:"1001880006"` | JWT 鉴权失败：检查 kid/issuer/私钥配置与文件 |
| `88888824` 商品不存在 | 服务端商品表、AGC 商品、客户端 productIds 三方不一致 |
| 用户已付款但余额未到账 | 客户端本地补发凭据；服务端可查 `t_prepay_detail` 该订单状态 |
| 余额查询返回 `88888804` | 该用户华为账户无充值记录（未充过值），按余额 0 处理 |
| 线上环境返回 `88888825` 但测试单 | 沙盒单不能在线上环境入账，属预期拦截 |
| 鸿蒙端**一个商品都查不到**（Flutter 日志 `code=INVALID_PRODUCT`，华为 `1001860003`） | ① **账号**：手机上的华为账号不在 AGC 沙盒测试名单里，看不到「未上架」商品 —— 联调期必须有沙盒账号登录；② **商品**：某个 `productId` 在 AGC 不存在/未上架/类型不是消耗型 —— 批量查询里只要有一个无效就整批失败，看 `商店查不到的商品: [...]` 日志定位具体 ID |
| 加了一个新商品后其他档位也一起消失 | 同上②：华为批量查询是「全有或全无」，先把新商品在 AGC 上架或从 `IapService.products` 里临时移除 |
