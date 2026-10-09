import { CommonUtil } from '../../utils/CommonUtil'
import { CloudThemeToken } from '../../model/CloudTheme'
import { CloudRouter } from '../../utils/CloudRouter'
import Constant from '../../model/Constant'
import { ACCOUNT_PROFILE_STORE_KEY, AccountProfileStore } from '../../model/AccountProfileStore'
import { ChipTone, SettingChip } from './SettingRows'

// 「我的」页顶部资料卡：头像 + 昵称/账号 + 用户组/UID/加入天数，点击进入账号与安全页
@Component
export struct MineProfileCard {
  // 账号状态单例（@Observed，经 AppStorage 共享）；必须用 @StorageLink 绑定，普通字段持有不会触发 V1 组件刷新
  @StorageLink(ACCOUNT_PROFILE_STORE_KEY) store: AccountProfileStore = AccountProfileStore.instance

  build() {
    Row({ space: CloudThemeToken.spacingPanel }) {
      this.avatarView(CloudThemeToken.avatarLargeSize)
      Column({ space: CloudThemeToken.spacingXs }) {
        Text(this.store.displayName())
          .fontSize(CloudThemeToken.textSizeHero)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.store.accountName())
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Flex({ wrap: FlexWrap.Wrap }) {
          if ((this.store.user?.group?.name ?? '').length > 0) {
            SettingChip({ text: this.store.user?.group?.name ?? '', tone: ChipTone.PRIMARY })
              .margin({ right: CloudThemeToken.spacingMd, top: CloudThemeToken.spacingMd })
          }
          if ((this.store.user?.id ?? '').length > 0) {
            SettingChip({ text: `UID ${this.store.user?.id ?? ''}` })
              .margin({ right: CloudThemeToken.spacingMd, top: CloudThemeToken.spacingMd })
          }
          if (this.store.createdDays() > 0) {
            SettingChip({ text: `已加入 ${this.store.createdDays()} 天` })
              .margin({ top: CloudThemeToken.spacingMd })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_chevron_right'))
        .width(CloudThemeToken.iconSm)
        .height(CloudThemeToken.iconSm)
        .fillColor(CloudThemeToken.textSecondary)
        .draggable(false)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPage)
    .borderRadius(CloudThemeToken.settingGroupRadius)
    .backgroundColor(CloudThemeToken.surface)
    .stateStyles({
      pressed: { .backgroundColor(CloudThemeToken.surfaceSubtle) },
      normal: { .backgroundColor(CloudThemeToken.surface) }
    })
    .onClick(() => {
      CloudRouter.push(Constant.ACCOUNT_SECURITY_PAGE)
    })
  }

  @Builder avatarView(size: number) {
    Stack() {
      Text(this.store.displayName().substring(0, 1).toUpperCase())
        .fontSize(size * 0.36)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.primary)
      if (this.store.avatarCacheUri.length > 0) {
        Image(this.store.avatarCacheUri)
          .width(size).height(size)
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
          .borderRadius(size / CloudThemeToken.halfDivisor)
          .draggable(false)
      }
      if (this.store.avatar) {
        Image(this.store.avatar)
          .width(size).height(size)
          .objectFit(ImageFit.Cover)
          .borderRadius(size / CloudThemeToken.halfDivisor)
          .draggable(false)
      }
    }
    .width(size)
    .height(size)
    .borderRadius(size / CloudThemeToken.halfDivisor)
    .borderWidth(CloudThemeToken.lineWidth)
    .borderColor(CloudThemeToken.line)
    .backgroundColor(CloudThemeToken.primarySoft)
    .clip(true)
  }
}

// 「我的」页存储卡：已用/总量、容量条、剩余与存储包、更新时间
@Component
export struct MineStorageCard {
  @StorageLink(ACCOUNT_PROFILE_STORE_KEY) store: AccountProfileStore = AccountProfileStore.instance

  build() {
    Column({ space: CloudThemeToken.spacingCard }) {
      Row() {
        Text('存储空间')
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .layoutWeight(1)
        Text(this.storagePercentText())
          .fontSize(CloudThemeToken.textSizeBodyPlus)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.primary)
      }
      .width('100%')

      Text(this.storageUsedText())
        .fontSize(CloudThemeToken.textSizeHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)

      Progress({
        value: this.store.storage?.used ?? 0,
        total: Math.max(this.store.storage?.total ?? 0, 1),
        type: ProgressType.Capsule
      })
        .width('100%')
        .height(CloudThemeToken.storageProgressHeight)
        .color(CloudThemeToken.primary)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        // 胶囊型 Progress 自带按钮式交互态，纯展示条需屏蔽，否则 2in1 悬停时横条晃动
        .focusable(false)
        .hitTestBehavior(HitTestMode.None)

      Row() {
        Text(this.storageFreeText())
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .layoutWeight(1)
        Text(this.storageUpdatedText())
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
      }
      .width('100%')
    }
    .width('100%')
    .padding(CloudThemeToken.spacingPage)
    .borderRadius(CloudThemeToken.settingGroupRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(HorizontalAlign.Start)
  }

  private storagePercentText(): string {
    const s = this.store.storage
    if (!s || s.total <= 0) {
      return ''
    }
    return `${(s.used * CloudThemeToken.percentageFull / s.total).toFixed(1)}%`
  }

  private storageUsedText(): string {
    const s = this.store.storage
    return s ? `${CommonUtil.formatBytes(s.used)} / ${CommonUtil.formatBytes(s.total)}` : '—'
  }

  private storageFreeText(): string {
    const s = this.store.storage
    if (!s) {
      return ''
    }
    const packs = this.store.account?.storage_packs ?? []
    let packTotal = 0
    packs.forEach(pack => {
      packTotal += pack.size
    })
    const free = `剩余 ${CommonUtil.formatBytes(s.free)}`
    return packTotal > 0 ? `${free} · 含存储包 ${CommonUtil.formatBytes(packTotal)}` : free
  }

  private storageUpdatedText(): string {
    if (this.store.storageUpdatedAt <= 0) {
      return ''
    }
    const d = new Date(this.store.storageUpdatedAt)
    const hh = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`
    const mm = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`
    return `${hh}:${mm} 更新`
  }
}
