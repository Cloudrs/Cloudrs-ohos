import Constant from "../model/Constant";
import { CloudThemeToken } from "../model/CloudTheme";
import { CloudIconButton } from "./CloudIconButton";

@Component
export struct FeedbackSheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  onCopy?: () => void
  onIssue?: () => void
  onMail?: () => void
  onClose?: () => void

  build() {
    Column({ space: CloudThemeToken.uploadSourceSheetGap }) {
      Row() {
        Column({ space: CloudThemeToken.spacingXs }) {
          Text('问题反馈')
            .fontSize(CloudThemeToken.uploadSourceTitleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(CloudThemeToken.textPrimary)
          Text('复制诊断信息或提交带模板的问题，方便开发者快速定位')
            .fontSize(CloudThemeToken.textSizeSmall)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        CloudIconButton({
          icon: $r('app.media.ic_xmark_bold'),
          buttonSize: CloudThemeToken.smallIconButtonSize,
          iconSize: CloudThemeToken.sheetActionIconSize,
          buttonBackground: CloudThemeToken.surfaceSubtle,
          iconColor: CloudThemeToken.textSecondary,
          onAction: () => {
            this.onClose?.()
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: CloudThemeToken.uploadSourceListGap }) {
        this.feedbackActionItem(
          $r('app.media.ic_copy'),
          '复制诊断信息',
          '脱敏复制版本、站点、账号和复现模板',
          () => {
            this.onCopy?.()
          })

        this.feedbackActionItem(
          $r('app.media.ic_feedback'),
          '提交 Issue',
          '打开预填模板的 Gitee 问题页面',
          () => {
            this.onIssue?.()
          })

        this.feedbackActionItem(
          $r('app.media.ic_share'),
          '邮件反馈',
          '使用邮件发送同样的诊断模板',
          () => {
            this.onMail?.()
          })
      }
      .width('100%')

      Row({ space: CloudThemeToken.spacingXs }) {
        Image($r('app.media.ic_info_circle'))
          .width(CloudThemeToken.iconMd)
          .height(CloudThemeToken.iconMd)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
        Text('不会包含密码、Token、Cookie、刷新令牌和下载直链。')
          .fontSize(CloudThemeToken.textSizeSmall)
          .fontColor(CloudThemeToken.textSecondary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: CloudThemeToken.spacingCard, right: CloudThemeToken.spacingCard })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.uploadSourceSheetHorizontalPadding,
      right: CloudThemeToken.uploadSourceSheetHorizontalPadding,
      top: CloudThemeToken.uploadSourceSheetTopPadding,
      bottom: this.bottomRectHeight + CloudThemeToken.uploadSourceSheetBottomPadding
    })
    .borderRadius({ topLeft: CloudThemeToken.surfaceRadius, topRight: CloudThemeToken.surfaceRadius })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.background)
    .zIndex(1)
  }

  @Builder feedbackActionItem(icon: Resource, title: ResourceStr, description: ResourceStr, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: CloudThemeToken.uploadSourceItemGap }) {
        Stack() {
          Image(icon)
            .width(CloudThemeToken.icon3xl)
            .height(CloudThemeToken.icon3xl)
            .fillColor(CloudThemeToken.textPrimary)
            .draggable(false)
        }
        .width(CloudThemeToken.uploadSourceIconBoxSize)
        .height(CloudThemeToken.uploadSourceIconBoxSize)
        .borderRadius(CloudThemeToken.controlRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)

        Column({ space: CloudThemeToken.uploadSourceTextGap }) {
          Text(title)
            .fontSize(CloudThemeToken.uploadSourceTitleTextSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(CloudThemeToken.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(description)
            .fontSize(CloudThemeToken.uploadSourceDescriptionSize)
            .fontColor(CloudThemeToken.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_chevron_right'))
          .width(CloudThemeToken.sheetActionIconSize)
          .height(CloudThemeToken.sheetActionIconSize)
          .fillColor(CloudThemeToken.textSecondary)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(CloudThemeToken.uploadSourceRowHeight)
    .padding({
      left: CloudThemeToken.uploadSourceItemHorizontalPadding,
      right: CloudThemeToken.uploadSourceItemHorizontalPadding
    })
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .onClick(onClick)
  }
}
