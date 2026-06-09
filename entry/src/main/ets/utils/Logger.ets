/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import AppLogger from './AppLogger';

const LOGGER_PREFIX: string = 'Cloudrs';

class Logger {
  private domain: number;
  private prefix: string;

  // format Indicates the log format string.
  private format: string = '%{public}s, %{public}s';

  /**
   * constructor.
   *
   * @param prefix Identifies the log tag.
   * @param domain Indicates the service domain, which is a hexadecimal integer ranging from 0x0 to 0xFFFFF
   * @param args Indicates the log parameters.
   */
  constructor(prefix: string = '', domain: number = 0xFF00) {
    this.prefix = prefix;
    this.domain = domain;
  }

  debug(...args: string[]): void {
    hilog.debug(this.domain, this.prefix, this.format, args);
    // 不向 AppLogger 转发 debug，避免反馈日志被海量 trace 淹没
  }

  info(...args: string[]): void {
    hilog.info(this.domain, this.prefix, this.format, args);
    // 不向 AppLogger 转发 info，关键事件请显式调用 AppLogger.info
  }

  warn(...args: string[]): void {
    hilog.warn(this.domain, this.prefix, this.format, args);
    AppLogger.warn(this.pickTag(args), this.pickMessage(args));
  }

  error(...args: string[]): void {
    hilog.error(this.domain, this.prefix, this.format, args);
    AppLogger.error(this.pickTag(args), this.pickMessage(args));
  }

  private pickTag(args: string[]): string {
    return args.length > 0 ? args[0] : this.prefix;
  }

  private pickMessage(args: string[]): string {
    if (args.length <= 1) {
      return args.length === 0 ? '' : args[0];
    }
    return args.slice(1).join(' ');
  }
}

export default new Logger(LOGGER_PREFIX, 0xFF02);