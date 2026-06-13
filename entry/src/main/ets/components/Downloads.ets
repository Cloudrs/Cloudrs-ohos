import { EmptyState } from "./EmptyState"
import { FileModelState } from "../model/FileModel"
import { CloudThemeToken } from "../model/CloudTheme"
import { TransportObject } from "../model/TransportObject"
import { CommonUtil } from "../utils/CommonUtil"
import LazyDataSource from "../utils/LazyDataSource"
import { TransferStateUtil } from "../utils/TransferStateUtil"

const TAG = 'Downloads'

export enum TransferAction {
  PAUSE,
  RESUME,
  CANCEL,
  CLEAR_COMPLETED
}

@Component
export struct Downloads {
  @ObjectLink downloadObjects: LazyDataSource<TransportObject>
  onAction?: (object: TransportObject, action: TransferAction) => void

  build() {
    Column() {
      if (this.downloadObjects.totalCount() == CloudThemeToken.zero) {
        this.noItem()
      } else {
        List({ space: CloudThemeToken.transferListGap }) {
          LazyForEach(this.downloadObjects, (item: TransportObject, index) => {
            ListItem() {
              this.downloadItem(item)
            }
            .bindContextMenu(this.itemMenu(item), ResponseType.RightClick)
            .bindContextMenu(this.itemMenu(item), ResponseType.LongPress)
            .swipeAction({
              end: {
                builder: () => { this.deleteSwipe(item) },
                actionAreaDistance: CloudThemeToken.transferSwipeActionWidth
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (item: TransportObject, index) => item.item.id + index)
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder noItem() {
    EmptyState({
      icon: $r('app.media.ic_arrowshape_down'),
      title: $r('app.string.no_download_task'),
      description: '下载任务会显示在这里。'
    })
  }

  getDownloadIcon(state: FileModelState) {
    return TransferStateUtil.getStateIcon(state, $r('app.media.ic_arrowshape_down'))
  }

  getStateColor(state: FileModelState): ResourceColor {
    return TransferStateUtil.getStateColor(state)
  }

  @Builder downloadItem(object: TransportObject) {
    Row({ space: CloudThemeToken.transferItemGap }) {
      Image(CommonUtil.getFileIconInfo(object.item.name).icon)
        .width(CloudThemeToken.transferFileIconSize)
        .height(CloudThemeToken.transferFileIconSize)

      Column({ space: CloudThemeToken.transferTextGap }) {
        Text(object.item.name)
          .fontSize(CloudThemeToken.transferNameSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CloudThemeToken.textPrimary)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .ellipsisMode(EllipsisMode.CENTER)

        Row({ space: CloudThemeToken.transferMetaGap }) {
          Image(this.getDownloadIcon(object.state))
            .width(CloudThemeToken.transferStateIconSize)
            .height(CloudThemeToken.transferStateIconSize)
            .fillColor(this.getStateColor(object.state))

          Text(this.getStateText(object))
            .fontSize(CloudThemeToken.transferMetaSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getStateColor(object.state))
            .margin({ right: CloudThemeToken.transferSpeedRightMargin })

          Text(`${CommonUtil.formatBytes(object.trans, 1)}/${CommonUtil.formatBytes(object.total, 1)}`)
            .fontSize(CloudThemeToken.transferMetaSize)
            .fontColor(CloudThemeToken.textSecondary)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      Stack() {
        Progress({
          value: object.progress,
          total: CloudThemeToken.percentageFull,
          type: ProgressType.Capsule
        })
          .style({ showDefaultPercentage: false })
          .width(CloudThemeToken.transferProgressWidth)
          .height(CloudThemeToken.transferProgressHeight)
          .color(this.getProgressFillColor(object.state))
          .backgroundColor(Color.Transparent)

        Text(this.getProgressLabel(object))
          .fontSize(CloudThemeToken.transferProgressLabelSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getProgressLabelColor(object.state))
          .textShadow(this.getProgressLabelShadow(object.state))
      }
      .width(CloudThemeToken.transferProgressWidth)
      .height(CloudThemeToken.transferProgressHeight)
      .backgroundColor(this.getProgressTrackColor(object.state))
      .borderRadius(CloudThemeToken.transferProgressHeight / 2)
      .onClick(() => {
        this.onProgressClick(object)
      })
    }
    .width('100%')
    .padding(CloudThemeToken.transferItemPadding)
    .borderRadius(CloudThemeToken.cardRadius)
    .backgroundColor(CloudThemeToken.surface)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder itemMenu(object: TransportObject) {
    Menu() {
      MenuItemGroup() {
        if (this.canPause(object.state)) {
          MenuItem({ content: '暂停' })
            .onClick(() => {
              if (this.onAction) this.onAction(object, TransferAction.PAUSE)
            })
        } else if (this.canResume(object.state)) {
          MenuItem({ content: object.state == FileModelState.FAILED ? '重试' : '继续' })
            .onClick(() => {
              if (this.onAction) this.onAction(object, TransferAction.RESUME)
            })
        }
      }
      MenuItemGroup() {
        MenuItem({ content: object.state == FileModelState.COMPLETED ? '删除' : '取消' })
          .contentFontColor(CloudThemeToken.danger)
          .onClick(() => {
            if (this.onAction) this.onAction(object, TransferAction.CANCEL)
          })
        if (object.state == FileModelState.COMPLETED) {
          MenuItem({ content: '删除所有已完成' })
            .contentFontColor(CloudThemeToken.danger)
            .onClick(() => {
              if (this.onAction) this.onAction(object, TransferAction.CLEAR_COMPLETED)
            })
        }
      }
    }
    .width(CloudThemeToken.menuWidth)
  }

  @Builder deleteSwipe(object: TransportObject) {
    Row() {
      Stack() {
        Image($r('app.media.ic_trash_close'))
          .width(CloudThemeToken.transferSwipeIconSize)
          .height(CloudThemeToken.transferSwipeIconSize)
          .fillColor(Color.White)
      }
      .width(CloudThemeToken.transferSwipeButtonSize)
      .height(CloudThemeToken.transferSwipeButtonSize)
      .borderRadius(CloudThemeToken.transferSwipeButtonSize / 2)
      .backgroundColor('#FF3B30')
      .alignContent(Alignment.Center)
      .onClick(() => {
        if (this.onAction) {
          this.onAction(object, TransferAction.CANCEL)
        }
      })
    }
    .height('100%')
    .padding({ left: CloudThemeToken.transferSwipeGap, right: CloudThemeToken.transferSwipeGap })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  private onProgressClick(object: TransportObject): void {
    if (!this.onAction) {
      return
    }
    if (this.canPause(object.state)) {
      this.onAction(object, TransferAction.PAUSE)
    } else if (this.canResume(object.state)) {
      this.onAction(object, TransferAction.RESUME)
    }
  }

  private getProgressFillColor(state: FileModelState): ResourceColor {
    switch (state) {
      case FileModelState.PAUSED:
      case FileModelState.STOPPED:
      case FileModelState.FAILED:
      case FileModelState.COMPLETED:
        return Color.Transparent
      default:
        return CloudThemeToken.primary
    }
  }

  private getProgressTrackColor(state: FileModelState): ResourceColor {
    switch (state) {
      case FileModelState.PAUSED:
      case FileModelState.STOPPED:
        return CloudThemeToken.primarySoft
      case FileModelState.FAILED:
        return CloudThemeToken.dangerSoft
      case FileModelState.COMPLETED:
        return CloudThemeToken.success
      default:
        return CloudThemeToken.surfaceSubtle
    }
  }

  private getProgressLabel(object: TransportObject): string {
    switch (object.state) {
      case FileModelState.PAUSED:
      case FileModelState.STOPPED:
        return '继续'
      case FileModelState.FAILED:
        return '重试'
      case FileModelState.COMPLETED:
        return '已完成'
      default:
        return `${object.progress}%`
    }
  }

  private getProgressLabelColor(state: FileModelState): ResourceColor {
    switch (state) {
      case FileModelState.PAUSED:
      case FileModelState.STOPPED:
        return CloudThemeToken.primary
      case FileModelState.FAILED:
        return CloudThemeToken.danger
      default:
        return Color.White
    }
  }

  private getProgressLabelShadow(state: FileModelState): ShadowOptions | ShadowOptions[] {
    switch (state) {
      case FileModelState.PAUSED:
      case FileModelState.STOPPED:
      case FileModelState.FAILED:
      case FileModelState.COMPLETED:
        return { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
      default:
        return [
          { radius: 0, color: 'rgba(0,0,0,0.6)', offsetX: 1, offsetY: 0 },
          { radius: 0, color: 'rgba(0,0,0,0.6)', offsetX: -1, offsetY: 0 },
          { radius: 0, color: 'rgba(0,0,0,0.6)', offsetX: 0, offsetY: 1 },
          { radius: 0, color: 'rgba(0,0,0,0.6)', offsetX: 0, offsetY: -1 },
          { radius: 3, color: 'rgba(0,0,0,0.5)', offsetX: 0, offsetY: 0 }
        ]
    }
  }

  private canPause(state: FileModelState): boolean {
    return state == FileModelState.RUNNING ||
      state == FileModelState.WAITING ||
      state == FileModelState.RETRYING
  }

  private canResume(state: FileModelState): boolean {
    return state == FileModelState.PAUSED ||
      state == FileModelState.STOPPED ||
      state == FileModelState.FAILED
  }

  getStateText(object: TransportObject): string {
    return TransferStateUtil.getCommonStateText(object.state, '下载失败') ?? TransferStateUtil.getSpeedText(object)
  }
}
