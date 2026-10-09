import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Constant from '../model/Constant';
import UserPreferences from '../model/UserPreferences';
import AppLogger from './AppLogger';

const TAG: string = 'HoldingHandUtil';
const ERR_NOT_SUPPORTED: number = 801;

/** 握持手映射到界面上的落点。 */
export enum GripSide {
  LEFT,
  RIGHT
}

/**
 * 智感握姿（motion 'holdingHandChanged'，API 20+）封装。
 * 全局只维持一个订阅：文件页、相册页各自按「可见 + 前台 + 开关」调 start/stop（同一时刻只有一个页签可见），
 * 只有明确识别出左/右手才回调；双手、未握持、未识别不回调，界面保持上一次的落点。
 * 仅「设置-系统」里有「智感握姿」开关的机型支持，其余机型订阅抛 801。
 * 每处 motion 调用都用 canIUse 字面量词法包住，syscap 检查才认（提前 return 的写法不认）。
 */
export class HoldingHandUtil {
  // undefined = 还没有结论；遇到 801 或缺 syscap 后固定为 false，之后不再尝试订阅
  private static supported: boolean | undefined = undefined;
  private static subscribed: boolean = false;
  private static onSide: ((side: GripSide) => void) | undefined = undefined;
  // 当前订阅期内最近一次识别结果；新页面接管已有订阅时系统不会再回调，靠它补发一次
  private static lastSide: GripSide | undefined = undefined;
  private static readonly listener = (status: motion.HoldingHandStatus): void => {
    AppLogger.debug(TAG, `holding hand status=${status}`);
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
        HoldingHandUtil.dispatch(GripSide.LEFT);
      } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
        HoldingHandUtil.dispatch(GripSide.RIGHT);
      }
    }
  };

  static isEnabled(): boolean {
    return (UserPreferences.getSync(Constant.USER_PREFERENCES, Constant.SMART_GRIP_ENABLED, true) as boolean) === true;
  }

  static setEnabled(enabled: boolean): void {
    UserPreferences.putSync(Constant.USER_PREFERENCES, Constant.SMART_GRIP_ENABLED, enabled);
    AppStorage.setOrCreate(Constant.SMART_GRIP_ENABLED, enabled);
  }

  /** 把持久化的开关镜像进 AppStorage，供文件页、相册页 @StorageProp 读取。 */
  static mirrorEnabled(): void {
    AppStorage.setOrCreate(Constant.SMART_GRIP_ENABLED, HoldingHandUtil.isEnabled());
  }

  /**
   * 设备是否支持智感握姿。首次调用时订阅一下再立即退订来探测，结论缓存；
   * 只有 801 算「不支持」，服务异常等其它错误可能是暂时的，不下结论、按支持处理。
   */
  static isSupported(): boolean {
    if (HoldingHandUtil.supported !== undefined) {
      return HoldingHandUtil.supported;
    }
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      const probe = (_status: motion.HoldingHandStatus): void => {};
      try {
        motion.on('holdingHandChanged', probe);
        motion.off('holdingHandChanged', probe);
        HoldingHandUtil.supported = true;
        return true;
      } catch (err) {
        return HoldingHandUtil.handleError('probe', err as BusinessError);
      }
    }
    HoldingHandUtil.supported = false;
    return false;
  }

  /** 开始订阅；已订阅时只替换回调。返回 false 表示设备不支持或订阅失败。 */
  static start(onSide: (side: GripSide) => void): boolean {
    HoldingHandUtil.onSide = onSide;
    if (HoldingHandUtil.subscribed) {
      // 页签切换时新页面可能先于旧页面退订就来接管，订阅没断、系统不会再回调，补发最近一次结果
      if (HoldingHandUtil.lastSide !== undefined) {
        onSide(HoldingHandUtil.lastSide);
      }
      return true;
    }
    if (HoldingHandUtil.supported === false) {
      return false;
    }
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      try {
        // 订阅成功后系统会立即回调一次当前握持状态
        motion.on('holdingHandChanged', HoldingHandUtil.listener);
        HoldingHandUtil.subscribed = true;
        HoldingHandUtil.supported = true;
        AppLogger.info(TAG, 'subscribed');
        return true;
      } catch (err) {
        HoldingHandUtil.handleError('subscribe', err as BusinessError);
        return false;
      }
    }
    HoldingHandUtil.supported = false;
    return false;
  }

  /**
   * 退订。传入 start 时的回调则只在它仍是当前回调时生效：HomePage 切换双布局、或在文件 / 相册页签间切换时，
   * 旧页面的退订可能晚于新页面的 start，不能把新订阅一并退掉。
   */
  static stop(onSide?: (side: GripSide) => void): void {
    if (onSide !== undefined && HoldingHandUtil.onSide !== onSide) {
      return;
    }
    HoldingHandUtil.onSide = undefined;
    if (!HoldingHandUtil.subscribed) {
      return;
    }
    HoldingHandUtil.subscribed = false;
    // 重新订阅时系统会立即回调当前状态，不再沿用旧结果
    HoldingHandUtil.lastSide = undefined;
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      try {
        motion.off('holdingHandChanged', HoldingHandUtil.listener);
        AppLogger.info(TAG, 'unsubscribed');
      } catch (err) {
        const error = err as BusinessError;
        AppLogger.warn(TAG, `unsubscribe failed: code=${error.code}, ${error.message}`);
      }
    }
  }

  private static dispatch(side: GripSide): void {
    HoldingHandUtil.lastSide = side;
    if (HoldingHandUtil.onSide) {
      HoldingHandUtil.onSide(side);
    }
  }

  /** 801 记为不支持并返回 false；其它错误只记日志，返回 true（不认定为不支持）。 */
  private static handleError(action: string, error: BusinessError): boolean {
    if (error.code === ERR_NOT_SUPPORTED) {
      HoldingHandUtil.supported = false;
      AppLogger.info(TAG, `${action}: holding hand detection not supported on this device`);
      return false;
    }
    AppLogger.warn(TAG, `${action} failed: code=${error.code}, ${error.message}`);
    return true;
  }
}
