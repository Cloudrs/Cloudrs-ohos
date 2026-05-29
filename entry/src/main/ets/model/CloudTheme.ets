export class CloudThemeToken {
  static readonly pagePadding: number = 16
  static readonly sectionGap: number = 16
  static readonly cardRadius: number = 8
  static readonly surfaceRadius: number = 24
  static readonly controlRadius: number = 22
  static readonly inputInnerRadius: number = 0
  static readonly otpCellRadius: number = 10
  static readonly tabBarHeight: number = 78
  static readonly tabBarRadius: number = 32
  static readonly floatingTabBarVisualHeight: number = 64
  static readonly floatingTabBarBottomGap: number = 10
  static readonly floatingTabBarMaxWidth: number = 520
  static readonly floatingTabItemHeight: number = 48
  static readonly floatingTabItemWideWidth: number = 112
  static readonly twoColumnBreakpoint: number = 520
  static readonly tabletBreakpoint: number = 720
  static readonly wideBreakpoint: number = 920
  static readonly smallIconButtonSize: number = 36
  static readonly iconButtonSize: number = 40
  static readonly actionIconSize: number = 22
  static readonly compactIconSize: number = 20
  static readonly titleBarHeight: number = 50
  static readonly inputHeight: number = 48
  static readonly menuWidth: number = 220
  static readonly menuItemHeight: number = 45
  static readonly menuItemLabelHeight: number = 50
  static readonly transferFileIconSize: number = 40
  static readonly transferStateIconSize: number = 12
  static readonly transferProgressWidth: number = 60
  static readonly transferProgressHeight: number = 30
  static readonly sheetActionIconSize: number = 16
  static readonly sheetOptionIconSize: number = 40
  static readonly sheetOptionTileSize: number = 88
  static readonly sheetOptionRowHeight: number = 112
  static readonly uploadSourceRowHeight: number = 72
  static readonly uploadSourceIconBoxSize: number = 46
  static readonly sheetHeaderHeight: number = 70
  static readonly sheetConfirmHeight: number = 36
  static readonly pathRowHeight: number = 45
  static readonly pathInnerRowHeight: number = 43
  static readonly pathLabelHeight: number = 32
  static readonly pathFolderIconSize: number = 30
  static readonly pathChevronWidth: number = 24
  static readonly pathChevronHeight: number = 12

  static readonly background: ResourceColor = $r('app.color.cloud_background')
  static readonly surface: ResourceColor = $r('app.color.cloud_surface')
  static readonly surfaceSubtle: ResourceColor = $r('app.color.cloud_surface_subtle')
  static readonly surfaceTranslucent: ResourceColor = $r('app.color.cloud_surface_translucent')
  static readonly line: ResourceColor = $r('app.color.cloud_line')
  static readonly primary: ResourceColor = $r('app.color.cloud_primary')
  static readonly primarySoft: ResourceColor = $r('app.color.cloud_primary_soft')
  static readonly textPrimary: ResourceColor = $r('app.color.cloud_text_primary')
  static readonly textSecondary: ResourceColor = $r('app.color.cloud_text_secondary')
  static readonly onPrimary: Color = Color.White
  static readonly transparent: Color = Color.Transparent
  static readonly previewBackground: Color = Color.Black
  static readonly danger: ResourceColor = $r('app.color.cloud_danger')
  static readonly dangerSoft: ResourceColor = $r('app.color.cloud_danger_soft')
  static readonly success: ResourceColor = $r('app.color.cloud_success')
  static readonly successSoft: ResourceColor = $r('app.color.cloud_success_soft')
  static readonly uploadFileSoft: ResourceColor = '#EAF2FF'
  static readonly uploadPhotoSoft: ResourceColor = '#EAF9F0'
  static readonly uploadVideoSoft: ResourceColor = '#F1EAFF'
  static readonly glassHighlight: ResourceColor = '#8CFFFFFF'
  static readonly floatingShadow: ResourceColor = '#260A59F7'
  static readonly selectedGlow: ResourceColor = '#33115DFC'
  static readonly selectedHighlight: ResourceColor = '#66FFFFFF'
  static readonly refreshShadow: ResourceColor = 'rgba(24, 36, 56, 0.12)'
  static readonly overlayScrim: ResourceColor = 'rgba(0, 0, 0, 0.28)'
  static readonly sheetShadow: ResourceColor = 'rgba(0, 0, 0, 0.18)'

  static getLayoutMode(width: number): CloudLayoutMode {
    if (width >= CloudThemeToken.wideBreakpoint) {
      return CloudLayoutMode.WIDE
    }
    if (width >= CloudThemeToken.tabletBreakpoint) {
      return CloudLayoutMode.TABLET
    }
    return CloudLayoutMode.PHONE
  }
}

export enum CloudLayoutMode {
  PHONE = 'phone',
  TABLET = 'tablet',
  WIDE = 'wide'
}
