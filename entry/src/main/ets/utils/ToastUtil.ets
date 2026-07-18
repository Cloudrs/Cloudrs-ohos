import { promptAction, UIContext } from '@kit.ArkUI'
import Constant from '../model/Constant'
import AppLogger from './AppLogger'
import { ApiErrorUtil, NETWORK_ERROR_MESSAGE } from './ApiErrorUtil'

export enum ToastType {Error, Warn, Info}

// 全局 promptAction 在长按菜单关闭动画、Navigation 子页等场景会静默失败，
// 启动时注入主窗口 UIContext，走 getPromptAction() 保证 toast 一定弹得出来。
let toastUiContext: UIContext | undefined = undefined

export function initToastUiContext(ctx: UIContext): void {
  toastUiContext = ctx
}

/**
 * 显示自定义toast，支持图标加文本显示
 * @param message   需要显示的文本
 * @param toastType 类型ToastType，支持Error,Warn,Info，默认Info
 * @param duration  显示时长，单位：毫秒
 */
export function showToastTips(message: string|Resource, toastType: ToastType = ToastType.Info,
  duration: number = Constant.TOAST_TIPS_DEFAULT_DURATION_MS)
{
  showToast(formatToastMessage(message, toastType), duration)
}

/**
 * 显示toast，支持文本显示
 * @param message   需要显示的文本
 * @param duration  显示时长，单位：毫秒
 */
export function showToast(message: string|Resource, duration: number = Constant.TOAST_DEFAULT_DURATION_MS) {
  if (toastUiContext) {
    toastUiContext.getPromptAction().openToast({message: message, duration: duration}).catch((err: Error) => {
      AppLogger.error('ToastUtil', `openToast failed: ${err.message}`)
    })
  } else {
    promptAction.openToast({message: message, duration: duration}).catch((err: Error) => {
      AppLogger.error('ToastUtil', `openToast failed: ${err.message}`)
    })
  }
}

/**
 * API 失败的统一 toast：网络类错误显示「网络异常，请检查网络」，
 * 其余显示调用方给的兜底文案。
 * @param msg      onFailure 拿到的错误消息
 * @param fallback 非网络错误时显示的文案
 */
export function showApiFailureToast(msg: string, fallback: string | Resource) {
  showToast(ApiErrorUtil.isNetworkMessage(msg) ? NETWORK_ERROR_MESSAGE : fallback)
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
