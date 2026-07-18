import { NetworkStateUtil } from './NetworkStateUtil';

/** 无网络/连接失败时给用户看的统一文案。 */
export const NETWORK_ERROR_MESSAGE = '网络异常，请检查网络';

/**
 * API 层错误消息的统一识别与翻译。
 * 原始错误来自 Rust 侧 reqwest（英文连接类错误）或 Cloudreve 服务端（带业务码的消息），
 * 各页面 onFailure 拿到的是这里翻译后的结果。
 */
export class ApiErrorUtil {
  /**
   * Cloudreve「对象已存在」（40004，overwrite=false 撞到云端同名对象）。
   * 新建/重命名/上传会话创建撞同名时服务端返回此码。
   */
  static isObjectExisted(msg: string): boolean {
    const lower = (msg ?? '').toLowerCase();
    return lower.includes('40004') || lower.includes('object existed') || lower.includes('对象已存在');
  }

  /** 连接类错误：DNS 解析失败、连不上、超时、发送请求失败等。 */
  static isNetworkError(msg: string): boolean {
    if (!NetworkStateUtil.hasNetwork()) {
      return true;
    }
    const lower = (msg ?? '').toLowerCase();
    return lower.includes('error sending request') ||
      lower.includes('dns error') ||
      lower.includes('connection refused') ||
      lower.includes('connection reset') ||
      lower.includes('connect timeout') ||
      lower.includes('timed out') ||
      lower.includes('network unreachable') ||
      lower.includes('failed to lookup address');
  }

  /** 网络类错误替换为统一中文文案，其余原样返回。 */
  static translate(msg: string): string {
    return ApiErrorUtil.isNetworkError(msg) ? NETWORK_ERROR_MESSAGE : msg;
  }

  /** 判断消息是否为网络类错误（含 translate 之后的统一文案）。 */
  static isNetworkMessage(msg: string): boolean {
    return msg === NETWORK_ERROR_MESSAGE || ApiErrorUtil.isNetworkError(msg);
  }
}
