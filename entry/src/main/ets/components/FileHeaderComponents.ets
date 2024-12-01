import { HMRouterMgr } from "@hadss/hmrouter";

@Component
export struct FileHeader {
  @Prop isRoot: boolean;

  build() {
    Column() {
      Row() {
        Row({ space: 10 }) {
          if (!this.isRoot) {
            Button() {
              Image($r('app.media.ic_back'))
                .padding(5)
                .fillColor(Color.Black)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(Color.White)
            .onClick(() => {
              HMRouterMgr.pop()
            })
            .transition(TransitionEffect.OPACITY.animation({duration: 200})
              .combine(TransitionEffect.scale({x: 0, y: 0}).animation({duration: 200})))
          }

          Search({ placeholder: $r("app.string.header_search") })
            .searchIcon({ color: Color.Black })
            .backgroundColor(Color.White)
        }
        .width('50%')

        Row({ space: 10 }) {
          Button() {
            Image($r('app.media.ic_transport'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.light_light_gray'))

          Button() {
            Image($r('app.media.ic_person'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.White)
        }
        .width(100)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(36)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({ left: 10, right: 10 })
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}