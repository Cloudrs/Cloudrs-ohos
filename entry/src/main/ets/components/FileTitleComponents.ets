@Component
export struct FileTitle {
  @Prop mainTitle: string | Resource;
  @Prop subTitle: string| Resource;
  @State isPress: boolean = false;

  build() {
    Column({space: 10}) {
      Row() {
        Column() {
          Text(this.mainTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)

          Text(this.subTitle)
            .fontSize(11)
            .fontColor($r('app.color.light_gray'))
        }
        .height(30)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)

        Image($r('app.media.ic_square_more'))
          .padding(5)
          .fillColor(this.isPress ? $r('app.color.light_gray') : Color.Black)
          .width(30)
          .height(30)
          .onClick((e) => {
            this.isPress = !this.isPress
          })
      }
      .padding({left: 20, right: 25})
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

}