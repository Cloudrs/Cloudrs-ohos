import Constant from "../model/Constant"
import { CloudApi } from "../model/net/CloudApi";

const TAG: string = 'Aria2Create'

@Component
export struct Aria2Create {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0;
  @State inputUrls: string = ''
  @State path: string = ''
  private urls: string[] = []
  onFinished?: () => void

  createAria2Task() {
    CloudApi.aria2TaskCreate(this.path, this.urls, {
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
          console.debug(TAG, 'urls: ' + this.urls)
        })

      Row({space: 10}) {
        Image($r('app.media.ic_folder_fill'))
          .width(30)
          .height(30)

        Text(this.path === '' ? $r('app.string.aria2_path_select') : this.path)
          .fontColor(Color.White)
          .fontSize(16)
          .wordBreak(WordBreak.BREAK_ALL)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius(5)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .backgroundColor($r('app.color.aria2_path_background'))
      .onClick(() => {
        //TODO: 进入选择路径
        this.path = '/demo01'
      })

      Button({type: ButtonType.Normal}) {
        Row({space: 10}) {
          Image($r('app.media.ic_aria2_create'))
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
      .borderRadius(10)
      .enabled(this.path != '' && this.inputUrls != '')
      .onClick(() => {
        this.createAria2Task()
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 15, right: 15, top: 15, bottom: this.bottomRectHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.sheet_default_background'))
  }
}