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

  /**
   * Cloudreve「上传会话已存在」（40054）。
   *
   * 建会话时服务端会插一条占位文件记录占住文件名，上传没走完就中断的话占位会留下，
   * 之后同名文件每次建会话都撞这个码，要等服务端 GC（V3 的 upload_session_timeout
   * 默认 24h）才自己好。和 40004 的区别很关键：40004 是撞上一个真实文件，
   * 40054 意味着同名的那个对象一定是占位——所以清掉它是安全的。
   */
  static isUploadSessionExisted(msg: string): boolean {
    const lower = (msg ?? '').toLowerCase();
    return lower.includes('40054') ||
      lower.includes('upload session existed') ||
      lower.includes('上传会话已存在');
  }

  /** Cloudreve V4 文件锁冲突（40073），常见于未结束的上传/备份会话。 */
  static isLockConflict(msg: string): boolean {
    const lower = (msg ?? '').toLowerCase();
    return lower.includes('40073') ||
      lower.includes('lock conflict') ||
      lower.includes('locked resource') ||
      lower.includes('文件被占用') ||
      lower.includes('文件锁冲突') ||
      lower.includes('资源被锁定');
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
