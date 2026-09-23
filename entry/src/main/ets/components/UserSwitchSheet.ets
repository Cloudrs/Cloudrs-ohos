import { DbUserInfo } from "../model/net/ApiTypes";
import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';
import UserDatabase from "../model/UserDatabase";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudMaterial } from "../model/CloudMaterial";
import { showCloudConfirmDialog } from "../utils/CloudDialogUtil";
import { ActiveAccount } from "../utils/ActiveAccount";
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

  /** 凭证已过期：点它不会直接切过去，而是去登录页补密码，提前标出来免得意外 */
  private isExpired(user: DbUserInfo): boolean {
    const expires = new Date(user.expires).getTime()
    return Number.isNaN(expires) || expires <= Date.now()
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
          ActiveAccount.clear()
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
    .backgroundColor(CloudMaterial.materialSurface(CloudThemeToken.background))
  }

  // systemMaterial 版本守卫在 CloudMaterial 内部，编译器看不见，此处屏蔽兼容性告警
  @SuppressWarnings({ rules: [SuppressWarningsType.COMPATIBILITY] })
  @Builder userRow(user: DbUserInfo) {
    Row({ space: CloudThemeToken.spacingCard }) {
      AccountAvatar({
        baseUrl: user.url,
        userId: user.userinfo.id,
        avatar: user.userinfo.avatar,
        cookie: user.cookie,
        refreshToken: user.refresh_token,
        username: user.username,
        avatarSize: CloudThemeToken.iconBoxXl,
        radius: CloudThemeToken.controlRadiusRoundXl
      })

      Column({ space: CloudThemeToken.spacingTiny }) {
        Row({ space: CloudThemeToken.spacingXs }) {
          // 名字可收缩、超长省略；「已过期」紧跟其后（flexShrink(0) 不被挤压），
          // 不再用 layoutWeight 把徽标顶到右缘——那样各行徽标 x 会因是否有勾选而参差
          Text(user.userinfo.nickname.length > 0 ? user.userinfo.nickname : user.username)
            .fontSize(CloudThemeToken.textSizeLarge)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)

          if (this.isExpired(user)) {
            Text('已过期')
              .fontSize(CloudThemeToken.textSizeTiny)
              .fontColor(CloudThemeToken.danger)
              .backgroundColor(CloudThemeToken.dangerSoft)
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
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)

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
    .backgroundColor(this.isCurrentUser(user) ? CloudThemeToken.primarySoft : CloudMaterial.cardBackground(CloudThemeToken.surface))
    .systemMaterial(CloudMaterial.cardMaterial())
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
