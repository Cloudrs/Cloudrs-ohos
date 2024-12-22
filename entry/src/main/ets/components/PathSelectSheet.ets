import Constant from "../model/Constant";
import { DirectoryInfo, DirFileInfo, ObjectInfo } from "../model/net/ApiTypes";
import { CloudApi } from "../model/net/CloudApi";
import { showToastTips, ToastType } from "../utils/ToastUtil";

const TAG: string = 'PathSelectSheet'

@Component
export struct PathSelectSheet {
  @Prop title: ResourceStr
  @Prop filterDirId: string
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State currentPath: string = ''
  @State objectsInfo: DirFileInfo = new DirFileInfo();
  onClose?: (isFinished: boolean, path?: string) => void

  private normalIcon: Resource = $r('app.media.ic_folder_fill');
  private downIcon: Resource = $r('app.media.ic_chevron_down');
  private rightIcon: Resource = $r('app.media.ic_chevron_right');
  @State allDirs: Map<string, ObjectInfo[]> = new Map()
  @State pathShow: Map<string, boolean> = new Map()

  getPathPadding(path: string) {
    if (path == '/') {
      return 15
    }

    let num = path.split('/').length-1
    return 15 + num*10
  }

  putDirs(path: string, dirs: ObjectInfo[]) {
    this.allDirs.set(path, dirs)
  }

  getDirs(path: string) {
    if (this.allDirs.has(path)) {
      return this.allDirs.get(path)
    }
    return []
  }

  putPathShow(path: string, show: boolean) {
    this.pathShow.set(path, show)
  }

  getPathShow(item: ObjectInfo) {
    let path = CloudApi.getTotalPath(item)
    return this.pathShow.get(path)
  }

  async getFileList(path: string) {
    this.currentPath = path
    CloudApi.getFilesInfo(path, {
      onSuccess: (data: DirectoryInfo) => {
        let dirs = new DirFileInfo(data.parent, data.objects, data.policy).dirObjects
        this.putDirs(path, dirs.filter(item => item.id != this.filterDirId))
        this.putPathShow(this.currentPath, true)
      },
      onFailure: (msg) => {
        showToastTips($r('app.string.get_failed'), ToastType.Error)
      }
    })
  }

  aboutToAppear(): void {
    console.debug(TAG, 'filterDirId: ' + this.filterDirId)
    this.getFileList('/')
  }

  aboutToDisappear(): void {

  }

  build() {
    Column({space: 5}) {
      this.header()

      List() {
        ForEach(this.getDirs('/'), (item: ObjectInfo, index) => {
          this.dirItem(item)
        })
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_default_background'))
    .padding({top: 10, bottom: this.bottomRectHeight})
    .justifyContent(FlexAlign.Start)
  }

  @Builder header() {
    Column() {
      Row({space: 2}) {
        Text(this.title ?? '')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)

        Text(this.currentPath)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row({space: 10}) {
        Button() {
          Image($r('app.media.ic_xmark_circle_fill'))
            .fillColor($r('app.color.light_gray'))
            .draggable(false)
        }
        .width(25)
        .height(25)
        .borderRadius(18)
        .backgroundColor($r('app.color.nav_background'))
        .onClick(() => {
          if (this.onClose) {
            this.onClose(false)
          }
        })

        Row() {
          Text($r('app.string.select_path'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .layoutWeight(1)

          Text($r('app.string.finished'))
            .height(36)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .padding(5)
            .onClick(() => {
              if (this.onClose) {
                this.onClose(true, this.currentPath)
              }
            })
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .outline({width: {bottom: '2px'}})
        .outlineColor($r('app.color.default_line_color'))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .height(70)
    .width('100%')
    .padding({left: 15, right: 15})
  }

  @Builder dirItem(item: ObjectInfo) {
    Column() {
      Row({ space: 10 }) {
        Image(this.normalIcon)
          .width(30)
          .height(30)
          .draggable(false)

        Row({ space: 5 }) {
          Text(item.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .height(32)
            .layoutWeight(1)

          Image(this.getPathShow(item) ? this.downIcon : this.rightIcon)
            .width(24)
            .height(12)
            .padding({left: this.getPathShow(item) ? 0 : 6, right: this.getPathShow(item)? 0: 6})
            .fillColor($r('app.color.file_folder_right'))
            .draggable(false)
        }
        .height(43)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .outline({ width: { bottom: '2px' } })
        .outlineColor($r('app.color.default_line_color'))
      }
      .height(45)
      .width('100%')
      .padding({ left: this.getPathPadding(CloudApi.getTotalPath(item)), right: 15})
      .clip(true)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.currentPath === CloudApi.getTotalPath(item) ? $r('app.color.select_background') : Color.White)
      .onClick(() => {
        this.currentPath = CloudApi.getTotalPath(item)
        let isShow = this.getPathShow(item)
        if (isShow === undefined) {
          this.getFileList(this.currentPath)
        } else {
          this.putPathShow(this.currentPath, !isShow)
        }
      })

      if (this.getPathShow(item)) {
        ForEach(this.getDirs(CloudApi.getTotalPath(item)), (item: ObjectInfo, index) => {
          this.dirItem(item)
        }, (item: ObjectInfo, index) => item.id + index)
      }
    }
    .width('100%')
  }
}