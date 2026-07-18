import { common } from '@kit.AbilityKit'
import { BusinessError, emitter } from '@kit.BasicServicesKit'
import { statusBarManager } from '@kit.DeskTopExtensionKit'
import { image } from '@kit.ImageKit'
import AppLogger from './AppLogger'

const TAG: string = 'CloudStatusBar'

export class CloudStatusBar {
  private static context: common.UIAbilityContext | undefined = undefined
  private static registered: boolean = false
  private static listenerRegistered: boolean = false

  private static readonly iconClickListener = (event: emitter.EventData): void => {
    const clickType = event.data?.['iconClickType'] as string | undefined
    if (clickType !== 'leftClick') {
      return
    }
    const context = CloudStatusBar.context
    if (!context) {
      AppLogger.warn(TAG, 'show ability ignored because UIAbilityContext is unavailable')
      return
    }
    context.showAbility().catch((err: Error) => {
      AppLogger.error(TAG, `show ability from status bar failed: ${err.message}`)
    })
  }

  static async register(context: common.UIAbilityContext): Promise<void> {
    CloudStatusBar.context = context
    if (CloudStatusBar.registered) {
      return
    }

    const item = await CloudStatusBar.createStatusBarItem(context)
    try {
      await CloudStatusBar.addToStatusBar(context, item)
      CloudStatusBar.registered = true
      AppLogger.info(TAG, 'status bar icon registered')
      if (!CloudStatusBar.listenerRegistered) {
        statusBarManager.on('statusBarIconClick', CloudStatusBar.iconClickListener)
        CloudStatusBar.listenerRegistered = true
      }
    } catch (err) {
      throw new Error((err as Error)?.message ?? `${err}`)
    }
  }

  static isRegistered(): boolean {
    return CloudStatusBar.registered
  }

  static bindContext(context: common.UIAbilityContext): void {
    CloudStatusBar.context = context
  }

  static async showAbility(): Promise<void> {
    const context = CloudStatusBar.context
    if (!context) {
      throw new Error('UIAbilityContext is unavailable')
    }
    await context.showAbility()
  }

  private static addToStatusBar(context: common.UIAbilityContext,
    item: statusBarManager.StatusBarItem): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      statusBarManager.addToStatusBar(context, item, (err: BusinessError): void => {
        if (err) {
          reject(new Error(`code=${err.code}, message=${err.message}`))
          return
        }
        resolve()
      })
    })
  }

  static dispose(): void {
    if (CloudStatusBar.listenerRegistered) {
      try {
        statusBarManager.off('statusBarIconClick', CloudStatusBar.iconClickListener)
      } catch (err) {
        AppLogger.warn(TAG, `unregister icon click listener failed: ${(err as Error)?.message ?? err}`)
      }
    }
    CloudStatusBar.listenerRegistered = false
    CloudStatusBar.registered = false
    CloudStatusBar.context = undefined
  }

  private static async createStatusBarItem(context: common.UIAbilityContext): Promise<statusBarManager.StatusBarItem> {
    const white = await CloudStatusBar.loadPixelMap(context, 'cloudrs_statusbar_white.png')
    const black = await CloudStatusBar.loadPixelMap(context, 'cloudrs_statusbar_black.png')

    return {
      icons: { white: white, black: black },
      quickOperation: {
        title: 'Cloudrs',
        height: 160,
        abilityName: ''
      },
      hoverTips: 'Cloudrs'
    }
  }

  private static async loadPixelMap(context: common.UIAbilityContext, rawFileName: string): Promise<image.PixelMap> {
    const fileData = context.resourceManager.getRawFileContentSync(rawFileName)
    const source = image.createImageSource(fileData.buffer)
    return source.createPixelMap()
  }
}
