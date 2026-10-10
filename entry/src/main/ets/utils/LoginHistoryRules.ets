const SCHEME_PATTERN: RegExp = new RegExp('^https?://', 'i')
const NOT_FOUND: number = -1

/**
 * 一个站点的登录历史：网址（含协议）和在这里登录成功过的用户名，最近用的排在前面。
 * 只用来给登录页做候选，不记密码与 token。
 */
export class LoginHistoryEntry {
  url: string = ''
  usernames: string[] = []
}

function sameText(a: string, b: string): boolean {
  return a.toLowerCase() === b.toLowerCase()
}

function copyEntry(source: LoginHistoryEntry): LoginHistoryEntry {
  const copy = new LoginHistoryEntry()
  copy.url = source.url
  copy.usernames = source.usernames.slice()
  return copy
}

/**
 * 输入与某个候选完全一致时给出全部（从下一步返回、想换一个时用得上）；
 * 否则按不区分大小写的包含关系过滤。
 */
function matchByContains<T>(list: T[], keyOf: (item: T) => string, query: string): T[] {
  const key = query.toLowerCase()
  if (key.length === 0 || list.some((item: T) => keyOf(item).toLowerCase() === key)) {
    return list.slice()
  }
  return list.filter((item: T) => keyOf(item).toLowerCase().includes(key))
}

/**
 * 登录页历史候选的纯规则：不碰 UI、不碰存储，便于本地单测。
 * 所有方法都返回新数组，不改动传入的列表。
 */
export class LoginHistoryRules {
  static readonly MAX_SITES: number = 10
  static readonly MAX_USERNAMES: number = 5

  /** 去掉首尾空白和末尾斜杠，作为站点的唯一标识 */
  static normalizeUrl(url: string): string {
    let result = url.trim()
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1)
    }
    return result
  }

  /** 去掉协议头：候选里展示和匹配都只看这部分，协议另由输入框左侧的 http/https 决定 */
  static hostOf(url: string): string {
    return url.replace(SCHEME_PATTERN, '')
  }

  /** 两个网址是否指同一站点：忽略首尾空白、末尾斜杠和大小写，协议不同算不同站点 */
  static isSameUrl(a: string, b: string): boolean {
    return sameText(LoginHistoryRules.normalizeUrl(a), LoginHistoryRules.normalizeUrl(b))
  }

  /** 用户名比较不区分大小写，与历史去重的规则一致 */
  static isSameUsername(a: string, b: string): boolean {
    return sameText(a.trim(), b.trim())
  }

  static findSite(list: LoginHistoryEntry[], url: string): LoginHistoryEntry | undefined {
    const target = LoginHistoryRules.normalizeUrl(url)
    return list.find((item: LoginHistoryEntry) => sameText(item.url, target))
  }

  /** 站点校验通过：挪到最前（没有就新建），已记的用户名保留 */
  static recordSite(list: LoginHistoryEntry[], url: string): LoginHistoryEntry[] {
    return LoginHistoryRules.recordLogin(list, url, '')
  }

  /** 登录成功：站点挪到最前，用户名放到该站点最前；用户名为空时等同 recordSite */
  static recordLogin(list: LoginHistoryEntry[], url: string, username: string): LoginHistoryEntry[] {
    const target = LoginHistoryRules.normalizeUrl(url)
    if (target.length === 0) {
      return list.slice()
    }
    const existing = LoginHistoryRules.findSite(list, target)
    const site = new LoginHistoryEntry()
    // 用最新一次的写法，大小写不同也算同一个站点
    site.url = target
    site.usernames = existing ? existing.usernames.slice() : []
    const name = username.trim()
    if (name.length > 0) {
      site.usernames = [name, ...site.usernames.filter((item: string) => !sameText(item, name))]
        .slice(0, LoginHistoryRules.MAX_USERNAMES)
    }
    const others = list.filter((item: LoginHistoryEntry) => !sameText(item.url, target)).map(copyEntry)
    return [site, ...others].slice(0, LoginHistoryRules.MAX_SITES)
  }

  static removeSite(list: LoginHistoryEntry[], url: string): LoginHistoryEntry[] {
    const target = LoginHistoryRules.normalizeUrl(url)
    return list.filter((item: LoginHistoryEntry) => !sameText(item.url, target)).map(copyEntry)
  }

  static removeUsername(list: LoginHistoryEntry[], url: string, username: string): LoginHistoryEntry[] {
    const target = LoginHistoryRules.normalizeUrl(url)
    return list.map((item: LoginHistoryEntry) => {
      const copy = copyEntry(item)
      if (sameText(copy.url, target)) {
        copy.usernames = copy.usernames.filter((name: string) => !sameText(name, username))
      }
      return copy
    })
  }

  /** 网址框的候选：query 可以带协议头、末尾斜杠，匹配时一并忽略 */
  static matchSites(list: LoginHistoryEntry[], query: string): LoginHistoryEntry[] {
    const key = LoginHistoryRules.hostOf(LoginHistoryRules.normalizeUrl(query))
    return matchByContains(list, (item: LoginHistoryEntry) => LoginHistoryRules.hostOf(item.url), key)
  }

  /** 用户名框的候选：已填的就是唯一那一个时没有可换的，返回空 */
  static matchUsernames(usernames: string[], query: string): string[] {
    const key = query.trim()
    const matched = matchByContains(usernames, (item: string) => item, key)
    if (matched.length === 1 && sameText(matched[0], key)) {
      return []
    }
    return matched
  }

  /** 高亮起点；query 为空或不包含时返回 -1 */
  static matchStart(text: string, query: string): number {
    if (query.length === 0) {
      return NOT_FOUND
    }
    return text.toLowerCase().indexOf(query.toLowerCase())
  }

  /** 读盘容错：手改过或旧版本残留的脏数据在这里挡掉 */
  static parse(raw: string): LoginHistoryEntry[] {
    if (!raw || raw.length === 0) {
      return []
    }
    let parsed: Object
    try {
      parsed = JSON.parse(raw) as Object
    } catch (_) {
      return []
    }
    if (!Array.isArray(parsed)) {
      return []
    }
    const result: LoginHistoryEntry[] = []
    for (const value of parsed as Object[]) {
      if (value === null || value === undefined) {
        continue
      }
      const item = value as LoginHistoryEntry
      if (typeof item.url !== 'string' || item.url.length === 0) {
        continue
      }
      const entry = new LoginHistoryEntry()
      entry.url = item.url
      if (Array.isArray(item.usernames)) {
        entry.usernames = (item.usernames as Object[])
          .filter((name: Object) => typeof name === 'string' && (name as string).length > 0)
          .map((name: Object) => name as string)
          .slice(0, LoginHistoryRules.MAX_USERNAMES)
      }
      result.push(entry)
      if (result.length >= LoginHistoryRules.MAX_SITES) {
        break
      }
    }
    return result
  }
}
