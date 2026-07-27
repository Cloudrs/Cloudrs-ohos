import { UIContext } from '@kit.ArkUI'

export interface CloudConfirmDialogOptions {
  title: ResourceStr
  message?: ResourceStr
  confirmText: ResourceStr
  cancelText?: ResourceStr
  onConfirm: () => void
  onCancel?: () => void
}

export interface CloudNoticeDialogOptions {
  title: ResourceStr
  message?: ResourceStr
  confirmText?: ResourceStr
  onConfirm?: () => void
}

export interface CloudActionDialogOptions {
  title: ResourceStr
  message?: ResourceStr
  primaryText: ResourceStr
  secondaryText: ResourceStr
  onPrimary: () => void
  onSecondary: () => void
}

export function showCloudActionDialog(uiContext: UIContext, options: CloudActionDialogOptions): void {
  uiContext.showAlertDialog({
    title: options.title,
    message: options.message ?? '',
    primaryButton: {
      value: options.primaryText,
      action: options.onPrimary
    },
    secondaryButton: {
      value: options.secondaryText,
      action: options.onSecondary
    }
  })
}

/** 单按钮告知型弹窗：只需用户知晓、无需选择的场景 */
export function showCloudNoticeDialog(uiContext: UIContext, options: CloudNoticeDialogOptions): void {
  uiContext.showAlertDialog({
    title: options.title,
    message: options.message ?? '',
    confirm: {
      value: options.confirmText ?? '知道了',
      action: () => {
        if (options.onConfirm) {
          options.onConfirm()
        }
      }
    }
  })
}

export function showCloudConfirmDialog(uiContext: UIContext, options: CloudConfirmDialogOptions): void {
  showCloudActionDialog(uiContext, {
    title: options.title,
    message: options.message,
    primaryText: options.cancelText ?? $r('app.string.dialog_cancel'),
    secondaryText: options.confirmText,
    onPrimary: () => {
      if (options.onCancel) {
        options.onCancel()
      }
    },
    onSecondary: options.onConfirm
  })
}
