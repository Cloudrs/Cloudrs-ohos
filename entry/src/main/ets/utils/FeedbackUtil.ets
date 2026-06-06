import { UserInfo } from "../model/net/ApiTypes";

export interface FeedbackDiagnosticInput {
  appVersion: string;
  serverUrl: string;
  account: string;
  user?: UserInfo;
}

class FeedbackUtil {
  private readonly issueUrl: string = 'https://gitee.com/larriti/cloudrs-ohos/issues/new';
  private readonly feedbackEmail: string = 'wangxian@dreamflytech.com';

  buildDiagnosticMarkdown(input: FeedbackDiagnosticInput): string {
    const feedbackId = this.createFeedbackId();
    const user = input.user;
    let nickname = '未知';
    let rawAccount = input.account;
    let group = '未知';
    let uid = '未知';
    if (user) {
      if (user.nickname.length > 0) {
        nickname = user.nickname;
      }
      if (user.user_name.length > 0) {
        rawAccount = user.user_name;
      }
      if (user.group.name.length > 0) {
        group = user.group.name;
      }
      if (user.id.length > 0) {
        uid = user.id;
      }
    }
    const account = this.maskAccount(rawAccount);
    const server = this.maskServerUrl(input.serverUrl);
    const appVersion = input.appVersion.length > 0 ? input.appVersion : '未知';

    return [
      '# Cloudrs 问题反馈',
      '',
      '## 问题描述',
      '- 发生了什么：',
      '- 期望结果：',
      '- 是否可以稳定复现：',
      '',
      '## 复现步骤',
      '1. ',
      '2. ',
      '3. ',
      '',
      '## 诊断信息',
      `- 反馈编号：${feedbackId}`,
      `- 反馈时间：${new Date().toISOString()}`,
      `- App 版本：${appVersion}`,
      `- 当前站点：${server}`,
      `- 用户昵称：${nickname}`,
      `- 用户账号：${account}`,
      `- 用户 UID：${uid}`,
      `- 用户组：${group}`,
      '',
      '## 最近日志',
      '- 第一阶段暂未启用应用内日志导出，如问题与崩溃/上传/下载有关，请在反馈后补充操作时间点。',
      '',
      '## 隐私说明',
      '- 以上诊断信息已脱敏，不包含密码、Token、Cookie、刷新令牌和下载直链。'
    ].join('\n');
  }

  buildIssueUrl(input: FeedbackDiagnosticInput): string {
    return this.issueUrl;
  }

  buildMailUrl(input: FeedbackDiagnosticInput): string {
    const subject = '[Cloudrs 反馈] ' + this.createFeedbackId();
    return `mailto:${this.feedbackEmail}?subject=${encodeURIComponent(subject)}`;
  }

  private createFeedbackId(): string {
    const timePart = Date.now().toString(36).toUpperCase();
    const randomPart = Math.floor(Math.random() * 1679616).toString(36).toUpperCase().padStart(4, '0');
    return `CR-${timePart}-${randomPart}`;
  }

  private maskAccount(account: string): string {
    if (account.length === 0) {
      return '未知';
    }
    const atIndex = account.indexOf('@');
    if (atIndex > 0) {
      const name = account.substring(0, atIndex);
      const domain = account.substring(atIndex + 1);
      return `${this.maskText(name)}@${domain}`;
    }
    return this.maskText(account);
  }

  private maskText(value: string): string {
    if (value.length <= 2) {
      return value.substring(0, 1) + '*';
    }
    return value.substring(0, 1) + '***' + value.substring(value.length - 1);
  }

  private maskServerUrl(url: string): string {
    if (url.length === 0) {
      return '未知';
    }
    let normalized = url;
    const protocolIndex = normalized.indexOf('://');
    if (protocolIndex >= 0) {
      normalized = normalized.substring(protocolIndex + 3);
    }
    const slashIndex = normalized.indexOf('/');
    if (slashIndex >= 0) {
      normalized = normalized.substring(0, slashIndex);
    }
    return normalized;
  }
}

export default new FeedbackUtil();
