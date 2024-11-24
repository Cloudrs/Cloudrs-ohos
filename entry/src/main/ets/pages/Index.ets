
@Entry
@Component
struct Index {

  build() {
    Column() {
      Navigation() {

      }
      .toolbarConfiguration([
        {
          value: $r("app.string.navigation_toolbar_files"),
          icon: $r("app.media.ic_cloud_fill")
        },
        {
          value: $r("app.string.navigation_toolbar_photos"),
          icon: $r("app.media.ic_picture_fill")
        },
        {
          value: $r("app.string.navigation_toolbar_remote_download"),
          icon: $r("app.media.ic_remote_download")
        },
        {
          value: $r("app.string.navigation_toolbar_me"),
          icon: $r("app.media.ic_me")
        }
      ])
    }
    .padding(10)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
