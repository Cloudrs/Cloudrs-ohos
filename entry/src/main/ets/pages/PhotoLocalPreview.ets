import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoLocalPreviewParam } from '../model/Params';
import { CommonUtil } from '../utils/CommonUtil';
import { DateFormatUtil } from '../utils/DateFormatUtil';

const TAG: string = 'PhotoLocalPreview'

@Component
export struct PhotoLocalPreviewPage {
  routeParam?: PhotoLocalPreviewParam
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @State items: PhotoBackupItem[] = []
  @State index: number = 0
  @State backupEnabled: boolean = false

  aboutToAppear(): void {
    if (this.routeParam) {
      this.items = this.routeParam.items
      this.index = Math.max(0, Math.min(this.routeParam.index, this.routeParam.items.length - 1))
      this.backupEnabled = this.routeParam.backupEnabled
    }
    console.info(TAG, `preview local photos count=${this.items.length} index=${this.index}`)
  }

  private statusLine(item: PhotoBackupItem): string {
    if (item.status === PhotoBackupStatus.COMPLETED) {
      return '已备份'
    }
    if (!this.backupEnabled) {
      return '未备份'
    }
    if (item.status === PhotoBackupStatus.UPLOADING) {
      return '上传中'
    }
    if (item.status === PhotoBackupStatus.FAILED) {
      return '备份失败'
    }
    return '待备份'
  }

  @Builder infoBar(item: PhotoBackupItem) {
    Column({ space: CloudThemeToken.spacingXs }) {
      Text(item.name)
        .fontSize(CloudThemeToken.textSizeBodyPlus)
        .fontWeight(FontWeight.Medium)
        .fontColor(CloudThemeToken.onPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(`${DateFormatUtil.format(new Date(item.modifiedAt), 'yyyy/MM/dd HH:mm')} · ${CommonUtil.formatBytes(item.size)}`)
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor('rgba(255, 255, 255, 0.65)')
        .width('100%')

      Text(this.statusLine(item))
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.primary)
        .width('100%')
    }
    .width('100%')
    .padding({
      left: CloudThemeToken.spacingPage,
      right: CloudThemeToken.spacingPage,
      top: CloudThemeToken.spacingSection,
      bottom: CloudThemeToken.spacingSection
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        ForEach(this.items, (item: PhotoBackupItem) => {
          Image(item.uri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }, (item: PhotoBackupItem) => item.id)
      }
      .index(this.index)
      .loop(false)
      .indicator(false)
      .onChange((i: number) => {
        this.index = i
      })
      .width('100%')
      .height('100%')

      if (this.items.length > 0 && this.index < this.items.length) {
        Column() {
          this.infoBar(this.items[this.index])
        }
        .width('100%')
        .padding({ bottom: this.bottomRectHeight })
        .backgroundColor(0xCC000000)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
