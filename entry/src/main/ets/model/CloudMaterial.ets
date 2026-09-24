import { uiMaterial } from '@kit.ArkUI'
import { CloudThemeToken } from './CloudTheme'
import { SuppressWarnings, SuppressWarningsType, deviceInfo } from '@kit.BasicServicesKit';
import AppLogger from '../utils/AppLogger'

const TAG = 'CloudMaterial'

/**
 * API 26 沉浸光感的统一入口。
 *
 * 本分支 compatibleSdkVersion 仍是 6.1.0(23)，一份代码要在两档 ROM 上跑：
 * 26+ 走官方沉浸式系统材质，23/24 回退到原有的 backgroundBlurStyle / backdropBlur。
 * 版本分叉只在这个文件里做，调用点不应再出现版本判断。
 *
 * 两条实测结论（验于真机 ALN-AL80/API 26 与 Mate 60 Pro 模拟器/API 23）：
 * 1. deviceInfo.apiAvailable 虽标 @since 26.0.0，但在 API 23 ROM 上确实存在，
 *    调用返回 false 而非抛异常，可安全用作门控；
 * 2. 顶部静态 import uiMaterial 在 API 23 上不崩，但材质对象必须惰性构造——
 *    写成模块级常量会在低版本 ROM 上加载即崩。
 *
 * **重要限制（实测）**：systemMaterial 作为组件属性只在 Column / Row / Stack / Text
 * 这类容器上生效，**Button 上完全没有效果**——底色一并置透明后按钮直接变空白，
 * 说明材质没画任何东西。所以按钮类控件拿不到材质，只能保留原有的手写毛玻璃。
 * 另外跨文件 export 的 AttributeModifier 其 applyNormalAttribute 根本不触发，
 * 别再试图用 modifier 收拢这些调用来消除兼容性告警，改用 @SuppressWarnings。
 *
 * 注意 apiAvailable 的版本号必须**字面量**传入，编译器才能校验并消除
 * “API supported since 26.0.0 但 compatible 是 23” 的告警；抽成常量就失效了。
 */
export class CloudMaterial {
  private static cachedSupported: boolean | undefined = undefined
  private static cachedSheetMaterial: SystemUiMaterial | undefined = undefined

  /** 当前 ROM 是否支持沉浸光感。只在首次访问时算一次，并把结论记进启动日志。 */
  static get supported(): boolean {
    if (CloudMaterial.cachedSupported === undefined) {
      CloudMaterial.cachedSupported = deviceInfo.apiAvailable('26.0.0')
      AppLogger.info(TAG, CloudMaterial.cachedSupported ? '走 API 26 沉浸光感' : '回退手写毛玻璃')
    }
    return CloudMaterial.cachedSupported
  }

  /**
   * 交给系统材质渲染的表面底色：26+ 置透明让材质透出，低版本沿用原色。
   * 用于 sheet 自身、sheet 内容区顶层容器、以及菜单这类系统接管背景的组件；
   * 内层卡片（surface / surfaceSubtle）不该用它，那些要保持不透明才有层次。
   * @param fallback 低版本 ROM 上使用的底色
   */
  static materialSurface(fallback: ResourceColor): ResourceColor {
    return CloudMaterial.supported ? Color.Transparent : fallback
  }

  private static cachedExquisite: boolean | undefined = undefined

  /**
   * 当前设备材质档位是否为最高档 EXQUISITE。材质厚度被芯片算力锁死：
   * 只有 EXQUISITE 档 THICK/ULTRA_THICK 才真的厚实、能当背景用；GENTLE/SMOOTH
   * 档材质极薄近乎透明，此时若把背景置透明交给材质，文字会被身后内容透穿看不清。
   */
  static get isExquisite(): boolean {
    if (CloudMaterial.cachedExquisite === undefined) {
      let exquisite: boolean = false
      // apiAvailable 字面量守卫必须用 if 块，编译器才认得出、消除兼容性告警
      if (deviceInfo.apiAvailable('26.0.0')) {
        exquisite = uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.EXQUISITE
      }
      CloudMaterial.cachedExquisite = exquisite
    }
    return CloudMaterial.cachedExquisite
  }

  /**
   * 文字型面板（自绘菜单）的底色：仅 EXQUISITE 档置透明、交给厚材质出通透观感；
   * 中低算力档与 <26 一律用不透明 surface，保证菜单文字任何背景下都可读。
   */
  static menuBackground(): ResourceColor {
    return CloudMaterial.isExquisite ? Color.Transparent : CloudThemeToken.surface
  }

  private static cachedCard: SystemUiMaterial | undefined = undefined

  /**
   * sheet 内层卡片底色（磨砂卡片方案）：
   * EXQUISITE 高算力档置透明、交给 THIN 材质出通透磨砂；GENTLE/SMOOTH 档材质太薄，
   * 退回半透明色 surfaceTranslucent 保可读；<26 用调用点原本的实色。
   */
  static cardBackground(fallback: ResourceColor): ResourceColor {
    if (!CloudMaterial.supported) {
      return fallback
    }
    return CloudMaterial.isExquisite ? Color.Transparent : CloudThemeToken.surfaceTranslucent
  }

  /** sheet 内层卡片材质：仅 EXQUISITE 高算力档挂 THIN 磨砂，其余档由 cardBackground 兜色。 */
  static cardMaterial(): SystemUiMaterial | undefined {
    // apiAvailable 字面量守卫必须单独用 if 块直接包住 uiMaterial 使用点，编译器才认得出并消除
    // 兼容性告警；与 isExquisite 写成 `&&` 会让识别失效（实测会报 since 26 告警）
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.isExquisite) {
        if (CloudMaterial.cachedCard === undefined) {
          CloudMaterial.cachedCard = new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THIN
          })
        }
        return CloudMaterial.cachedCard
      }
    }
    return undefined
  }

  /** bindSheet 的系统材质。低版本返回 undefined 即系统默认。 */
  static sheetMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedSheetMaterial === undefined) {
        CloudMaterial.cachedSheetMaterial = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        })
      }
      return CloudMaterial.cachedSheetMaterial
    }
    return undefined
  }

  private static cachedFloating: SystemUiMaterial | undefined = undefined
  private static cachedPanel: SystemUiMaterial | undefined = undefined

  /**
   * 压在图片/视频上的可按压控件：超薄材质保证底下画面看得见，
   * 并开交互形变与光感反馈——这类按钮直接压在内容上，手感反馈最该给。
   */
  static floatingControlMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedFloating === undefined) {
        CloudMaterial.cachedFloating = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: { color: undefined }
        })
      }
      return CloudMaterial.cachedFloating
    }
    return undefined
  }

  /** 悬浮面板、工具栏、抽屉、提示条：薄材质，整块不是按压对象故不开形变。 */
  static panelMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedPanel === undefined) {
        CloudMaterial.cachedPanel = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN
        })
      }
      return CloudMaterial.cachedPanel
    }
    return undefined
  }

  private static cachedTitleControl: SystemUiMaterial | undefined = undefined

  /**
   * 标题栏上的自绘方块键（侧栏折叠键、2in1 窗口三键）：与 HDS 标题栏菜单键并排，
   * 材质染 surfaceSubtle 取得同样的蓝灰底，否则 ULTRA_THIN 透出背景成中性灰；开形变与光感。
   */
  static titleControlMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedTitleControl === undefined) {
        CloudMaterial.cachedTitleControl = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: $r('app.color.cloud_surface_subtle'),
          interactive: true,
          lightEffect: { color: undefined }
        })
      }
      return CloudMaterial.cachedTitleControl
    }
    return undefined
  }

  private static cachedSheetControl: SystemUiMaterial | undefined = undefined

  /**
   * sheet 内的圆形按钮：比浮在画面上的控件厚一档（THIN），
   * 否则压在 sheet 材质上几乎看不出按钮轮廓；同样开形变与光感。
   */
  static sheetControlMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedSheetControl === undefined) {
        CloudMaterial.cachedSheetControl = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true,
          lightEffect: { color: undefined }
        })
      }
      return CloudMaterial.cachedSheetControl
    }
    return undefined
  }

  /**
   * 材质按钮（Button 已换成容器）的底色。材质在低档设备上几乎透明，
   * 手机上常见的这类按钮不能像 PC 侧栏折叠键那样一律置透明：
   * EXQUISITE 档用 exquisiteTint（默认全透明；白图标压在亮画面上的传深色薄染保对比），
   * GENTLE/SMOOTH 档与 <26 沿用原底色，材质只贡献按压形变。
   */
  static controlSurface(fallback: ResourceColor, exquisiteTint: ResourceColor = Color.Transparent): ResourceColor {
    return CloudMaterial.isExquisite ? exquisiteTint : fallback
  }

  /** 同 controlSurface：只有 EXQUISITE 档撤掉手写模糊，其余档保留原毛玻璃。 */
  static controlBlurStyle(fallback: BlurStyle): BlurStyle {
    return CloudMaterial.isExquisite ? BlurStyle.NONE : fallback
  }

  /** 同 controlBlurStyle，用于 backdropBlur 形式的手写模糊。 */
  static controlBackdropBlur(fallback: number): number {
    return CloudMaterial.isExquisite ? 0 : fallback
  }

  private static cachedDialog: SystemUiMaterial | undefined = undefined

  /**
   * 自绘内容的系统模态弹窗（openCustomDialog 的 systemMaterial 选项）：
   * 与系统弹窗同档 ULTRA_THICK。弹窗根容器底色走 cardBackground 分档让位。
   */
  static dialogMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedDialog === undefined) {
        CloudMaterial.cachedDialog = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THICK
        })
      }
      return CloudMaterial.cachedDialog
    }
    return undefined
  }

  private static cachedMenu: SystemUiMaterial | undefined = undefined

  /**
   * 自绘下拉/弹出菜单面板：厚材质，与系统菜单控件（应用级 ENABLE 默认 THICK）
   * 观感一致。菜单里全是文字，比浮动工具栏更需要模糊背景保证可读。
   */
  static menuMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedMenu === undefined) {
        CloudMaterial.cachedMenu = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        })
      }
      return CloudMaterial.cachedMenu
    }
    return undefined
  }


  /**
   * 材质接管后不再需要手写毛玻璃。只用于 systemMaterial 确实生效的组件
   * （Column / Row / Stack / Text —— Button 不支持材质，那些站点保留原模糊）。
   */
  static blurFallback(fallback: BlurStyle): BlurStyle {
    return CloudMaterial.supported ? BlurStyle.NONE : fallback
  }

  /** 同 blurFallback，用于 backdropBlur 形式的手写模糊。 */
  static backdropBlurFallback(fallback: number): number {
    return CloudMaterial.supported ? 0 : fallback
  }

  /**
   * 把本机的材质档位记进启动日志。效果被设备算力锁死，与系统设置无关：
   * 实测 Mate 60 Pro 即使把沉浸光感调到最强，globalLevel 仍是 1(GENTLE)，
   * 材质几乎不透；MateBook Pro 读到 0(EXQUISITE) 才是完整效果。
   * 界面「没变化」时先看这行再怀疑代码。
   */
  static logDiagnostics(): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo()
      AppLogger.info(TAG, `diag: state=${info.state} type=${info.type}` +
        ` globalLevel=${uiMaterial.getGlobalMaterialLevel()}` +
        ` immersiveSupported=${uiMaterial.isImmersiveMaterialSupported()}`)
    }
  }
}
