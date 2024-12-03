import { LengthMetrics } from "@kit.ArkUI"

@Component
export struct FileMenu {
  build() {
    Menu() {
      MenuItem({content: $r('app.string.dir_enter')})
      MenuItem({content: $r('app.string.file_details')})
      MenuItem({content: $r('app.string.rename')})
      MenuItem({content: $r('app.string.copy')})
      MenuItem({content: $r('app.string.move')})
      MenuItem({content: $r('app.string.cloud_share')})
      MenuItem({content: $r('app.string.delete')})
    }
    .width(200)
    .menuItemDivider({strokeWidth: LengthMetrics.px(1), color: $r("app.color.menu_divider_line")})
  }
}