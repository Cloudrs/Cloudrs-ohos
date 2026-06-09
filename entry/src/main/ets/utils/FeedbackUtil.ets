import { UserInfo } from "../model/net/ApiTypes";

export interface FeedbackDiagnosticInput {
  appVersion: string;
  serverUrl: string;
  account: string;
  user?: UserInfo;
  recentLogs?: string;
  logFilePath?: string;
}

const MAX_INLINE_LOG_CHARS: number = 8000;

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
      nickname = this.pickUserText(() => user.nickname, nickname);
      rawAccount = this.pickUserText(() => user.user_name, rawAccount);
      group = this.pickUserText(() => user.group.name, group);
      uid = this.pickUserText(() => user.id, uid);
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
      ...this.buildLogSection(input),
      '',
      '## 隐私说明',
      '- 以上诊断信息已脱敏，不包含密码、Token、Cookie、刷新令牌和下载直链。'
    ].join('\n');
  }

  private buildLogSection(input: FeedbackDiagnosticInput): string[] {
    const lines: string[] = [];
    if (input.logFilePath && input.logFilePath.length > 0) {
      lines.push(`- 本机日志文件：${input.logFilePath}`);
    }
    const logs = input.recentLogs ?? '';
    if (logs.length === 0) {
      lines.push('- 暂无应用内日志（可能首次启动或刚清空）。如问题与崩溃/上传/下载有关，请补充操作时间点。');
      return lines;
    }
    const trimmed = logs.length > MAX_INLINE_LOG_CHARS
      ? `... (前段省略) ...\n${logs.substring(logs.length - MAX_INLINE_LOG_CHARS)}`
      : logs;
    lines.push('```');
    lines.push(trimmed);
    lines.push('```');
    return lines;
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

  private pickUserText(getter: () => string, fallback: string): string {
    try {
      const value = getter();
      if (value.length > 0) {
        return value;
      }
    } catch (err) {
    }
    return fallback;
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
