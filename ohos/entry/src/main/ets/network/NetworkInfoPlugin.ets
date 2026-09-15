import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import connection from '@ohos.net.connection';

const TAG: string = 'NetworkInfoPlugin';
const CHANNEL_NAME: string = 'fmlink/network_info';

/**
 * 网络信息 MethodChannel（fmlink/network_info）
 *
 * 底层使用 HarmonyOS @ohos.net.connection：
 * getDefaultNet() → getNetCapabilities() → bearerTypes
 * 返回字符串：wifi / cellular / none / unknown
 * 需在 module.json5 声明 ohos.permission.GET_NETWORK_INFO。
 */
export class NetworkInfoPlugin implements MethodCallHandler {
  private channel: MethodChannel;

  constructor(flutterEngine: FlutterEngine) {
    this.channel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getNetworkType') {
      this.getNetworkType(result);
    } else {
      result.notImplemented();
    }
  }

  private async getNetworkType(result: MethodResult): Promise<void> {
    try {
      const netHandle = await connection.getDefaultNet();
      // netId 为 0 表示无默认网络（飞行模式）
      if (!netHandle || netHandle.netId === 0) {
        result.success('none');
        return;
      }
      const caps = await connection.getNetCapabilities(netHandle);
      const bearerTypes: Array<connection.NetBearType> = caps.bearerTypes ?? [];
      if (bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
        result.success('wifi');
      } else if (bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
        result.success('cellular');
      } else if (bearerTypes.length === 0) {
        // 无任何承载方式（飞行模式/网络已断开）：判定为无网络，
        // 与 Android(activeNetwork==null→none)/iOS(path 非 satisfied→none) 保持一致
        result.success('none');
      } else {
        result.success('unknown');
      }
    } catch (e) {
      console.error(`${TAG} getNetworkType error: ${e}`);
      result.success('none');
    }
  }
}