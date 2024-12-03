
@Component
export struct TabFilesTitle {
  @Prop mainTitle: string | Resource;
  @Prop subTitle: string | Resource;
  onMoreClick?: () => void;

  build() {
    Column({space: 10}) {
      Row() {
        Column() {
          Text(this.mainTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.MARQUEE})

          Text(this.subTitle)
            .fontSize(11)
            .fontColor($r('app.color.light_gray'))
        }
        .height(30)
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)

        Image($r('app.media.ic_square_more'))
          .padding(5)
          .fillColor(Color.Black)
          .width(30)
          .height(30)
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick()
            }
          })
      }
      .padding({left: 20, right: 25})
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(40)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }
}