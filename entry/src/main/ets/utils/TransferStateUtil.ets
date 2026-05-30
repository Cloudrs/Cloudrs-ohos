import { FileModelState } from "../model/FileModel";
import { CloudThemeToken } from "../model/CloudTheme";
import { TransportObject } from "../model/TransportObject";
import { CommonUtil } from "./CommonUtil";

export class TransferStateUtil {
  static getStateColor(state: FileModelState): ResourceColor {
    switch (state) {
      case FileModelState.COMPLETED:
        return CloudThemeToken.success
      case FileModelState.FAILED:
        return CloudThemeToken.danger
      default:
        return CloudThemeToken.primary
    }
  }

  static getStateIcon(state: FileModelState, runningIcon: Resource): Resource {
    switch (state) {
      case FileModelState.COMPLETED:
        return $r('app.media.ic_checkmark_circle')
      case FileModelState.FAILED:
        return $r('app.media.ic_xmark_circle_fill')
      default:
        return runningIcon
    }
  }

  static getCommonStateText(state: FileModelState, failedText: string): string | undefined {
    switch (state) {
      case FileModelState.COMPLETED:
        return '已完成'
      case FileModelState.FAILED:
        return failedText
      case FileModelState.WAITING:
        return '等待中'
      case FileModelState.RETRYING:
        return '重试中'
      case FileModelState.PAUSED:
        return '已暂停'
      case FileModelState.STOPPED:
        return '已停止'
      case FileModelState.REMOVED:
        return '已移除'
      default:
        return undefined
    }
  }

  static getSpeedText(object: TransportObject): string {
    return CommonUtil.formatBytes(object.speed, CloudThemeToken.lineWidth) + '/s'
  }

  static isServerProcessing(object: TransportObject): boolean {
    return object.progress >= CloudThemeToken.percentageAlmostFull && object.trans >= object.total
  }
}
