import Constant from "../model/Constant"
import { CloudApi } from "../model/net/CloudApi";
import { CloudThemeToken } from "../model/CloudTheme";
import { PathSelectSheet } from "./PathSelectSheet";
import { showToastTips, ToastType } from "../utils/ToastUtil";

const TAG: string = 'Aria2Create'

@Component
export struct Aria2Create {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State inputUrls: string = ''
  @State path: string|undefined = undefined
  @State isShowPathSelect: boolean = false
  private urls: string[] = []
  onFinished?: () => void

  createAria2Task(path: string) {
    this.urls = this.inputUrls.split(/\r\n|\r|\n/)
      .map((url: string) => url.trim())
      .filter((url: string) => url.length > 0)
    if (this.urls.length === 0) {
      showToastTips('请输入下载链接', ToastType.Warn)
      return
    }

    CloudApi.aria2TaskCreate(path, this.urls, {
      onSuccess: (data) => {
        if (this.onFinished) {
          this.onFinished()
        }
      },
      onFailure: (msg) => {
        console.error(TAG, 'create aria2 task failed, msg: ' + msg)
        showToastTips(`创建任务失败：${msg}`, ToastType.Error)
      }
    })
  }

  build() {
    Column({ space: CloudThemeToken.aria2CreateGap }){
      TextArea({placeholder: $r('app.string.aria2_url_input_placeholder'), text: $$this.inputUrls})
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .height(CloudThemeToken.aria2InputHeight)
        .borderRadius(CloudThemeToken.cardRadius)
        .padding(CloudThemeToken.aria2InputPadding)
        .textAlign(TextAlign.Start)
        .align(Alignment.TopStart)
        .fontColor(CloudThemeToken.textPrimary)
        .placeholderColor(CloudThemeToken.textSecondary)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
        .onChange((value) => {
          this.urls = value.split(/\r\n|\r|\n/)
            .map((url: string) => url.trim())
            .filter((url: string) => url.length > 0)
          //console.debug(TAG, 'urls: ' + this.urls)
          console.debug(TAG, 'path: ' + this.path)
        })

      Row({ space: CloudThemeToken.aria2PathGap }) {
        Image($r('app.media.ic_folder_fill'))
          .width(CloudThemeToken.aria2PathIconSize)
          .height(CloudThemeToken.aria2PathIconSize)
          .fillColor(CloudThemeToken.primary)

        Text(this.path == undefined ? $r('app.string.aria2_path_select') : this.path)
          .fontColor(CloudThemeToken.textPrimary)
          .fontSize(CloudThemeToken.aria2PathTextSize)
          .wordBreak(WordBreak.BREAK_ALL)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(CloudThemeToken.aria2PathPadding)
      .borderRadius(CloudThemeToken.cardRadius)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .backgroundColor(CloudThemeToken.surface)
      .onClick(() => {
        this.isShowPathSelect = true
      })

      Button({type: ButtonType.Normal}) {
        Row({ space: CloudThemeToken.aria2ButtonGap }) {
          Image($r('app.media.ic_tabbar_remote_down'))
            .width(CloudThemeToken.aria2ButtonIconSize)
            .height(CloudThemeToken.aria2ButtonIconSize)
            .fillColor(CloudThemeToken.onPrimary)

          Text($r('app.string.aria2_create_task'))
            .fontSize(CloudThemeToken.aria2ButtonTextSize)
            .fontColor(CloudThemeToken.onPrimary)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(CloudThemeToken.inputHeight)
      .borderRadius(CloudThemeToken.controlRadius)
      .backgroundColor(CloudThemeToken.primary)
      .enabled(this.path != undefined && this.inputUrls.trim() != '')
      .onClick(() => {
        if (this.path) {
          this.createAria2Task(this.path)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: CloudThemeToken.pagePadding,
      right: CloudThemeToken.pagePadding,
      top: CloudThemeToken.aria2SheetTopPadding,
      bottom: this.bottomRectHeight
    })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(CloudThemeToken.background)
    .bindSheet($$this.isShowPathSelect, this.selectPathSheet(), {
      showClose: false,
      backgroundColor: CloudThemeToken.background,
      onDisappear: () => {
        this.isShowPathSelect = false
      }
    })
  }

  @Builder selectPathSheet() {
    PathSelectSheet({title: $r('app.string.aria2_download_to'), onClose: (isFinished: boolean, path?: string) => {
      this.isShowPathSelect = false
      if (isFinished && path !== '') {
        console.debug(TAG, 'select path: ' + path)
        this.path = path
      }
    }})
  }
}
