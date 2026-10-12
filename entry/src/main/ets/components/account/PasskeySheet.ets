import Constant from '../../model/Constant'
import { CloudThemeToken } from '../../model/CloudTheme'
import { CloudMaterial } from '../../model/CloudMaterial'
import { CloudApi } from '../../model/net/CloudApi'
import { AccountPasskey } from '../../model/net/ApiTypes'
import { ACCOUNT_PROFILE_STORE_KEY, AccountProfileStore } from '../../model/AccountProfileStore'
import { SettingsRules } from '../../utils/SettingsRules'
import { showCloudConfirmDialog } from '../../utils/CloudDialogUtil'
import { showToast } from '../../utils/ToastUtil'

@Component
export struct PasskeySheet {
  @StorageProp(Constant.NAV_BOTTOM_RECT_HEIGHT) bottomRectHeight: number = 0
  @StorageLink(ACCOUNT_PROFILE_STORE_KEY) store: AccountProfileStore = AccountProfileStore.instance

  build() {
    Column({ space: CloudThemeToken.spacingSection }) {
      Text('添加新的通行密钥需要在网页端操作')
        .fontSize(CloudThemeToken.textSizeSmallPlus)
        .fontColor(CloudThemeToken.textSecondary)
      if ((this.store.account?.passkeys ?? []).length === 0) {
        Text('暂无通行密钥')
          .fontSize(CloudThemeToken.textSizeBody)
          .fontColor(CloudThemeToken.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(CloudThemeToken.spacingPage)
      } else {
        Column() {
          ForEach(this.store.account?.passkeys ?? [], (passkey: AccountPasskey, index: number) => {
            Row({ space: CloudThemeToken.spacingSection }) {
              Column({ space: CloudThemeToken.spacingTiny }) {
                Text(passkey.name.length > 0 ? passkey.name : '未命名')
                  .fontSize(CloudThemeToken.textSizeLarge)
                  .fontColor(CloudThemeToken.textPrimary)
                Text(this.passkeyMeta(passkey))
                  .fontSize(CloudThemeToken.textSizeSmall)
                  .fontColor(CloudThemeToken.textSecondary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('删除')
                .fontSize(CloudThemeToken.textSizeBody)
                .fontColor(CloudThemeToken.danger)
                .padding(CloudThemeToken.spacingXl)
                .onClick(() => this.confirmDelete(passkey))
            }
            .width('100%')
            .constraintSize({ minHeight: CloudThemeToken.rowHeight4xl })
            .padding({ left: CloudThemeToken.spacingPanel, right: CloudThemeToken.spacingXs })
            .border(index > 0
              ? { width: { top: CloudThemeToken.lineWidth }, color: CloudThemeToken.line }
              : { width: 0 })
          }, (passkey: AccountPasskey) => passkey.id)
        }
        .width('100%')
        .borderRadius(CloudThemeToken.settingGroupRadius)
        // 同输入框：半透明底 + 细描边，不用 surfaceSubtle 实色块盖住半模态材质
        .backgroundColor(CloudMaterial.fieldBackground())
        .border(CloudThemeToken.inputBorder(false))
        .clip(true)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: CloudThemeToken.spacingSheetHorizontal,
      right: CloudThemeToken.spacingSheetHorizontal,
      top: CloudThemeToken.spacingSheetTop,
      bottom: this.bottomRectHeight + CloudThemeToken.spacingSheetBottom
    })
  }

  private passkeyMeta(passkey: AccountPasskey): string {
    const created = SettingsRules.formatDate(passkey.created_at)
    const used = SettingsRules.formatDate(passkey.used_at)
    return SettingsRules.joinNonEmpty([
      created.length > 0 ? `${created} 创建` : '',
      used.length > 0 ? `${used} 使用过` : '从未使用'
    ], ' · ')
  }

  private confirmDelete(passkey: AccountPasskey): void {
    showCloudConfirmDialog(this.getUIContext(), {
      title: '删除通行密钥？',
      message: passkey.name,
      confirmText: $r('app.string.dialog_delete'),
      onConfirm: () => {
        CloudApi.deletePasskey(passkey.id, {
          onSuccess: () => {
            this.store.removePasskey(passkey.id)
            showToast('已删除通行密钥')
          },
          onFailure: (msg: string) => {
            showToast(SettingsRules.apiMessage(msg))
          }
        })
      }
    })
  }
}
