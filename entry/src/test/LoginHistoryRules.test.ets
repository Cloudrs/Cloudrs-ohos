import { describe, it, expect } from '@ohos/hypium'
import { LoginHistoryEntry, LoginHistoryRules } from '../main/ets/utils/LoginHistoryRules'

function entry(url: string, usernames: string[]): LoginHistoryEntry {
  const item = new LoginHistoryEntry()
  item.url = url
  item.usernames = usernames
  return item
}

function urlsOf(list: LoginHistoryEntry[]): string {
  return list.map((item: LoginHistoryEntry) => item.url).join(',')
}

export default function loginHistoryRulesTest() {
  describe('LoginHistoryRules', () => {
    it('normalize_trimsSpacesAndTrailingSlashes', 0, () => {
      expect(LoginHistoryRules.normalizeUrl('  https://pan.example.com//  ')).assertEqual('https://pan.example.com')
      expect(LoginHistoryRules.normalizeUrl('https://pan.example.com/cloud/')).assertEqual('https://pan.example.com/cloud')
      expect(LoginHistoryRules.normalizeUrl('')).assertEqual('')
    })
    it('hostOf_stripsScheme', 0, () => {
      expect(LoginHistoryRules.hostOf('https://pan.example.com')).assertEqual('pan.example.com')
      expect(LoginHistoryRules.hostOf('http://192.168.1.20:5212')).assertEqual('192.168.1.20:5212')
      expect(LoginHistoryRules.hostOf('HTTPS://Pan.example.com')).assertEqual('Pan.example.com')
      expect(LoginHistoryRules.hostOf('pan.example.com')).assertEqual('pan.example.com')
    })
    it('recordSite_movesToFrontAndKeepsUsernames', 0, () => {
      const list = [entry('https://a.com', []), entry('https://b.com', ['bob'])]
      const next = LoginHistoryRules.recordSite(list, 'https://b.com/')
      expect(urlsOf(next)).assertEqual('https://b.com,https://a.com')
      expect(next[0].usernames.join(',')).assertEqual('bob')
      // 不改动传入的数组
      expect(urlsOf(list)).assertEqual('https://a.com,https://b.com')
    })
    it('recordSite_sameUrlIgnoresCase', 0, () => {
      const next = LoginHistoryRules.recordSite([entry('https://pan.example.com', ['a'])], 'https://Pan.Example.com')
      expect(next.length).assertEqual(1)
      expect(next[0].url).assertEqual('https://Pan.Example.com')
      expect(next[0].usernames.join(',')).assertEqual('a')
    })
    it('recordSite_ignoresEmpty', 0, () => {
      expect(LoginHistoryRules.recordSite([], '   ').length).assertEqual(0)
    })
    it('recordSite_capsSites', 0, () => {
      let list: LoginHistoryEntry[] = []
      for (let i = 0; i < LoginHistoryRules.MAX_SITES + 3; i++) {
        list = LoginHistoryRules.recordSite(list, `https://s${i}.com`)
      }
      expect(list.length).assertEqual(LoginHistoryRules.MAX_SITES)
      expect(list[0].url).assertEqual(`https://s${LoginHistoryRules.MAX_SITES + 2}.com`)
    })
    it('recordLogin_addsUsernameToFront', 0, () => {
      const list = [entry('https://a.com', ['alice', 'bob'])]
      const next = LoginHistoryRules.recordLogin(list, 'https://a.com', 'Bob')
      expect(next[0].usernames.join(',')).assertEqual('Bob,alice')
    })
    it('recordLogin_createsSiteWhenMissing', 0, () => {
      const next = LoginHistoryRules.recordLogin([entry('https://a.com', [])], 'https://b.com', ' carol ')
      expect(urlsOf(next)).assertEqual('https://b.com,https://a.com')
      expect(next[0].usernames.join(',')).assertEqual('carol')
    })
    it('recordLogin_emptyUsernameOnlyRecordsSite', 0, () => {
      const next = LoginHistoryRules.recordLogin([], 'https://a.com', '')
      expect(next.length).assertEqual(1)
      expect(next[0].usernames.length).assertEqual(0)
    })
    it('recordLogin_capsUsernames', 0, () => {
      let list: LoginHistoryEntry[] = []
      for (let i = 0; i < LoginHistoryRules.MAX_USERNAMES + 2; i++) {
        list = LoginHistoryRules.recordLogin(list, 'https://a.com', `u${i}`)
      }
      expect(list[0].usernames.length).assertEqual(LoginHistoryRules.MAX_USERNAMES)
      expect(list[0].usernames[0]).assertEqual(`u${LoginHistoryRules.MAX_USERNAMES + 1}`)
    })
    it('remove_siteAndUsername', 0, () => {
      const list = [entry('https://a.com', ['alice', 'bob']), entry('https://b.com', [])]
      expect(urlsOf(LoginHistoryRules.removeSite(list, 'https://A.com/'))).assertEqual('https://b.com')
      const next = LoginHistoryRules.removeUsername(list, 'https://a.com', 'alice')
      expect(next[0].usernames.join(',')).assertEqual('bob')
      expect(list[0].usernames.join(',')).assertEqual('alice,bob')
    })
    it('isSameUrl_andUsername', 0, () => {
      expect(LoginHistoryRules.isSameUrl('https://A.com/', ' https://a.com')).assertTrue()
      expect(LoginHistoryRules.isSameUrl('http://a.com', 'https://a.com')).assertFalse()
      expect(LoginHistoryRules.isSameUsername('Demo@Cloudrs.cn ', 'demo@cloudrs.cn')).assertTrue()
      expect(LoginHistoryRules.isSameUsername('demo', 'demo2')).assertFalse()
    })
    it('findSite_normalizes', 0, () => {
      const list = [entry('https://a.com', ['alice'])]
      expect(LoginHistoryRules.findSite(list, 'https://A.com/')?.usernames[0]).assertEqual('alice')
      expect(LoginHistoryRules.findSite(list, 'http://a.com')).assertUndefined()
    })
    it('matchSites_emptyQueryReturnsAll', 0, () => {
      const list = [entry('https://a.com', []), entry('https://b.com', [])]
      expect(LoginHistoryRules.matchSites(list, '  ').length).assertEqual(2)
    })
    it('matchSites_containsIgnoringCase', 0, () => {
      const list = [entry('https://pan.example.com', []), entry('http://192.168.1.20:5212', []),
        entry('https://drive.team.org', [])]
      expect(urlsOf(LoginHistoryRules.matchSites(list, '192'))).assertEqual('http://192.168.1.20:5212')
      expect(urlsOf(LoginHistoryRules.matchSites(list, 'EXAMPLE'))).assertEqual('https://pan.example.com')
      expect(urlsOf(LoginHistoryRules.matchSites(list, 'https://drive'))).assertEqual('https://drive.team.org')
      expect(LoginHistoryRules.matchSites(list, 'nothing').length).assertEqual(0)
    })
    it('matchSites_exactMatchShowsAll', 0, () => {
      // 从账号步返回时网址框里就是某个站点本身，这时给全部候选方便换站点
      const list = [entry('https://a.com', []), entry('https://b.com', [])]
      expect(LoginHistoryRules.matchSites(list, 'b.com/').length).assertEqual(2)
    })
    it('matchUsernames_rules', 0, () => {
      const users = ['alice@example.com', 'bob@example.com']
      expect(LoginHistoryRules.matchUsernames(users, '').length).assertEqual(2)
      expect(LoginHistoryRules.matchUsernames(users, 'BOB').join(',')).assertEqual('bob@example.com')
      // 已填的就是其中一个：还有别的可换才弹
      expect(LoginHistoryRules.matchUsernames(users, 'alice@example.com').length).assertEqual(2)
      expect(LoginHistoryRules.matchUsernames(['alice'], 'alice').length).assertEqual(0)
      expect(LoginHistoryRules.matchUsernames([], '').length).assertEqual(0)
    })
    it('matchStart_findsHighlight', 0, () => {
      expect(LoginHistoryRules.matchStart('pan.example.com', 'EXA')).assertEqual(4)
      expect(LoginHistoryRules.matchStart('pan.example.com', '')).assertEqual(-1)
      expect(LoginHistoryRules.matchStart('pan.example.com', 'zzz')).assertEqual(-1)
    })
    it('parse_toleratesGarbage', 0, () => {
      expect(LoginHistoryRules.parse('').length).assertEqual(0)
      expect(LoginHistoryRules.parse('not json').length).assertEqual(0)
      expect(LoginHistoryRules.parse('{"url":"https://a.com"}').length).assertEqual(0)
      const list = LoginHistoryRules.parse(
        '[{"url":"https://a.com","usernames":["alice",3,""]},{"url":""},null,{"url":"https://b.com"}]')
      expect(urlsOf(list)).assertEqual('https://a.com,https://b.com')
      expect(list[0].usernames.join(',')).assertEqual('alice')
      expect(list[1].usernames.length).assertEqual(0)
    })
    it('parse_roundTrip', 0, () => {
      const list = LoginHistoryRules.recordLogin([], 'https://a.com', 'alice')
      expect(urlsOf(LoginHistoryRules.parse(JSON.stringify(list)))).assertEqual('https://a.com')
    })
  })
}
