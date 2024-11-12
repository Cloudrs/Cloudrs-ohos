@Entry
@Component
struct LoginPage {

  build() {
    Column({space: 10}) {
      Image($r("app.media.cloudreve"))
        .width(100)
        .margin({top: 100, bottom: 20})

      Text($r("app.string.login_title"))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Stack() {
        TextInput()
          .borderRadius(10)

        Row() {
          Image($r("app.media.ic_worldclock_fill"))
            .width(20)
            .margin({left: 5, right: 5})

          Text("https://")

          TextInput({
            placeholder: $r("app.string.login_address")
          })
            .backgroundColor("#f4f6f5")
            .padding({left: 0})
            .layoutWeight(1)
        }
      }
      .alignContent(Alignment.Start)
      .width("100%")

      Button($r("app.string.login_continue"))
        .width("100%")

      Text($r("app.string.login_tips"))
        .fontSize(11)
        .fontColor($r("app.color.light_gray"))
        .margin({left: 10, right: 10})

      Blank()

      Row({space: 10}) {
        Image($r("app.media.ic_qrcode_scan"))
          .width(30)
          .borderColor($r("app.color.light_light_gray"))
          .borderWidth(1)
          .borderRadius(15)
          .padding(3)

        Image($r("app.media.ic_person_2"))
          .width(30)
          .borderColor($r("app.color.light_light_gray"))
          .borderWidth(1)
          .borderRadius(15)
          .padding(3)
      }

      Row({space: 2}) {
        Text("使用Cloudreve即表示您接受我们的")
          .fontSize(11)
          .fontColor($r("app.color.light_gray"))
        Text("服务条款")
          .fontSize(11)
          .fontColor($r("app.color.select_primary"))
        Text("和")
          .fontSize(11)
          .fontColor($r("app.color.light_gray"))
        Text("隐私政策")
          .fontSize(11)
          .fontColor($r("app.color.select_primary"))
      }
    }
    .height("100%")
    .padding(20)
  }
}