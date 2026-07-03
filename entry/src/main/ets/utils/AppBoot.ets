/**
 * 启动就绪门闩：loadContent 已提前到 onWindowStageCreate 开头以尽快出首帧，
 * 数据库/首选项等初始化改为首帧后异步执行。依赖这些初始化的启动逻辑
 * （如 CloudRouter.showStartPage 的登录态判定）须先 await whenReady()。
 */
export class AppBoot {
  private static ready: boolean = false
  private static waiters: Array<() => void> = []

  static markReady(): void {
    if (AppBoot.ready) {
      return
    }
    AppBoot.ready = true
    const waiters = AppBoot.waiters
    AppBoot.waiters = []
    for (const resolve of waiters) {
      resolve()
    }
  }

  static whenReady(): Promise<void> {
    if (AppBoot.ready) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      AppBoot.waiters.push(resolve)
    })
  }
}
