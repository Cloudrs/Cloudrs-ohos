import { promptAction } from '@kit.ArkUI'
import { DialogHelper } from '@pura/harmony-dialog'

export enum ToastType {Error, Warn, Info}
let customDialogId: number = 0

@Builder
export function customToastBuilder(message: string | Resource, toastType: ToastType = ToastType.Info) {
  Column() {
    Row() {
      if (toastType === ToastType.Error) {
        Image($r('app.media.ic_warn_circle'))
          .width(20)
          .fillColor(Color.Red)
          .margin({ left: 10, right: 10 })
      } else if (toastType === ToastType.Warn) {
        Image($r('app.media.ic_warn_circle'))
          .width(20)
          .fillColor(Color.Yellow)
          .margin({ left: 10, right: 10 })
      } else {
        Image($r('app.media.ic_info_circle'))
          .width(20)
          .margin({ left: 10, right: 10 })
      }

      Text(message)
        .fontSize(14)
        .layoutWeight(1)
    }
    .height(40)
  }
}

/**
 * 显示自定义toast，支持图标加文本显示，暂时因为builder上下文问题没实现，弃用
 * @param message   需要显示的文本
 * @param toastType 类型ToastType，支持Error,Warn,Info，默认Info
 * @param duration  显示时长，单位：毫秒，默认：3000
 */
export function showCustomToast(message: string|Resource, toastType: ToastType = ToastType.Info,
  duration: number = 3000, builder?: CustomBuilder)
{
  if (customDialogId > 0) {
    promptAction.closeCustomDialog(customDialogId)
    customDialogId = 0
  }

  promptAction.openCustomDialog({
    builder: () => customToastBuilder(message, toastType), // 此处有问题
    alignment: DialogAlignment.Top,
    keyboardAvoidMode: KeyboardAvoidMode.NONE,
    showInSubWindow: false,
    offset: { dx: 0, dy: 10 },
    backgroundColor: $r('app.color.light_gray'),
    cornerRadius: 20,
    height: 40,
    width: '50%',
    // borderWidth: 1,
    // borderStyle: BorderStyle.Dashed, //使用borderStyle属性，需要和borderWidth属性一起使用
    // borderColor: Color.Blue, //使用borderColor属性，需要和borderWidth属性一起使用
    shadow: ({
      radius: 20,
      color: Color.Grey,
      offsetX: 20,
      offsetY: -20
    }),
  }).then((dialogId: number) => {
    customDialogId = dialogId
    // 设置超时时间则关闭弹窗
    let timeoutId = setTimeout(() => {
      if (customDialogId > 0) {
        promptAction.closeCustomDialog(customDialogId)
        customDialogId = 0
      }
    }, duration)
  })
}

/**
 * 显示自定义toast，支持图标加文本显示
 * @param message   需要显示的文本
 * @param toastType 类型ToastType，支持Error,Warn,Info，默认Info
 * @param duration  显示时长，单位：毫秒，默认：3000
 */
export function showToastTips(message: string|Resource, toastType: ToastType = ToastType.Info,
  duration: number = 3000)
{
  let fillColor: string | Resource | Color = Color.Gray
  let fontColor: string | Resource | Color = Color.Black
  let image: string | Resource;

  if (toastType === ToastType.Error) {
    fillColor = Color.Red
    image = $r('app.media.ic_warn_circle')
  } else if (toastType === ToastType.Warn) {
    fillColor = Color.Yellow
    image = $r('app.media.ic_warn_circle')
  } else {
    // fillColor = Color.Gray
    image = $r('app.media.ic_info_circle')
  }

  DialogHelper.showToastTipCustom({
    message,
    fontColor,
    fontSize: 15,
    imageRes: image,
    imageSize: {width: 24, height: 24},
    imageFillColor: fillColor,
    borderRadius: 20,
    alignment: DialogAlignment.Top,
    backgroundColor: '#ffeeeeee',
    offset: {dx: 0, dy: 20},
  })
}

/**
 * 显示toast，支持文本显示
 * @param message   需要显示的文本
 * @param duration  显示时长，单位：毫秒，默认：1500
 */
export function showToast(message: string|Resource, duration: number = 1500) {
  promptAction.showToast({message: message, duration: duration})
  // DialogHelper.showToast(message, {duration})
}