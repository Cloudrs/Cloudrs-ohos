import { promptAction } from '@kit.ArkUI'

export enum ToastType {Error, Warn, Info}

/**
 * 显示自定义toast，支持图标加文本显示
 * @param message   需要显示的文本
 * @param toastType 类型ToastType，支持Error,Warn,Info，默认Info
 * @param duration  显示时长，单位：毫秒，默认：3000
 */
export function showToastTips(message: string|Resource, toastType: ToastType = ToastType.Info,
  duration: number = 3000)
{
  showToast(formatToastMessage(message, toastType), duration)
}

/**
 * 显示toast，支持文本显示
 * @param message   需要显示的文本
 * @param duration  显示时长，单位：毫秒，默认：1500
 */
export function showToast(message: string|Resource, duration: number = 1500) {
  promptAction.openToast({message: message, duration: duration}).catch((err: Error) => {
    console.error('ToastUtil', `openToast failed: ${err.message}`)
  })
}

function formatToastMessage(message: string | Resource, toastType: ToastType): string | Resource {
  if (typeof message !== 'string') {
    return message
  }
  if (toastType === ToastType.Error) {
    return `错误：${message}`
  }
  if (toastType === ToastType.Warn) {
    return `提示：${message}`
  }
  return message
}
