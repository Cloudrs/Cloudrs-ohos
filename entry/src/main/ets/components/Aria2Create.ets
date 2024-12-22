import Constant from "../model/Constant"
import { CloudApi } from "../model/net/CloudApi";
import { PathSelectSheet } from "./PathSelectSheet";

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
    CloudApi.aria2TaskCreate(path, this.urls, {
      onSuccess: (data) => {
        if (this.onFinished) {
          this.onFinished()
        }
      },
      onFailure: (msg) => {
        console.error(TAG, 'create aria2 task failed, msg: ' + msg)
      }
    })
  }

  build() {
    Column({space: 15}){
      TextArea({placeholder: $r('app.string.aria2_url_input_placeholder'), text: $$this.inputUrls})
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .height(200)
        .borderRadius(5)
        .padding(7)
        .textAlign(TextAlign.Start)
        .align(Alignment.TopStart)
        .onChange((value) => {
          this.urls = value.split(/\r\n|\r|\n/)
          //console.debug(TAG, 'urls: ' + this.urls)
          console.debug(TAG, 'path: ' + this.path)
        })

      Row({space: 10}) {
        Image($r('app.media.ic_folder_fill'))
          .width(30)
          .height(30)

        Text(this.path == undefined ? $r('app.string.aria2_path_select') : this.path)
          .fontColor(Color.White)
          .fontSize(16)
          .wordBreak(WordBreak.BREAK_ALL)
      }
      .width('100%')
      .padding(10)
      .borderRadius(5)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.aria2_path_background'))
      .onClick(() => {
        this.isShowPathSelect = true
      })

      Button({type: ButtonType.Normal}) {
        Row({space: 10}) {
          Image($r('app.media.ic_tabbar_remote_down'))
            .width(30)
            .height(30)

          Text($r('app.string.aria2_create_task'))
            .fontSize(16)
            .fontColor(Color.White)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding(10)
      .borderRadius(5)
      .enabled(this.path != undefined && this.inputUrls != '')
      .onClick(() => {
        if (this.path) {
          this.createAria2Task(this.path)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 15, right: 15, top: 15, bottom: this.bottomRectHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.sheet_default_background'))
    .bindSheet($$this.isShowPathSelect, this.selectPathSheet(), {
      showClose: false
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