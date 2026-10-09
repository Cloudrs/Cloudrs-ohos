import Constant from '../model/Constant'
import { CloudThemeToken } from '../model/CloudTheme'
import { CloudMaterial } from '../model/CloudMaterial'
import { PhotoBackupSettings } from '../model/PhotoBackupModel'
import { PhotoBackupSettingsStore, PHOTO_BACKUP_REVISION_KEY } from '../model/PhotoBackupSettingsStore'
import { SubPageScaffold } from '../components/SubPageScaffold'
import { PathSelectSheet } from '../components/PathSelectSheet'
import {
  SettingGroup, SettingRow, SettingSectionTitle, SettingStepperRow, SettingSwitchRow
} from '../components/settings/SettingRows'

/** 相册备份设置（原「我的」页里的半模态）：所有项即改即存，备份路径另开路径选择半模态 */
@Component
export struct PhotoBackupPage {
  // 宽屏在「我的」内容区内打开时由 TabMine 传入：标题栏左内边距（让出悬浮折叠键）与返回回调；
  // 未传时 -1 / undefined，走默认 pagePadding 与 CloudRouter.pop()
  @Prop titleStartPadding: number = -1
  onBack?: () => void
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) topRectHeight: number = 0
  @StorageProp(Constant.WINDOW_WIDTH_VP) sheetLayoutWidth: number = 0
  // 相册页也能开关备份；任何一处 save 都会递增修订号，这里跟着重读，两边保持一致
  @StorageProp(PHOTO_BACKUP_REVISION_KEY) @Watch('reloadSettings') settingsRevision: number = 0
  @State settings: PhotoBackupSettings = new PhotoBackupSettings()
  @State showPathSheet: boolean = false
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.reloadSettings()
  }

  private reloadSettings(): void {
    this.settings = PhotoBackupSettingsStore.load()
  }

  // 以持久化的设置为底改一项再存；save 会递增修订号，触发 reloadSettings 刷新界面
  private update(mutate: (s: PhotoBackupSettings) => void): void {
    const next = PhotoBackupSettingsStore.load()
    mutate(next)
    PhotoBackupSettingsStore.save(next)
  }

  build() {
    Stack() {
      SubPageScaffold({
        title: '相册备份', startPadding: this.titleStartPadding, scroller: this.scroller, onBackClick: this.onBack
      }) {
        // 内容铺满全页、从标题栏底下滚过（顶部留出标题栏高度），上滑时标题栏出模糊材质
        Scroll(this.scroller) {
          Column({ space: CloudThemeToken.sectionGap }) {
            Column({ space: CloudThemeToken.spacingXl }) {
              SettingSectionTitle({ title: '备份' })
              this.backupGroup()
            }
            .width('100%')
            Column({ space: CloudThemeToken.spacingXl }) {
              SettingSectionTitle({ title: '上传' })
              this.uploadGroup()
            }
            .width('100%')
            Text('备份进度可在「相册」页标题旁查看')
              .fontSize(CloudThemeToken.textSizeSmall)
              .fontColor(CloudThemeToken.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({
            left: CloudThemeToken.pagePadding,
            right: CloudThemeToken.pagePadding,
            top: CloudThemeToken.hdsTitleBarHeight(this.topRectHeight) + CloudThemeToken.spacingXs,
            bottom: this.bottomRectHeight + CloudThemeToken.pageBottomPadding
          })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      this.pathSheetHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CloudThemeToken.background)
  }

  @Builder backupGroup() {
    SettingGroup() {
      SettingSwitchRow({
        title: '开启自动备份',
        desc: '扫描本地图片并上传到云端',
        isOn: this.settings.enabled,
        onChange: (isOn: boolean) => {
          this.update((s: PhotoBackupSettings) => { s.enabled = isOn })
        }
      })
      SettingRow({
        title: '备份路径',
        desc: this.settings.remotePath,
        divider: true,
        onTap: () => {
          this.showPathSheet = true
        }
      })
    }
  }

  @Builder uploadGroup() {
    SettingGroup() {
      SettingSwitchRow({
        title: '仅 Wi-Fi 下备份',
        desc: '关闭后将使用移动网络备份',
        isOn: this.settings.wifiOnly,
        onChange: (isOn: boolean) => {
          this.update((s: PhotoBackupSettings) => { s.wifiOnly = isOn })
        }
      })
      SettingStepperRow({
        title: '同时上传数量',
        desc: '同时上传的照片数，弱网时建议调低',
        value: this.settings.uploadConcurrent,
        min: Constant.UPLOAD_CONCURRENT_MIN,
        max: Constant.UPLOAD_CONCURRENT_MAX,
        divider: true,
        onChange: (next: number) => {
          this.update((s: PhotoBackupSettings) => { s.uploadConcurrent = next })
        }
      })
    }
  }

  @Builder pathSheetHost() {
    Column().width(0).height(0)
      .bindSheet($$this.showPathSheet, this.pathSheet(), {
        showClose: false,
        backgroundColor: CloudMaterial.materialSurface(CloudThemeToken.background),
        systemMaterial: CloudMaterial.sheetMaterial(),
        preferType: CloudThemeToken.sheetTypeForWidth(this.sheetLayoutWidth),
        width: CloudThemeToken.sheetWidthForWidth(this.sheetLayoutWidth),
        onDisappear: () => {
          this.showPathSheet = false
        }
      })
  }

  @Builder pathSheet() {
    PathSelectSheet({
      title: $r('app.string.backup_to'),
      filterDirId: '',
      onClose: (isFinished: boolean, path?: string) => {
        this.showPathSheet = false
        if (isFinished && path && path.length > 0) {
          this.update((s: PhotoBackupSettings) => { s.remotePath = path })
        }
      }
    })
  }
}
