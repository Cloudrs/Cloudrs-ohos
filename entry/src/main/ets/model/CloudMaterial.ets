import { uiMaterial } from '@kit.ArkUI'
import { CloudThemeToken } from './CloudTheme'
import { deviceInfo } from '@kit.BasicServicesKit';
import AppLogger from '../utils/AppLogger'

const TAG = 'CloudMaterial'

/**
 * API 26 沉浸光感的统一入口。
 *
 * 本分支 compatibleSdkVersion 仍是 6.1.0(23)，一份代码要在两档 ROM 上跑：
 * 26+ 走官方沉浸式系统材质，23/24 回退到原有底色。版本分叉只在这个文件里做。
 *
 * **生效范围（官方「沉浸光感常见问题」）**：除弹窗/菜单/Popup/半模态、Slider/Toggle/Select 外，
 * 其他组件的沉浸光感（材质、交互形变、点光源）只在 Navigation/NavDestination 标题栏与
 * barPosition=End 的底部 TabBar 内生效，其它区域设置了也不生效（日志 "Material inactive: out of scope"）。
 * 所以本类只服务生效范围内的组件；内容区的浮层、浮动键、卡片一律不挂材质，改用通用属性
 * （底色 + backdropBlur / backgroundBlurStyle + 光边 + 投影），各设备通用。
 *
 * **档位**：材质效果由系统按设备算力档位与用户的系统光感设置自适应调整，官方明确
 * 「开发者无需为不同档位设备编写差异化代码」。此前按 getGlobalMaterialLevel 分档置透明的写法，
 * 实为把范围外失效误判成「低档材质太薄 / 高档自绘材质不显形」，已全部移除，别再加回来。
 *
 * 其它实测结论：
 * 1. deviceInfo.apiAvailable 虽标 @since 26.0.0，但在 API 23 ROM 上存在且返回 false，可安全用作门控；
 *    版本号必须字面量传入，编译器才认得出并消除兼容性告警；
 * 2. 顶部静态 import uiMaterial 在 API 23 上不崩，但材质对象必须惰性构造，写成模块级常量会加载即崩；
 * 3. systemMaterial 挂在 Button 上无效，按钮类控件用 Column/Stack 容器承载；
 * 4. 跨文件 export 的 AttributeModifier 不触发，兼容性告警用 @SuppressWarnings 屏蔽。
 * 另：背景色 / backgroundBlurStyle 画在材质层之上会盖住材质；systemMaterial 写在其它样式属性之后；
 * applyShadow 默认 true 时材质阴影覆盖自定义 shadow。
 */
export class CloudMaterial {
  private static cachedSupported: boolean | undefined = undefined
  private static cachedSheetMaterial: SystemUiMaterial | undefined = undefined
  private static cachedPanel: SystemUiMaterial | undefined = undefined
  private static cachedTitleControl: SystemUiMaterial | undefined = undefined
  private static cachedDialog: SystemUiMaterial | undefined = undefined

  /** 当前 ROM 是否支持沉浸光感。只在首次访问时算一次，并把结论记进启动日志。 */
  static get supported(): boolean {
    if (CloudMaterial.cachedSupported === undefined) {
      CloudMaterial.cachedSupported = deviceInfo.apiAvailable('26.0.0')
      AppLogger.info(TAG, CloudMaterial.cachedSupported ? '走 API 26 沉浸光感' : '回退底色')
    }
    return CloudMaterial.cachedSupported
  }

  /**
   * 生效范围内由材质接管背景的组件底色：半模态 / 弹窗的 backgroundColor 选项及其内容根容器、
   * 半模态与系统菜单里透出底板的行、标题栏内的控件（HDS backIconStyle / menuStyle、TitleControlButton）。
   * 26+ 一律置透明让系统材质透出（背景色画在材质层之上会盖住它），<26 用原底色。
   * 内容区的组件不要用它：那里材质不生效，置透明就是全透明。
   */
  static materialSurface(fallback: ResourceColor): ResourceColor {
    return CloudMaterial.supported ? Color.Transparent : fallback
  }

  /**
   * 半模态 / 自绘底部面板里的卡片底色。卡片是 sheet 的子组件、不在生效范围，自身挂材质无效：
   * 26+ 用半透明 surface 叠在 sheet 材质上出层次，<26 用调用点原本的实色。
   */
  static cardBackground(fallback: ResourceColor): ResourceColor {
    return CloudMaterial.supported ? CloudThemeToken.surfaceTranslucent : fallback
  }

  /** bindSheet 的系统材质（半模态在生效范围内）。低版本返回 undefined 即系统默认。 */
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

  /** 标题栏内的非按压面板（相册页标题旁的备份状态胶囊）：薄材质，不开形变。 */
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

  /**
   * 标题栏内的自绘方块键（TitleControlButton）：THIN 材质 + 交互形变 + 光感反馈。
   * 只有放在标题栏里才生效；底色配合 materialSurface 置透明。
   */
  static titleControlMaterial(): SystemUiMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (CloudMaterial.cachedTitleControl === undefined) {
        CloudMaterial.cachedTitleControl = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true,
          lightEffect: { color: undefined }
        })
      }
      return CloudMaterial.cachedTitleControl
    }
    return undefined
  }

  /**
   * 自绘内容的系统模态弹窗（openCustomDialog 的 systemMaterial 选项，在生效范围内）：
   * 与系统弹窗同档 ULTRA_THICK。
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

  /**
   * 把本机材质配置记进启动日志，排查「看不到材质」时先看这行：档位只读、由设备定义
   * （Mate 60 Pro=1 GENTLE、MateBook Pro / Pura X View=0 EXQUISITE），系统据此自适应，代码不分档。
   * 再看 hilog 有没有 "Material inactive: out of scope"——那说明组件不在生效范围。
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
