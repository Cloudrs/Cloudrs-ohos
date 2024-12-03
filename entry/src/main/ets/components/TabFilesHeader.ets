
@Component
export struct TabFilesHeader {
  @Prop isRoot: boolean;
  onBackClick?: () => void;
  onTransportClick?: () => void;
  onPersionClick?: () => void;

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
              if (this.onBackClick) {
                this.onBackClick()
              }
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
          .onClick(() => {
            if (this.onTransportClick) {
              this.onTransportClick()
            }
          })

          Button() {
            Image($r('app.media.ic_person'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.White)
          .onClick(() => {
            if (this.onPersionClick) {
              this.onPersionClick()
            }
          })
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
    .height(40)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }
}