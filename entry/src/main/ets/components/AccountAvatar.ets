import { CloudThemeToken } from "../model/CloudTheme";
import { AvatarSource, AvatarUtil } from "../utils/AvatarUtil";

const TAG: string = 'AccountAvatar'

@Component
export struct AccountAvatar {
  @Prop baseUrl: string = ''
  @Prop userId: string = ''
  @Prop avatar: string = ''
  @Prop cookie: string = ''
  @Prop refreshToken: string = ''
  @Prop avatarSize: number = CloudThemeToken.iconBoxSm
  @Prop radius: number = CloudThemeToken.controlRadiusRoundLg
  @State pixelMap?: PixelMap = undefined
  private loadKey: string = ''

  private loadAvatarIfNeeded(): void {
    const key = `${this.baseUrl}|${this.userId}|${this.avatar}|${this.cookie}`
    if (key === this.loadKey) {
      return
    }
    this.loadKey = key
    this.pixelMap = undefined
    const source: AvatarSource = {
      baseUrl: this.baseUrl,
      userId: this.userId,
      avatar: this.avatar,
      cookie: this.cookie,
      refreshToken: this.refreshToken
    }
    AvatarUtil.loadAvatar(source)
      .then((pixMap?: PixelMap) => {
        if (pixMap && key === this.loadKey) {
          this.pixelMap = pixMap
        }
      })
      .catch((err: Error) => {
        console.warn(TAG, `load avatar failed: ${err.message}`)
      })
  }

  build() {
    Stack() {
      if (this.pixelMap) {
        Image(this.pixelMap)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.radius)
          .draggable(false)
      } else {
        Image($r('app.media.ic_default_avatar'))
          .width(this.avatarSize * 0.58)
          .height(this.avatarSize * 0.58)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }
    }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(this.radius)
      .borderWidth(CloudThemeToken.lineWidth)
      .borderColor(CloudThemeToken.line)
      .backgroundColor(CloudThemeToken.primarySoft)
      .onAppear(() => {
        this.loadAvatarIfNeeded()
      })
  }
}
