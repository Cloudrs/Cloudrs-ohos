// import { ExceptionPrompt, MarginType, PromptOptions, window, promptAction } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction'
import { DialogHelper } from '@pura/harmony-dialog'
import { ToastUtil } from '@pura/harmony-utils'
import { customToastBuilder, showCustomToast, ToastType } from '../common/Components'

@Entry
struct TestPage {

  build() {
    Column({space: 20}) {
      Button('测试toast')
        .onClick(() => {
          DialogHelper.showToastTipCustom({
            // uiContext: this.getUIContext(),
            borderRadius: 20,
            backgroundColor: '#bfbfbf',
            alignment: DialogAlignment.Top,
            offset: {dx: 0, dy: 20},
            message: '网址异常,请检查输入是否正确',
            fontColor: Color.Black,
            imageRes: $r('app.media.ic_warn_circle'),
            imageSize: { width: 30, height: 30},
            imageFillColor: Color.Yellow
          })
        })

      Button('测试toast2')
        .onClick(() => {
          showCustomToast('哈哈哈')
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
  }
}