import AbilityStage from '@ohos.app.ability.AbilityStage';
import { preInit, setLogEnabled, InternalPlugin } from '@umeng/analytics';
import { ApmPlugin } from '@umeng/apm';

/**
 * 友盟 SDK 鸿蒙侧入口。
 *
 * 只做 preInit（预初始化，不采集、不上报）；
 * 真正的 init() 由 Flutter 插件（umeng_common_sdk）在用户同意隐私政策后触发，
 * 保证未同意前不产生任何数据采集（合规要求）。
 */
export default class MyAbilityStage extends AbilityStage {
  onCreate(): void {
    setLogEnabled(false);
    preInit({
      context: this.context.getApplicationContext(),
      plugins: [new InternalPlugin(), new ApmPlugin()],
    });
  }
}
