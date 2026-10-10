import { CloudThemeToken } from '../model/CloudTheme';
import { DbUserInfo } from '../model/net/ApiTypes';
import { LoginHistoryRules } from '../utils/LoginHistoryRules';
import { AccountAvatar } from './AccountAvatar';

const NO_MATCH: number = -1
const HALF: number = 2

/** 候选浮层里的一行 */
export class LoginSuggestItem {
  /** 唯一标识：站点网址或用户名 */
  key: string = ''
  title: string = ''
  /** 空串不显示 */
  subtitle: string = ''
  /** 标题后的小标签（如 HTTP），空串不显示 */
  tag: string = ''
  /** 用户名候选对应的已保存账号：有就画它的头像，没有（凭据已删、只在历史里）回落人形图标 */
  account: DbUserInfo | undefined = undefined
}

/**
 * 登录页网址 / 用户名输入框下方的历史候选列表，作为 bindPopup 的内容。
 * 只管展示和回调：候选从哪来、选中后做什么由登录页决定。
 *
 * 底色、描边、投影都交给气泡：26+ 由气泡的沉浸材质接管（Popup 在沉浸光感生效范围内），
 * <26 由 popupColor 给实底。本组件自身保持透明，否则会盖住材质。
 * 行和删除键都不可获焦：点它们时焦点得留在输入框上，否则输入框失焦、候选跟着收起，点击就丢了。
 */
@Component
export struct LoginSuggestPanel {
  @Prop header: string = ''
  @Prop items: LoginSuggestItem[] = []
  /** 高亮输入框里已输入的片段，空串不高亮 */
  @Prop query: string = ''
  /** 外接键盘 ↑↓ 选中的行，-1 表示没有 */
  @Prop activeIndex: number = NO_MATCH
  @Prop isUser: boolean = false
  /** 浮层整体最大高度，超出部分在列表内滚动 */
  @Prop maxPanelHeight: number = CloudThemeToken.zero
  onPick?: (index: number) => void
  onRemove?: (index: number) => void

  private listMaxHeight(): number {
    return this.maxPanelHeight - CloudThemeToken.loginSuggestHeaderHeight - CloudThemeToken.loginSuggestPadding * HALF
  }

  build() {
    Column() {
      Text(this.header)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
        .height(CloudThemeToken.loginSuggestHeaderHeight)
        .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
        .width('100%')

      Scroll() {
        Column() {
          // 删掉一行后下标会整体前移，key 带上下标让各行重建，回调里的 index 才不过期
          ForEach(this.items, (item: LoginSuggestItem, index: number) => {
            this.itemRow(item, index)
          }, (item: LoginSuggestItem, index: number) => `${index}|${item.key}|${this.query}`)
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .constraintSize({ maxHeight: this.listMaxHeight() })
    }
    .width('100%')
    .padding(CloudThemeToken.loginSuggestPadding)
  }

  @Builder itemRow(item: LoginSuggestItem, index: number) {
    Row({ space: CloudThemeToken.spacingCard }) {
      if (item.account !== undefined) {
        this.accountAvatar(item.account as DbUserInfo)
      } else {
        Stack() {
          Image(this.isUser ? $r('app.media.ic_person') : $r('app.media.ic_login_globe'))
            .width(CloudThemeToken.iconLg)
            .height(CloudThemeToken.iconLg)
            .fillColor(CloudThemeToken.primary)
            .draggable(false)
        }
        .width(CloudThemeToken.loginSuggestAvatarSize)
        .height(CloudThemeToken.loginSuggestAvatarSize)
        .borderRadius(CloudThemeToken.loginSuggestAvatarSize / HALF)
        .backgroundColor(CloudThemeToken.primarySoft)
      }

      Column({ space: CloudThemeToken.spacingTiny }) {
        Row({ space: CloudThemeToken.spacingMd }) {
          this.highlightTitle(item.title, LoginHistoryRules.matchStart(item.title, this.query))
          if (item.tag.length > 0) {
            Text(item.tag)
              .fontSize(CloudThemeToken.textSizeTiny)
              .fontColor(CloudThemeToken.textSecondary)
              .backgroundColor(CloudThemeToken.suggestHighlight)
              .borderRadius(CloudThemeToken.controlRadiusSm)
              .flexShrink(0)
              .padding({
                left: CloudThemeToken.spacingXs + CloudThemeToken.spacingTiny,
                right: CloudThemeToken.spacingXs + CloudThemeToken.spacingTiny,
                top: CloudThemeToken.spacingTiny,
                bottom: CloudThemeToken.spacingTiny
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (item.subtitle.length > 0) {
          Text(item.subtitle)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack() {
        Image($r('app.media.ic_window_close'))
          .width(CloudThemeToken.iconSm)
          .height(CloudThemeToken.iconSm)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width(CloudThemeToken.loginSuggestRemoveSize)
      .height(CloudThemeToken.loginSuggestRemoveSize)
      .borderRadius(CloudThemeToken.loginSuggestRemoveSize / HALF)
      .hoverEffect(HoverEffect.Highlight)
      .focusable(false)
      .accessibilityText('删除这条记录')
      .onClick(() => {
        this.onRemove?.(index)
      })
    }
    .width('100%')
    .height(CloudThemeToken.loginSuggestItemHeight)
    .padding({ left: CloudThemeToken.spacingXl, right: CloudThemeToken.spacingXs })
    .borderRadius(CloudThemeToken.controlRadiusSm)
    .backgroundColor(index === this.activeIndex ? CloudThemeToken.suggestHighlight : CloudThemeToken.transparent)
    .stateStyles({
      pressed: { .backgroundColor(CloudThemeToken.suggestHighlight) }
    })
    .hoverEffect(HoverEffect.Highlight)
    .focusable(false)
    .accessibilityText(item.subtitle.length > 0 ? `${item.title}，${item.subtitle}` : item.title)
    .onClick(() => {
      this.onPick?.(index)
    })
  }

  // 与登录页「已保存账号」列表同一个组件、同一份本地缓存，通常不会多发请求
  @Builder accountAvatar(account: DbUserInfo) {
    AccountAvatar({
      baseUrl: account.url,
      userId: account.userinfo.id,
      avatar: account.userinfo.avatar,
      cookie: account.cookie,
      refreshToken: account.refresh_token,
      username: account.username,
      avatarSize: CloudThemeToken.loginSuggestAvatarSize,
      radius: CloudThemeToken.loginSuggestAvatarSize / HALF
    })
  }

  // 按值传参：query 变化时 ForEach 的 key 跟着变、整行重建，这里拿到的总是新值
  @Builder highlightTitle(title: string, start: number) {
    Text() {
      if (start === NO_MATCH) {
        Span(title)
      } else {
        Span(title.substring(0, start))
        Span(title.substring(start, start + this.query.length))
          .fontColor(CloudThemeToken.primary)
          .fontWeight(FontWeight.Medium)
        Span(title.substring(start + this.query.length))
      }
    }
    .fontSize(CloudThemeToken.textSizeBodyPlus)
    .fontColor(CloudThemeToken.textPrimary)
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .flexShrink(1)
  }
}
