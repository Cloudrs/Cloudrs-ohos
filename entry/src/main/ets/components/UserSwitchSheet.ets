import { DbUserInfo } from "../model/net/ApiTypes";
import Constant from "../model/Constant";
import UserDatabase from "../model/UserDatabase";
import UserPreferences from "../model/UserPreferences";
import { CloudThemeToken } from "../model/CloudTheme";
import { showCloudConfirmDialog } from "../utils/CloudDialogUtil";
import { AccountAvatar } from "./AccountAvatar";
import { CloudIconButton } from "./CloudIconButton";

@Component
export struct UserSwitchSheet {
  @Prop currentUser: string = ''
  @Prop currentUrl: string = ''
  onSelect?: (user: DbUserInfo) => void
  onClose?: () => void
  @State users: DbUserInfo[] = []

  aboutToAppear(): void {
    this.reloadUsers()
  }

  private reloadUsers(): void {
    this.users = UserDatabase.listUserInfo()
  }

  private isCurrentUser(user: DbUserInfo): boolean {
    if (this.currentUrl.length > 0) {
      return user.username === this.currentUser && user.url === this.currentUrl
    }
    return user.username === this.currentUser
  }

  private deleteUser(user: DbUserInfo): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '删除账号记录',
      message: `${user.username}\n${user.url}`,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        UserDatabase.deleteUserInfo(user.username, user.url)
        if (this.isCurrentUser(user)) {
          UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_KEY)
          UserPreferences.deleteSync(Constant.USER_PREFERENCES, Constant.ACTIVE_USER_URL_KEY)
        }
        this.reloadUsers()
      }
    })
  }

  build() {
    Column({ space: CloudThemeToken.spacingPage }) {
      if (this.currentUrl.length > 0) {
        Row({ space: CloudThemeToken.spacingXs }) {
          Text('当前站点')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
          Text(this.currentUrl)
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(CloudThemeToken.rowHeightSm)
        .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingPanel })
        .borderRadius(CloudThemeToken.cardRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .alignItems(VerticalAlign.Center)
      }

      if (this.users.length === 0) {
        Column({ space: CloudThemeToken.spacingCard }) {
          Image($r('app.media.ic_person_2'))
            .width(CloudThemeToken.icon4xl)
            .height(CloudThemeToken.icon4xl)
            .fillColor(CloudThemeToken.textSecondary)
            .draggable(false)
          Text('暂无历史账号')
            .fontSize(CloudThemeToken.textSizeBodyPlus)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .height(CloudThemeToken.cardHeight2xl)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.users, (item: DbUserInfo) => {
          this.userRow(item)
        }, (item: DbUserInfo) => `${item.url}|${item.username}`)
      }
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: CloudThemeToken.spacingSheetBottom
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder userRow(user: DbUserInfo) {
    Row({ space: CloudThemeToken.spacingCard }) {
      AccountAvatar({
        baseUrl: user.url,
        userId: user.userinfo.id,
        avatar: user.userinfo.avatar,
        cookie: user.cookie,
        refreshToken: user.refresh_token,
        avatarSize: CloudThemeToken.iconBoxXl,
        radius: CloudThemeToken.controlRadiusRoundXl
      })

      Column({ space: CloudThemeToken.spacingTiny }) {
        Text(user.userinfo.nickname.length > 0 ? user.userinfo.nickname : user.username)
          .fontSize(CloudThemeToken.textSizeLarge)
          .fontWeight(FontWeight.Medium)
          .fontColor(CloudThemeToken.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(user.username)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(user.url)
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isCurrentUser(user)) {
        Image($r('app.media.ic_checkmark_circle'))
          .width(CloudThemeToken.icon2xl)
          .height(CloudThemeToken.icon2xl)
          .fillColor(CloudThemeToken.primary)
          .draggable(false)
      }

      CloudIconButton({
        icon: $r('app.media.ic_delete_fill'),
        iconSize: CloudThemeToken.iconLg,
        buttonBackground: CloudThemeToken.surfaceSubtle,
        iconColor: CloudThemeToken.danger,
        onAction: () => {
          this.deleteUser(user)
        }
      })
    }
    .width('100%')
    .height(CloudThemeToken.cardHeightLg)
    .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(this.isCurrentUser(user) ? CloudThemeToken.primarySoft : CloudThemeToken.surface)
    .border({
      width: CloudThemeToken.lineWidth,
      color: this.isCurrentUser(user) ? CloudThemeToken.primary : CloudThemeToken.line
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onSelect?.(user)
    })
  }

}
