export class CloudThemeToken {
  static readonly pagePadding: number = 16
  static readonly sectionGap: number = 16
  static readonly cardRadius: number = 8
  static readonly surfaceRadius: number = 24
  static readonly controlRadius: number = 22
  static readonly tabBarHeight: number = 78
  static readonly iconButtonSize: number = 40

  static readonly background: ResourceColor = $r('app.color.cloud_background')
  static readonly surface: ResourceColor = $r('app.color.cloud_surface')
  static readonly surfaceSubtle: ResourceColor = $r('app.color.cloud_surface_subtle')
  static readonly surfaceTranslucent: ResourceColor = $r('app.color.cloud_surface_translucent')
  static readonly line: ResourceColor = $r('app.color.cloud_line')
  static readonly primary: ResourceColor = $r('app.color.cloud_primary')
  static readonly primarySoft: ResourceColor = $r('app.color.cloud_primary_soft')
  static readonly textPrimary: ResourceColor = $r('app.color.cloud_text_primary')
  static readonly textSecondary: ResourceColor = $r('app.color.cloud_text_secondary')
  static readonly danger: ResourceColor = $r('app.color.cloud_danger')
  static readonly success: ResourceColor = $r('app.color.cloud_success')
}

export enum CloudLayoutMode {
  PHONE = 'phone',
  TABLET = 'tablet',
  WIDE = 'wide'
}
