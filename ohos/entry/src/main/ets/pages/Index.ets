
import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { SPLASH_HIDE_EVENT } from '../splash/SplashPlugin';

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'
// 兜底：即使 Flutter 首帧通知丢失，也不能让启动页一直盖住界面
const SPLASH_FALLBACK_MS: number = 3000

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @State showSplash: boolean = true;
  @State splashOpacity: number = 0;
  private fallbackTimer: number = -1;
  private removeTimer: number = -1;

  aboutToAppear(): void {
    this.context.eventHub.on(SPLASH_HIDE_EVENT, this.hideSplash);
    // 系统启动窗口是纯白背景，这里淡入，避免图标直接“弹”出来
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.splashOpacity = 1;
    });
    this.fallbackTimer = setTimeout(() => this.hideSplash(), SPLASH_FALLBACK_MS);
  }

  aboutToDisappear(): void {
    this.context.eventHub.off(SPLASH_HIDE_EVENT);
    if (this.fallbackTimer !== -1) {
      clearTimeout(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
    if (this.removeTimer !== -1) {
      clearTimeout(this.removeTimer);
      this.removeTimer = -1;
    }
  }

  /**
   * 与 Android/iOS 启动页保持同一套视觉：白底 + 靠底部居中，
   * 左侧 56 圆角 logo，右侧中文名（上）/英文名（下），四边与 logo 对齐。
   */
  private hideSplash = (): void => {
    if (!this.showSplash) {
      return;
    }
    if (this.fallbackTimer !== -1) {
      clearTimeout(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.splashOpacity = 0;
    });
    this.removeTimer = setTimeout(() => {
      this.showSplash = false;
    }, 220);
  }

  build() {
    Stack() {
      Column() {
        FlutterPage({ viewId: this.viewId })
      }
      .width('100%')
      .height('100%')

      if (this.showSplash) {
        Column() {
          Row() {
            Image($r('app.media.app_icon'))
              .width(56)
              .height(56)
              .borderRadius(10)
            // 中文 22 与英文 17 的文本宽度几乎一致（各约 88），左右两端自然对齐；
            // 容器高度 = logo 高度，上下 SpaceBetween 使首行贴 logo 顶、末行贴 logo 底
            Column() {
              Text('泛媒关联')
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
              Text('ISLI SCANr')
                .fontSize(17)
                .fontColor('#8C8C8C')
            }
            .height(56)
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 14 })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 88 })
        .backgroundColor(Color.White)
        .opacity(this.splashOpacity)
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
