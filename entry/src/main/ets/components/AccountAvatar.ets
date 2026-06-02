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
  @State cacheUri: string = ''
  private loadKey: string = ''
  private displayAccountKey: string = ''

  private getFallbackText(): string {
    const text = (this.userId ?? '').trim()
    return text.length > 0 ? text.substring(0, 1).toUpperCase() : 'C'
  }

  private loadAvatarIfNeeded(): void {
    const key = `${this.baseUrl}|${this.userId}|${this.avatar}|${this.cookie}`
    const accountKey = `${this.baseUrl}|${this.userId}`
    if (key === this.loadKey) {
      return
    }
    const sameAccount = accountKey === this.displayAccountKey
    this.loadKey = key
    this.displayAccountKey = accountKey
    if (!sameAccount) {
      this.pixelMap = undefined
      this.cacheUri = ''
    }
    const source: AvatarSource = {
      baseUrl: this.baseUrl,
      userId: this.userId,
      avatar: this.avatar,
      cookie: this.cookie,
      refreshToken: this.refreshToken
    }
    const memoryAvatar = AvatarUtil.getMemoryCachedAvatar(source)
    if (memoryAvatar) {
      this.pixelMap = memoryAvatar
    }
    this.cacheUri = AvatarUtil.getAvatarCacheUri(source)
    console.info(TAG, `account avatar load start, memory=${!!memoryAvatar}, cacheUri=${this.cacheUri.length > 0}`)
    if (memoryAvatar || this.cacheUri.length > 0) {
      return
    }
    const start = Date.now()
    AvatarUtil.loadAvatar(source)
      .then((pixMap?: PixelMap) => {
        if (pixMap && key === this.loadKey) {
          this.pixelMap = pixMap
          this.cacheUri = AvatarUtil.getAvatarCacheUri(source)
          console.info(TAG, `account avatar loaded, cost=${Date.now() - start}ms`)
          return
        }
      })
      .catch((err: Error) => {
        console.warn(TAG, `load avatar failed: ${err.message}`)
      })
  }

  build() {
    Stack() {
      Text(this.getFallbackText())
        .fontSize(this.avatarSize * 0.38)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.primary)
      if (this.cacheUri.length > 0) {
        Image(this.cacheUri)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
          .borderRadius(this.radius)
          .draggable(false)
      }
      if (this.pixelMap) {
        Image(this.pixelMap)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.radius)
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
