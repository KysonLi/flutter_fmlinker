# 泛媒关联APP接口文档

## 1. 接口概述

本文档整理了泛媒关联APP中使用的后端接口，基于提供的URL定义代码。由于仅提供了URL路径，部分接口的详细参数和返回结构需要根据命名和路径推测。

## 2. 基础URL

根据代码中的宏定义，接口分为两个基础URL：
- `URL_ROOT`：主要接口基础路径
- `URL_ROOT_SAFE`：安全接口基础路径

## 3. 接口列表

### 3.1 核心功能接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 获取ISLI关联目标 | `/target-goods/app/v1/targets` | 根据ISLI编码获取关联的目标资源 | GET/POST |
| 扫描获取资源 | `/target-goods/app/v1/source/scan` | 扫码后获取资源（V2版本） | GET |
| 获取多目标资源 | `/chain-server/api/link_code_system/multi_targetsAll` | 获取多个ISLI编码的关联资源 | POST |
| 查询目标资源源数据 | `/target-goods/api/isli_storage_system/hls/query` | 查询目标资源的源数据信息 | POST |
| 刷新资源地址 | `/target-goods/app/v1/resources-address` | 刷新资源的访问地址 | GET |
| 获取源目标资源 | `/target-goods/app/v1/targets-more` | 获取源的更多关联资源 | GET |
| 获取图书资源列表 | `/target-goods/app/v1/source/info` | 获取图书资源列表 | GET |

### 3.2 历史记录接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 商品扫码历史 | `/target-goods/app/v1/goods/link` | 获取商品扫码历史记录 | GET |
| 资源扫码历史 | `/target-goods/app/v1/source/link` | 获取资源扫码历史记录 | GET |

### 3.3 图书相关接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 图书章节信息 | `/target-goods/app/v1/targets/chapter` | 获取图书章节信息 | GET |
| 下载ISLI列表 | `/api/personalserver/book/remote/target/download` | 下载ISLI编码列表 | GET/POST |
| 获取更多目标资源 | `/target-goods/app/v1/targets-more` | 获取更多关联的目标资源 | GET/POST |

### 3.4 系统接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 应用更新信息 | `/chain-server/api/link_code_system/update` | 获取应用更新信息 | GET |
| 启动广告 | `/target-goods/app/v1/advert/list` | 获取启动广告列表 | GET |

### 3.5 发现相关接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 发现内容 | `/target-goods/app/v1/goods/find` | 获取发现页面内容 | GET |

### 3.6 资源详情接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 资源详情 | `/target-goods/app/v1/resource/detail` | 获取资源详细信息 | GET |
| 源详情 | `/target-goods/app/v1/source/detail` | 获取源详细信息 | GET |
| 图书资源信息 | `/target-goods/app/v1/source/info` | 获取图书资源信息 | GET |

### 3.7 点赞相关接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 点赞资源 | `/target-goods/app/v1/resource/like` | 点赞资源 | POST |
| 取消点赞 | `/target-goods/app/v1/resource/unlike` | 取消点赞 | POST |
| 资源点赞用户 | `/target-goods/app/v1/resource/like/list` | 获取资源的点赞用户列表 | GET |
| 源点赞列表 | `/target-goods/app/v1/source/resource/like` | 获取源的点赞列表 | GET |
| 我的点赞 | `/target-goods/app/v1/resource/mylike` | 获取用户的点赞列表 | GET |

### 3.8 账号相关接口

| 接口名称 | URL路径 | 功能描述 | 请求方法 |
|---------|---------|---------|----------|
| 获取验证码 | `/chain-server/api/link_code_system/login/get_verification_code` | 获取登录验证码 | POST |
| 绑定手机号 | `/chain-server/api/link_code_system/login/bind_user_phone_number` | 绑定手机号 | POST |
| 密码登录 | `/chain-server/api/link_code_system/login/login_with_account` | 使用账号密码登录 | POST |
| 验证码登录 | `/chain-server/api/link_code_system/login/login_with_verification_code` | 使用验证码登录 | POST |
| 第三方登录 | `/chain-server/api/link_code_system/login/third_party` | 第三方账号登录 | POST |
| 南方云登录 | `/chain-server/api/link_code_system/login/login_spm` | 南方云账号登录 | POST |
| 设置密码 | `/chain-server/api/link_code_system/login/set_user_password` | 设置用户密码 | POST |
| 退出登录 | `/chain-server/api/link_code_system/logout` | 用户退出登录 | POST |
| 修改昵称 | `/chain-server/api/link_code_system/login/change_user_name` | 修改用户昵称 | POST |
| 设备检查 | `/pls/v1/check` | 检查设备唯一性 | GET |
| 上传头像 | `/target-goods/app/v1/image/upload` | 上传用户头像 | POST |
| 设备列表 | `/chain-server/api/link_code_system/login/v2/userdevice_list` | 获取用户设备列表 | GET |
| 删除设备 | `/chain-server/api/link_code_system/login/v2/userdevice_delete` | 删除用户设备 | POST |

## 4. 接口详细说明

### 4.1 获取ISLI关联目标

**URL**: `/target-goods/app/v1/targets`

**功能**: 根据ISLI编码获取关联的目标资源

**请求方法**: GET/POST

**请求参数**:
- `isli_code`: ISLI编码（必填）
- 可能的其他参数：`prefix_code`（前缀码）

**返回数据**:
- 关联的目标资源列表
- 资源类型、名称、地址等信息

### 4.2 扫描获取资源 (V2)

**URL**: `/target-goods/app/v1/source/scan`

**功能**: 扫码后获取资源（V2版本，优化版本）

**请求方法**: GET

**请求参数**:
- 路径参数: `/isliCode`（ISLI编码，必填）
- `pageIndex`: 页码（可选，默认1）
- `pageSize`: 每页数量（可选，默认50）
- `unificationId`: 统一ID（可选，未登录时使用设备ID）
- `orderBy`: 排序方式（可选，默认ORDER_BY_PUBLISH_TIME）
- `hasScanUse`: 是否扫码使用（可选，默认false）
- `versionCode`: 版本号（可选）

**请求头**:
- `token`: 用户认证令牌（如果已登录）

**返回数据**:
```json
{
  "data": {
    "resultCode": "00000000",
    "data": {
      "serviceCode": "000000",
      "prefixCode": "1001894605",
      "goodsId": "123",
      "goodsName": "图书名称",
      "goodsImage": "http://...",
      "goodsDesc": "图书描述",
      "shopId": "456",
      "resourceCount": "10",
      "sourceCount": "5",
      "versionCode": "1",
      "isBenefit": false,
      "benefitPrice": "0",
      "totalPrice": "0",
      "source": {
        "sourceId": "789",
        "sourceIdentifier": "...",
        "sourceFragment": "章节片段",
        "chapterTitle": "章节标题",
        "chapterNum": "1",
        "free": true,
        "price": "0",
        "pay": false
      },
      "targetList": [
        {
          "targetId": "101",
          "targetIdentifier": "...",
          "targetName": "目标名称",
          "targetFormat": "...",
          "targetStatus": "...",
          "resourceCount": "2",
          "resources": [
            {
              "resourceId": "201",
              "resourceName": "资源名称",
              "resourceType": "1",
              "resourceAddress": "http://...",
              "resourcePoster": "http://...",
              "resourceSize": "1024000",
              "resourceSuffix": "mp4",
              "likeCount": "5",
              "hasLike": false
            }
          ]
        }
      ]
    }
  }
}
```

### 4.3 获取多目标资源

**URL**: `/chain-server/api/link_code_system/multi_targetsAll`

**功能**: 获取多个ISLI编码的关联资源

**请求方法**: POST

**请求参数**:
- `isli_codes`: ISLI编码列表（必填，数组）

**返回数据**:
- 多个ISLI编码的关联资源列表

### 4.4 查询目标资源源数据

**URL**: `/target-goods/api/isli_storage_system/hls/query`

**功能**: 查询目标资源的源数据信息

**请求方法**: GET/POST

**请求参数**:
- `isli_code`: ISLI编码（必填）
- 可能的其他参数：资源ID等

**返回数据**:
- 资源的源数据信息
- 可能包括资源的存储地址、格式、大小等

### 4.5 刷新资源地址

**URL**: `/target-goods/app/v1/resources-address`

**功能**: 刷新资源的访问地址（可能用于处理临时URL）

**请求方法**: GET/POST

**请求参数**:
- `resource_id`: 资源ID（必填）
- 可能的其他参数：过期时间等

**返回数据**:
- 刷新后的资源访问地址

### 4.6 商品扫码历史

**URL**: `/target-goods/app/v1/goods/link`

**功能**: 获取商品扫码历史记录

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（可能需要）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 扫码历史记录列表
- 包含ISLI编码、扫码时间、关联商品信息等

### 4.7 资源扫码历史

**URL**: `/target-goods/app/v1/source/link`

**功能**: 获取资源扫码历史记录

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（可能需要）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 资源扫码历史记录列表
- 包含ISLI编码、扫码时间、资源信息等

### 4.8 图书章节信息

**URL**: `/target-goods/app/v1/targets/chapter`

**功能**: 获取图书章节信息

**请求方法**: GET

**请求参数**:
- `prefix_code`: 前缀码（必填）
- 可能的其他参数：图书ID等

**返回数据**:
- 图书章节列表
- 章节名称、顺序、关联资源等

### 4.9 下载ISLI列表

**URL**: `/api/personalserver/book/remote/target/download`

**功能**: 下载ISLI编码列表

**请求方法**: GET/POST

**请求参数**:
- 可能的参数：图书ID、用户ID等

**返回数据**:
- ISLI编码列表
- 可能包含编码对应的资源信息

### 4.10 获取更多目标资源

**URL**: `/target-goods/app/v1/targets-more`

**功能**: 获取更多关联的目标资源

**请求方法**: GET/POST

**请求参数**:
- `isli_code`: ISLI编码（必填）
- 可能的其他参数：分页信息等

**返回数据**:
- 更多关联资源列表

### 4.11 应用更新信息

**URL**: `/chain-server/api/link_code_system/update`

**功能**: 获取应用更新版本信息

**请求方法**: GET

**请求参数**:
- `platformType`: 平台类型（必填，如"ios"或"android"）

**请求头**:
- `token`: 用户认证令牌（如果已登录）

**返回数据**:
```json
{
  "status": "0",
  "result": {
    "versionNum": "1.0.0",      // 最新版本号
    "updatePolicy": "0",         // 更新策略（1: 强制更新, 0: 可选更新）
    "svnVersion": "12345",       // SVN版本号
    "filePath": "http://...",     // 安装包下载地址
    "changeContent": "更新内容"    // 更新内容描述
  }
}
```

**示例请求**:
```http
GET /chain-server/api/link_code_system/update?platformType=ios
Authorization: Bearer {token}
```

### 4.12 启动广告

**URL**: `/target-goods/app/v1/advert/list`

**功能**: 获取启动广告列表

**请求方法**: GET

**请求参数**:
- 可能的参数：设备类型、系统版本等

**返回数据**:
- 广告列表
- 包括广告图片、链接、展示时间等

### 4.13 发现内容

**URL**: `/target-goods/app/v1/goods/find`

**功能**: 获取发现页面内容

**请求方法**: GET

**请求参数**:
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）
- 可能的其他参数：推荐类型等

**返回数据**:
- 发现页面内容
- 包括今日推荐、热搜词、热门关注、点赞最多等

### 4.14 资源详情

**URL**: `/target-goods/app/v1/resource/detail`

**功能**: 获取资源详细信息

**请求方法**: GET

**请求参数**:
- `resource_id`: 资源ID（必填）

**返回数据**:
- 资源详细信息
- 包括资源类型、名称、地址、描述、是否付费等

### 4.15 源详情

**URL**: `/target-goods/app/v1/source/detail`

**功能**: 获取源详细信息

**请求方法**: GET

**请求参数**:
- `source_id`: 源ID（必填）

**返回数据**:
- 源详细信息
- 包括源名称、描述、关联资源等

### 4.16 图书资源信息

**URL**: `/target-goods/app/v1/source/info`

**功能**: 获取图书资源信息

**请求方法**: GET

**请求参数**:
- `isli_code`: ISLI编码（必填）
- 可能的其他参数：图书ID等

**返回数据**:
- 图书资源信息
- 包括图书基本信息、关联资源等

### 4.17 点赞资源

**URL**: `/target-goods/app/v1/resource/like`

**功能**: 点赞资源

**请求方法**: POST

**请求参数**:
- `resource_id`: 资源ID（必填）
- `user_id`: 用户ID（可能需要）

**返回数据**:
- 点赞结果
- 包括是否成功、点赞数量等

### 4.18 取消点赞

**URL**: `/target-goods/app/v1/resource/unlike`

**功能**: 取消点赞

**请求方法**: POST

**请求参数**:
- `resource_id`: 资源ID（必填）
- `user_id`: 用户ID（可能需要）

**返回数据**:
- 取消点赞结果
- 包括是否成功、点赞数量等

### 4.19 资源点赞用户

**URL**: `/target-goods/app/v1/resource/like/list`

**功能**: 获取资源的点赞用户列表

**请求方法**: GET

**请求参数**:
- `resource_id`: 资源ID（必填）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 点赞用户列表
- 包括用户ID、昵称、头像等

### 4.20 源点赞列表

**URL**: `/target-goods/app/v1/source/resource/like`

**功能**: 获取源的点赞列表

**请求方法**: GET

**请求参数**:
- `source_id`: 源ID（必填）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 点赞列表
- 包括资源ID、点赞数量等

### 4.21 我的点赞

**URL**: `/target-goods/app/v1/resource/mylike`

**功能**: 获取用户的点赞列表

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（必填）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 用户点赞列表
- 包括资源ID、资源名称、点赞时间等

### 4.27 获取验证码

**URL**: `/chain-server/api/link_code_system/login/get_verification_code`

**功能**: 获取登录验证码

**请求方法**: POST

**请求参数**:
- `phone_number`: 手机号（必填）

**返回数据**:
- 验证码发送结果
- 包括是否成功、倒计时等

### 4.28 绑定手机号

**URL**: `/chain-server/api/link_code_system/login/bind_user_phone_number`

**功能**: 绑定手机号

**请求方法**: POST

**请求参数**:
- `phone_number`: 手机号（必填）
- `verification_code`: 验证码（必填）
- `user_id`: 用户ID（可能需要）

**返回数据**:
- 绑定结果
- 包括是否成功、用户信息等

### 4.29 密码登录

**URL**: `/chain-server/api/link_code_system/login/login_with_account`

**功能**: 使用账号密码登录

**请求方法**: POST

**请求参数**:
- `account`: 账号（必填）
- `password`: 密码（必填）

**返回数据**:
- 登录结果
- 包括是否成功、用户信息、token等

### 4.30 验证码登录

**URL**: `/chain-server/api/link_code_system/login/login_with_verification_code`

**功能**: 使用验证码登录

**请求方法**: POST

**请求参数**:
- `phone_number`: 手机号（必填）
- `verification_code`: 验证码（必填）

**返回数据**:
- 登录结果
- 包括是否成功、用户信息、token等

### 4.31 第三方登录

**URL**: `/chain-server/api/link_code_system/login/third_party`

**功能**: 第三方账号登录

**请求方法**: POST

**请求参数**:
- `third_party_type`: 第三方类型（必填）
- `third_party_id`: 第三方ID（必填）
- `access_token`: 访问令牌（可能需要）

**返回数据**:
- 登录结果
- 包括是否成功、用户信息、token等

### 4.32 南方云登录

**URL**: `/chain-server/api/link_code_system/login/login_spm`

**功能**: 南方云账号登录

**请求方法**: POST

**请求参数**:
- `spm_account`: 南方云账号（必填）
- `spm_password`: 南方云密码（必填）

**返回数据**:
- 登录结果
- 包括是否成功、用户信息、token等

### 4.33 设置密码

**URL**: `/chain-server/api/link_code_system/login/set_user_password`

**功能**: 设置用户密码

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `password`: 新密码（必填）
- `verification_code`: 验证码（可能需要）

**返回数据**:
- 设置结果
- 包括是否成功

### 4.34 退出登录

**URL**: `/chain-server/api/link_code_system/logout`

**功能**: 用户退出登录

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（可能需要）
- `token`: 认证令牌（可能需要）

**返回数据**:
- 退出结果
- 包括是否成功

### 4.35 修改昵称

**URL**: `/chain-server/api/link_code_system/login/change_user_name`

**功能**: 修改用户昵称

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `nickname`: 新昵称（必填）

**返回数据**:
- 修改结果
- 包括是否成功、新昵称等

### 4.36 设备检查

**URL**: `/pls/v1/check`

**功能**: 检查设备唯一性

**请求方法**: GET

**请求参数**:
- `device_id`: 设备ID（必填）

**返回数据**:
- 检查结果
- 包括设备是否唯一、状态等

### 4.37 上传头像

**URL**: `/target-goods/app/v1/image/upload`

**功能**: 上传用户头像

**请求方法**: POST (multipart/form-data)

**请求参数**:
- `unificationId`: 统一ID（必填）
- `deviceId`: 设备ID（必填）
- `imageFile`: 头像文件（必填，multipart/form-data）

**请求头**:
- `token`: 用户认证令牌（如果已登录）

**返回数据**:
```json
{
  "resultCode": "0",
  "data": {
    "avatarUrl": "http://..."
  }
}
```

### 4.38 设备列表

**URL**: `/chain-server/api/link_code_system/login/v2/userdevice_list`

**功能**: 获取用户设备列表

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（必填）

**返回数据**:
- 设备列表
- 包括设备ID、设备名称、登录时间等

### 4.39 删除设备

**URL**: `/chain-server/api/link_code_system/login/v2/userdevice_delete`

**功能**: 删除用户设备

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `device_id`: 设备ID（必填）

**返回数据**:
- 删除结果
- 包括是否成功

### 4.40 特价图书

**URL**: `/target-goods/app/v1/derate-goods`

**功能**: 获取特价图书列表

**请求方法**: GET

**请求参数**:
- `pageIndex`: 页码（可选，默认1）
- `pageSize`: 每页数量（可选，默认20）

**请求头**:
- `token`: 用户认证令牌（如果已登录）

**返回数据**:
- 特价图书列表
- 包括图书ID、封面、名称、原价、特价等

### 4.41 预付费产品

**URL**: `/chain-server/api/link_code_system/prepay/prepay_products`

**功能**: 获取预付费产品列表

**请求方法**: GET

**请求参数**:
- 可能的参数：产品类型等

**返回数据**:
- 预付费产品列表
- 包括产品ID、名称、价格、描述等

### 4.42 充值

**URL**: `/chain-server/api/link_code_system/prepay/prepay_ios`

**功能**: 充值（iOS）

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `product_id`: 产品ID（必填）
- `amount`: 充值金额（必填）

**返回数据**:
- 充值结果
- 包括是否成功、订单信息、支付链接等

### 4.43 充值V2

**URL**: `/chain-server/api/link_code_system/prepay/prepay_ios_v2`

**功能**: 充值V2（iOS）

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `product_id`: 产品ID（必填）
- `amount`: 充值金额（必填）

**返回数据**:
- 充值结果
- 包括是否成功、订单信息、支付链接等

### 4.44 用户余额

**URL**: `/chain-server/api/link_code_system/prepay/total_balance`

**功能**: 获取用户余额

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（必填）

**返回数据**:
- 用户余额信息
- 包括余额金额、可用余额等

### 4.45 购买商品

**URL**: `/chain-server/api/link_code_system/pay`

**功能**: 购买商品

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `goodsId`: 商品ID（必填）
- `amount`: 购买金额（必填）
- `pay_type`: 支付方式（可选）

**返回数据**:
- 购买结果
- 包括是否成功、订单信息、支付链接等

### 4.46 购买商品V2

**URL**: `/chain-server/api/link_code_system/v2/pay`

**功能**: 购买商品V2

**请求方法**: POST

**请求参数**:
- `user_id`: 用户ID（必填）
- `goodsId`: 商品ID（必填）
- `amount`: 购买金额（必填）
- `pay_type`: 支付方式（可选）

**返回数据**:
- 购买结果
- 包括是否成功、订单信息、支付链接等

### 4.47 订单列表

**URL**: `/pos/v1/order/target`

**功能**: 获取订单列表

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（必填）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 订单列表
- 包括订单ID、商品信息、金额、状态等

### 4.48 充值历史

**URL**: `/chain-server/api/link_code_system/prepay/prepay_record`

**功能**: 获取充值历史

**请求方法**: GET

**请求参数**:
- `user_id`: 用户ID（必填）
- `page`: 页码（可选）
- `page_size`: 每页数量（可选）

**返回数据**:
- 充值历史记录
- 包括充值ID、金额、时间、状态等

### 4.49 应用支付

**URL**: `/openapi/dms/brand-service/v1/un-special-terminal`

**功能**: 应用支付

**请求方法**: POST

**请求参数**:
- `order_id`: 订单ID（必填）
- `amount`: 支付金额（必填）
- `pay_type`: 支付方式（可选）

**返回数据**:
- 支付结果
- 包括是否成功、支付状态等

### 4.50 事件上报

**URL**: `/data-collection/v1/handle`

**功能**: 上报应用事件数据

**请求方法**: POST

**请求参数**:
- `event_type`: 事件类型（必填）
- `event_data`: 事件数据（必填）
- `device_id`: 设备ID（可选）
- `user_id`: 用户ID（可选）

**返回数据**:
- 上报结果
- 包括是否成功

### 4.51 资源阅读上报

**URL**: `/target-goods/app/v1/resource/read`

**功能**: 上报资源阅读数据

**请求方法**: POST

**请求参数**:
- `resource_id`: 资源ID（必填）
- `user_id`: 用户ID（可选）
- `read_duration`: 阅读时长（可选）
- `read_progress`: 阅读进度（可选）

**返回数据**:
- 上报结果
- 包括是否成功

## 5. 接口调用注意事项

1. **认证**: 所有接口都可能需要用户认证，通过请求头传递token
   - 请求头格式: `token: {用户认证令牌}`
   - 未登录状态下，部分接口可能仍可访问，但功能可能受限

2. **通用参数**: 大部分接口可能需要以下通用参数
   - `p_version`: 服务器版本（默认值: "1"）
   - `terminal_type`: 终端类型
   - `terminal_serial`: 终端序列号
   - `terminal_id`: 终端ID
   - `platform`: 平台类型（如"ios"或"android"）
   - `app_version_code`: 应用版本号
   - `app_platform`: 应用平台

3. **参数格式**: 确保参数格式正确，特别是ISLI编码格式
4. **错误处理**: 处理接口返回的错误信息，如404、500等状态码
   - 服务器返回码说明:
     - `0`: 成功
     - `2`: 失败
     - `3`: 失败
     - `1001`: 失败
     - `201`: 账号已注册
     - `6000`: 购买重复
5. **缓存策略**: 合理使用缓存，减少重复请求
6. **网络状态**: 处理网络异常情况，提供离线支持

## 6. 服务器返回格式

### 6.1 通用返回结构
```json
{
  "return_code": "0",  // 返回码
  "message": "成功",   // 返回消息
  "data": { ... }      // 业务数据
}
```

### 6.2 其他可能的返回键
- `resultCode`: 结果码
- `resultMsg`: 结果消息
- `status`: 状态

## 6. 示例请求

### 6.1 扫码获取资源 (V2)

```http
POST /target-goods/app/v1/source/scan
Content-Type: application/json

{
  "isli_code": "9787107320000"
}
```

### 6.2 获取ISLI关联目标

```http
GET /target-goods/app/v1/targets?isli_code=9787107320000
```

## 7. 总结

本接口文档基于提供的URL定义代码整理，部分接口的详细参数和返回结构需要根据实际调用情况进一步确认。在开发过程中，建议参考老APP的接口调用实现，确保与后端服务的正确交互。