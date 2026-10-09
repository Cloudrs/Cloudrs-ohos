// Lifecycle phase of a bindSheet, driven by its
// onWillAppear/onAppear/onWillDisappear/onDisappear callbacks.
enum SheetPhase {
  CLOSED,
  OPENING,
  OPEN,
  CLOSING
}

// Drives a single bindSheet off its real lifecycle phase instead of the bound
// flag (which stays true throughout the close animation). An open request that
// arrives while the sheet is still closing is queued and replayed once it
// finishes closing, instead of re-setting the flag mid-animation — which races
// the close and ends up dismissing the sheet (so the tap does nothing). The
// flag is only re-triggered (false→true) for a genuinely stale flag (true with
// no visible sheet).
export class SheetPhaseController {
  private phase: SheetPhase = SheetPhase.CLOSED
  private reopenPending: boolean = false
  /** 排队中的"稍后打开"，requestClose 要能把它撤销 */
  private pendingOpenTimer: number = -1

  requestOpen(getFlag: () => boolean, setFlag: (value: boolean) => void): void {
    if (getFlag() && (this.phase === SheetPhase.OPEN || this.phase === SheetPhase.OPENING)) {
      this.reopenPending = false
      return
    }
    if (this.phase === SheetPhase.CLOSED) {
      this.reopenPending = false
      if (getFlag()) {
        setFlag(false)
        this.clearPendingOpen()
        this.pendingOpenTimer = setTimeout(() => {
          this.pendingOpenTimer = -1
          setFlag(true)
        }, 50)
      } else {
        setFlag(true)
      }
      return
    }
    this.reopenPending = true
    setFlag(false)
  }

  /**
   * 收起面板，并撤销一切待打开的意图。
   *
   * 直接把绑定量设 false 是不够的：requestOpen 可能已经排了个 50ms 后打开的
   * 定时器，或标了 reopenPending，它们会在之后把面板重新拉起来——盖住此刻真正
   * 要给用户看的那一层。想让路就得连意图一起撤掉。
   */
  requestClose(setFlag: (value: boolean) => void): void {
    this.clearPendingOpen()
    this.reopenPending = false
    setFlag(false)
  }

  private clearPendingOpen(): void {
    if (this.pendingOpenTimer >= 0) {
      clearTimeout(this.pendingOpenTimer)
      this.pendingOpenTimer = -1
    }
  }

  onWillAppear(): void {
    this.phase = SheetPhase.OPENING
  }

  onAppear(): void {
    this.phase = SheetPhase.OPEN
  }

  onWillDisappear(): void {
    this.phase = SheetPhase.CLOSING
  }

  onDisappear(setFlag: (value: boolean) => void, onClosed: () => void): void {
    this.phase = SheetPhase.CLOSED
    if (this.reopenPending) {
      this.reopenPending = false
      setTimeout(() => setFlag(true), 50)
    } else {
      onClosed()
    }
  }
}
