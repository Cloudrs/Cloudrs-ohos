export enum CloudBreakpoint {
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl'
}

export class BreakpointType<T> {
  readonly sm: T
  readonly md: T
  readonly lg: T
  readonly xl: T

  constructor(sm: T, md: T, lg: T, xl: T) {
    this.sm = sm
    this.md = md
    this.lg = lg
    this.xl = xl
  }

  getValue(bp: CloudBreakpoint): T {
    if (bp === CloudBreakpoint.SM) {
      return this.sm
    }
    if (bp === CloudBreakpoint.MD) {
      return this.md
    }
    if (bp === CloudBreakpoint.LG) {
      return this.lg
    }
    return this.xl
  }
}
