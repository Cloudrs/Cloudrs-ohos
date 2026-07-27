import { AbilityConstant, Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import AppLogger from './AppLogger';
import { showToastTips, ToastType } from './ToastUtil';

const TAG: string = 'ContinuationCenter'

/**
 * 应用接续中枢：源端收集可接续状态、写入 wantParam，对端解析并暂存待恢复状态。
 *
 * 链路上有两处真机验证得出的非对称，实现时必须照顾：
 * 1. 接续启动只回调 onWindowStageRestore，不回调 onWindowStageCreate（loadContent 在后者）。
 * 2. 2in1 上 UI 跑在 MainAbility，接续先落到 EntryAbility 跳板再转发，
 *    转发后 MainAbility 收到的 launchReason 是 START_ABILITY 而非 CONTINUATION。
 *    因此判定"是否接续恢复"一律以 payload 是否存在为准，绝不看 launchReason。
 */

// wantParam 键名。系统预置了 version/targetDevice/pageStack/sessionId 等，加前缀避开
const KEY_PAGE: string = 'cloudrsContinuePage'
const KEY_FILE_ID: string = 'cloudrsContinueFileId'
const KEY_FILE_NAME: string = 'cloudrsContinueFileName'
const KEY_FILE_EXT: string = 'cloudrsContinueFileExt'
const KEY_SHARE_PATH: string = 'cloudrsContinueSharePath'
const KEY_TIME: string = 'cloudrsContinueTime'
const KEY_PLAYING: string = 'cloudrsContinuePlaying'
const KEY_USER: string = 'cloudrsContinueUser'
const KEY_SITE: string = 'cloudrsContinueSite'
const KEY_SCHEMA: string = 'cloudrsContinueSchema'

const PAGE_VIDEO: string = 'VideoPreview'

/**
 * 载荷结构版本。改动已有字段的语义时 +1(纯新增字段不用动)。
 *
 * 这是兼容判断的主依据：versionCode 由 hvigorfile 按构建日期生成(YYMMdd+index)，
 * 跟载荷结构没有语义关联，不适合单独承担这个职责。
 */
const PAYLOAD_SCHEMA_VERSION: number = 1

/**
 * 接续可用的最低对端 versionCode，用于源端握手阶段的粗筛
 * ——此时对端还没运行我们的代码，wantParam.version 是唯一能拿到的对端信息。
 * 取引入接续能力之前的基线版本即可，不需要每次发版维护。
 */
const MIN_COMPATIBLE_VERSION_CODE: number = 2607191

/** 可接续的视频播放状态 */
export interface VideoContinuationState {
  fileId: string
  fileName: string
  fileExtension: string
  sharePath: string
  currentTime: number
  isPlaying: boolean
  // 账号定位：对端需切到同一站点的同一用户才能取到直链
  userName: string
  siteUrl: string
}

export class ContinuationCenter {
  // 源端当前可接续状态；离开视频页即清空
  private static videoState: VideoContinuationState | undefined = undefined
  // 对端解析出的待恢复状态，等 Index 就绪后消费
  private static pendingRestore: VideoContinuationState | undefined = undefined
  // Index 注册的恢复入口。热启动接续走 onNewWant，此时 Index 早已建好，
  // 不会再走 aboutToAppear，必须主动回调它
  private static restoreHandler: (() => void) | undefined = undefined
  // 接续已挂起、正等用户登录目标账号
  private static awaitingLogin: boolean = false
  // 收到了读不懂的新版载荷，待界面就绪后告知用户
  private static incompatibleNotice: boolean = false

  /** 源端：视频页持续上报播放状态（秒级更新，纯内存写，不进 AppStorage） */
  static setVideoState(state: VideoContinuationState): void {
    ContinuationCenter.videoState = state
  }

  /** 源端：仅更新进度与播放态，避免每秒重建整个对象 */
  static updateVideoProgress(currentTime: number, isPlaying: boolean): void {
    const state = ContinuationCenter.videoState
    if (!state) {
      return
    }
    state.currentTime = currentTime
    state.isPlaying = isPlaying
  }

  /** 源端：离开视频页，不再可接续 */
  static clearVideoState(): void {
    ContinuationCenter.videoState = undefined
  }

  static hasVideoState(): boolean {
    return ContinuationCenter.videoState !== undefined
  }

  /**
   * 源端：校验对端应用版本。onContinue 的 wantParam.version 由系统填入对端 versionCode。
   * 取不到版本号时不阻断，避免误伤正常接续。
   */
  static isTargetVersionCompatible(wantParam: Record<string, Object>): boolean {
    const raw = wantParam.version
    if (raw === undefined || raw === null) {
      AppLogger.warn(TAG, 'target version absent, skip compatibility check')
      return true
    }
    const targetVersion = Number(raw)
    if (!Number.isFinite(targetVersion)) {
      AppLogger.warn(TAG, `target version unrecognized: ${raw}`)
      return true
    }
    if (targetVersion < MIN_COMPATIBLE_VERSION_CODE) {
      AppLogger.warn(TAG,
        `target version ${targetVersion} below min ${MIN_COMPATIBLE_VERSION_CODE}, reject continuation`)
      showToastTips('对方设备上的版本过旧，升级后才能接续', ToastType.Warn)
      return false
    }
    return true
  }

  /** 源端：把可接续状态写进 wantParam，返回是否有内容可迁移 */
  static writeTo(wantParam: Record<string, Object>): boolean {
    const state = ContinuationCenter.videoState
    if (!state) {
      return false
    }
    wantParam[KEY_SCHEMA] = PAYLOAD_SCHEMA_VERSION
    wantParam[KEY_PAGE] = PAGE_VIDEO
    wantParam[KEY_FILE_ID] = state.fileId
    wantParam[KEY_FILE_NAME] = state.fileName
    wantParam[KEY_FILE_EXT] = state.fileExtension
    wantParam[KEY_SHARE_PATH] = state.sharePath
    wantParam[KEY_TIME] = state.currentTime
    wantParam[KEY_PLAYING] = state.isPlaying
    wantParam[KEY_USER] = state.userName
    wantParam[KEY_SITE] = state.siteUrl
    AppLogger.info(TAG,
      `write payload schema=${PAYLOAD_SCHEMA_VERSION} fileId=${state.fileId} time=${Math.floor(state.currentTime)}`)
    return true
  }

  /** 对端：want 里是否带着接续载荷（跳板转发后 launchReason 不可信，只认这个） */
  static hasPayload(want: Want): boolean {
    return ContinuationCenter.readString(want, KEY_PAGE) === PAGE_VIDEO
  }

  /** 对端：解析 want 并暂存，等 Index 就绪后消费 */
  static acceptPayload(want: Want): boolean {
    if (!ContinuationCenter.hasPayload(want)) {
      return false
    }
    // 源端结构比本机新：字段语义可能已变，宁可明说也不要按旧规则误读
    const schema = ContinuationCenter.readNumber(want, KEY_SCHEMA)
    if (schema > PAYLOAD_SCHEMA_VERSION) {
      AppLogger.warn(TAG,
        `payload schema ${schema} newer than supported ${PAYLOAD_SCHEMA_VERSION}, drop`)
      // 此刻在 Ability 生命周期里，应用正被拉起、窗口还在切换，toast 弹不出来。
      // 挂起一条待告知，等 Index 就绪后再弹对话框。
      ContinuationCenter.incompatibleNotice = true
      return false
    }
    const fileId = ContinuationCenter.readString(want, KEY_FILE_ID)
    if (fileId.length === 0) {
      AppLogger.warn(TAG, 'payload missing fileId, drop')
      return false
    }
    const state: VideoContinuationState = {
      fileId: fileId,
      fileName: ContinuationCenter.readString(want, KEY_FILE_NAME),
      fileExtension: ContinuationCenter.readString(want, KEY_FILE_EXT),
      sharePath: ContinuationCenter.readString(want, KEY_SHARE_PATH),
      currentTime: ContinuationCenter.readNumber(want, KEY_TIME),
      isPlaying: ContinuationCenter.readBoolean(want, KEY_PLAYING),
      userName: ContinuationCenter.readString(want, KEY_USER),
      siteUrl: ContinuationCenter.readString(want, KEY_SITE)
    }
    ContinuationCenter.pendingRestore = state
    // 新的一次接续，重置上一轮遗留的等登录标记
    ContinuationCenter.awaitingLogin = false
    AppLogger.info(TAG,
      `accept payload fileId=${state.fileId} time=${Math.floor(state.currentTime)} user=${state.userName}`)
    return true
  }

  /** 对端：查看待恢复状态但不消费，账号校验通过后再 consume */
  static peekPendingRestore(): VideoContinuationState | undefined {
    return ContinuationCenter.pendingRestore
  }

  /** 对端：取走待恢复状态，只会成功一次 */
  static consumePendingRestore(): VideoContinuationState | undefined {
    const pending = ContinuationCenter.pendingRestore
    ContinuationCenter.pendingRestore = undefined
    ContinuationCenter.awaitingLogin = false
    return pending
  }

  static hasPendingRestore(): boolean {
    return ContinuationCenter.pendingRestore !== undefined
  }

  /**
   * 标记接续正挂起等待用户登录。
   * 登录完成后如果账号仍对不上，就不再二次跳登录页，避免来回弹。
   */
  static markAwaitingLogin(): void {
    ContinuationCenter.awaitingLogin = true
  }

  static isAwaitingLogin(): boolean {
    return ContinuationCenter.awaitingLogin
  }

  /** Index 就绪时注册恢复入口 */
  static setRestoreHandler(handler?: () => void): void {
    ContinuationCenter.restoreHandler = handler
  }

  /** 取走"版本不兼容"待告知，只会成功一次 */
  static consumeIncompatibleNotice(): boolean {
    const pending = ContinuationCenter.incompatibleNotice
    ContinuationCenter.incompatibleNotice = false
    return pending
  }

  /** 热启动接续：Index 已存在，主动驱动一次恢复（或告知不兼容） */
  static notifyRestore(): void {
    if (!ContinuationCenter.pendingRestore && !ContinuationCenter.incompatibleNotice) {
      return
    }
    const handler = ContinuationCenter.restoreHandler
    if (!handler) {
      // Index 尚未建好（冷启动），它会在 aboutToAppear 里自行消费
      return
    }
    handler()
  }

  /**
   * 控制系统接续图标的出现时机：只有视频页 ACTIVE，
   * 否则用户在文件列表页也会看到接续入口，点了却无内容可接。
   */
  static setMissionContinueState(context: common.UIAbilityContext | undefined, active: boolean): void {
    if (!context) {
      return
    }
    const state = active
      ? AbilityConstant.ContinueState.ACTIVE
      : AbilityConstant.ContinueState.INACTIVE
    context.setMissionContinueState(state).catch((err: Error) => {
      AppLogger.warn(TAG, `setMissionContinueState(${active}) failed: ${err.message}`)
    })
  }

  private static readString(want: Want, key: string): string {
    const raw = want.parameters?.[key]
    return raw === undefined || raw === null ? '' : `${raw}`
  }

  private static readNumber(want: Want, key: string): number {
    const raw = want.parameters?.[key]
    if (raw === undefined || raw === null) {
      return 0
    }
    const value = Number(raw)
    return Number.isFinite(value) && value > 0 ? value : 0
  }

  private static readBoolean(want: Want, key: string): boolean {
    const raw = want.parameters?.[key]
    return raw === true || `${raw}` === 'true'
  }
}
