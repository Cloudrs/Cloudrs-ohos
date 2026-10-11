import { describe, it, expect } from '@ohos/hypium'
import { ArchiveBannerJob, ArchiveRules, ArchiveSourceName } from '../main/ets/utils/ArchiveRules'
import { UserTask } from '../main/ets/model/net/ApiTypes'

function task(kind: string, status: string, createDate: string, id: string = ''): UserTask {
  return {
    id: id, kind: kind, status: status, create_date: createDate, src: '', src_count: 0, src_list: [],
    dst: '', stage: '', transferred: 0, failed: 0, duration: 0, node: '', error: ''
  }
}

function source(name: string, isDir: boolean): ArchiveSourceName {
  return { name: name, isDir: isDir }
}

function bannerJob(kind: string, label: string, status: string): ArchiveBannerJob {
  return { kind: kind, label: label, status: status }
}

export default function archiveRulesTest() {
  describe('ArchiveRules', () => {
    it('canExtract_caseRules', 0, () => {
      expect(ArchiveRules.canExtract('a.ZIP', true)).assertTrue()
      expect(ArchiveRules.canExtract('a.ZIP', false)).assertFalse()
      expect(ArchiveRules.canExtract('a.zip', false)).assertTrue()
      expect(ArchiveRules.canExtract('a.7z', true)).assertTrue()
      expect(ArchiveRules.canExtract('a.7z', false)).assertFalse()
      expect(ArchiveRules.canExtract('a.tar.gz', false)).assertTrue()
      expect(ArchiveRules.canExtract('a.bz2', true)).assertTrue()
      expect(ArchiveRules.canExtract('a.bz2', false)).assertFalse()
      expect(ArchiveRules.canExtract('notes.txt', true)).assertFalse()
      expect(ArchiveRules.canExtract('zip', true)).assertFalse()
    })
    it('options_byFormat', 0, () => {
      expect(ArchiveRules.needsEncoding('a.zip', true)).assertTrue()
      expect(ArchiveRules.needsEncoding('a.rar', true)).assertFalse()
      expect(ArchiveRules.needsEncoding('a.zip', false)).assertTrue()
      expect(ArchiveRules.acceptsPassword('a.7z', true)).assertTrue()
      expect(ArchiveRules.acceptsPassword('a.rar', true)).assertTrue()
      expect(ArchiveRules.acceptsPassword('a.zip', true)).assertFalse()
      expect(ArchiveRules.acceptsPassword('a.rar', false)).assertFalse()
    })
    it('defaultName_single', 0, () => {
      expect(ArchiveRules.defaultArchiveName([source('report.docx', false)], '/docs')).assertEqual('report.zip')
      expect(ArchiveRules.defaultArchiveName([source('photos', true)], '/')).assertEqual('photos.zip')
      expect(ArchiveRules.defaultArchiveName([source('.env', false)], '/')).assertEqual('.env.zip')
    })
    it('defaultName_multiple', 0, () => {
      const two = [source('a.txt', false), source('b', true)]
      expect(ArchiveRules.defaultArchiveName(two, '/work/2026')).assertEqual('2026.zip')
      expect(ArchiveRules.defaultArchiveName(two, '/')).assertEqual('archive.zip')
      expect(ArchiveRules.defaultArchiveName(two, '')).assertEqual('archive.zip')
    })
    it('nameError', 0, () => {
      expect(ArchiveRules.archiveNameError('')).assertEqual('请输入文件名')
      expect(ArchiveRules.archiveNameError('   ')).assertEqual('请输入文件名')
      expect(ArchiveRules.archiveNameError('a/b.zip')).assertEqual('文件名不能包含 / 或 \\')
      expect(ArchiveRules.archiveNameError('a'.repeat(256))).assertEqual('文件名最多 255 个字符')
      expect(ArchiveRules.archiveNameError('报告.zip')).assertEqual('')
    })
    it('joinPath_root', 0, () => {
      expect(ArchiveRules.joinPath('/', 'a.zip')).assertEqual('/a.zip')
      expect(ArchiveRules.joinPath('/docs', 'a.zip')).assertEqual('/docs/a.zip')
      expect(ArchiveRules.joinPath('/docs/', 'a.zip')).assertEqual('/docs/a.zip')
    })
    it('errorText_codes', 0, () => {
      expect(ArchiveRules.isNotAllowed('API error: Group not allowed to compress files (code: 40007)')).assertTrue()
      expect(ArchiveRules.errorText('API error:  (code: 40007)')).assertEqual('当前账号没有压缩权限')
      expect(ArchiveRules.errorText('API error:  (code: 40049)')).assertEqual('文件超过用户组允许的大小')
      expect(ArchiveRules.errorText('API error:  (code: 40051)')).assertEqual('空间不足')
      expect(ArchiveRules.errorText('API error:  (code: 40056)')).assertEqual('不支持该格式的压缩包')
      expect(ArchiveRules.errorText('API error:  (code: 40052)')).assertEqual('文件名不合法')
      expect(ArchiveRules.errorText('API error: File a.zip already exist (code: 40001)')).assertEqual('已存在同名文件')
      expect(ArchiveRules.errorText('boom')).assertEqual('boom')
    })
    it('findV4_byId', 0, () => {
      const tasks = [task('compress', 'processing', '2026-10-11T10:00:00+08:00', 'a'),
        task('compress', 'completed', '2026-10-11T10:00:01+08:00', 'b')]
      expect(ArchiveRules.findV4Task(tasks, 'b')?.status).assertEqual('completed')
      expect(ArchiveRules.findV4Task(tasks, 'z')).assertUndefined()
    })
    it('matchV3_claimsInOrder', 0, () => {
      const submitted = Date.parse('2026-10-11T10:00:00+08:00')
      const tasks = [
        task('compress', 'processing', '2026-10-11T10:00:05+08:00'),
        task('compress', 'completed', '2026-10-11T10:00:02+08:00'),
        task('extract', 'completed', '2026-10-11T10:00:03+08:00'),
        task('compress', 'completed', '2026-10-11T09:50:00+08:00')
      ]
      const first = ArchiveRules.matchV3Task(tasks, 'compress', submitted, [])
      expect(first?.create_date).assertEqual('2026-10-11T10:00:02+08:00')
      const claimed = [ArchiveRules.v3TaskKey(first as UserTask)]
      const second = ArchiveRules.matchV3Task(tasks, 'compress', submitted, claimed)
      expect(second?.create_date).assertEqual('2026-10-11T10:00:05+08:00')
      claimed.push(ArchiveRules.v3TaskKey(second as UserTask))
      expect(ArchiveRules.matchV3Task(tasks, 'compress', submitted, claimed)).assertUndefined()
    })
    it('matchV3_ignoresTasksBeforeSubmit', 0, () => {
      // 上一个压缩 1 分钟前已完成：新提交不能认领它（否则还没压完就报「完成」）
      const submitted = Date.parse('2026-10-11T10:01:00+08:00')
      const previous = [task('compress', 'completed', '2026-10-11T10:00:00+08:00')]
      expect(ArchiveRules.matchV3Task(previous, 'compress', submitted, [])).assertUndefined()
      // 服务器时钟比手机慢几秒仍能认领
      const skewed = [task('compress', 'processing', '2026-10-11T10:00:57+08:00')]
      expect(ArchiveRules.matchV3Task(skewed, 'compress', submitted, [])?.create_date)
        .assertEqual('2026-10-11T10:00:57+08:00')
    })
    it('scope_sameAccountOnly', 0, () => {
      expect(ArchiveRules.sameScope('https://a|u', 'https://a|u')).assertTrue()
      expect(ArchiveRules.sameScope('https://a|u', 'https://b|u')).assertFalse()
      expect(ArchiveRules.sameScope('https://a|u', '')).assertFalse()
      expect(ArchiveRules.sameScope('', '')).assertFalse()
    })
    it('refreshFolder_byKind', 0, () => {
      expect(ArchiveRules.shouldRefreshFolder('compress', '/', '/')).assertTrue()
      expect(ArchiveRules.shouldRefreshFolder('compress', '', '/')).assertTrue()
      expect(ArchiveRules.shouldRefreshFolder('compress', '/', '/docs')).assertFalse()
      expect(ArchiveRules.shouldRefreshFolder('compress', '/notes/', '/notes')).assertTrue()
      expect(ArchiveRules.shouldRefreshFolder('compress', '/notes', '/notes/joplin')).assertFalse()
      // 解压可能并进已有的子文件夹，停在子孙文件夹里也要刷
      expect(ArchiveRules.shouldRefreshFolder('extract', '/notes', '/notes/joplin')).assertTrue()
      expect(ArchiveRules.shouldRefreshFolder('extract', '/notes', '/notesX')).assertFalse()
      expect(ArchiveRules.shouldRefreshFolder('extract', '/', '/docs')).assertTrue()
    })
    it('banner_states', 0, () => {
      const none: ArchiveBannerJob[] = []
      expect(ArchiveRules.bannerFor(none, none).mode).assertEqual('hidden')
      // 点了解压、服务器还没回复
      const sending = ArchiveRules.bannerFor([bannerJob('extract', 'V.zip', '')], none)
      expect(sending.mode).assertEqual('submitting')
      expect(sending.text).assertEqual('正在提交解压 V.zip…')
      // 服务器已接收、还在排队
      const queued = ArchiveRules.bannerFor(none, [bannerJob('extract', 'V.zip', 'queued')])
      expect(queued.mode).assertEqual('queued')
      expect(queued.text).assertEqual('排队中 · 解压 V.zip')
      // v4 任务开始前会挂起等待（实测 queued → suspending 约 20 秒 → completed），同样是灰色等待态
      const waiting = ArchiveRules.bannerFor(none, [bannerJob('compress', 'X.zip', 'suspending')])
      expect(waiting.mode).assertEqual('queued')
      expect(waiting.text).assertEqual('等待中 · 压缩 X.zip')
      // 还没查到状态 / 已开始处理
      expect(ArchiveRules.bannerFor(none, [bannerJob('compress', 'a.zip', '')]).text).assertEqual('正在压缩 a.zip')
      const running = ArchiveRules.bannerFor(none, [bannerJob('compress', 'a.zip', 'processing')])
      expect(running.mode).assertEqual('running')
      expect(running.text).assertEqual('正在压缩 a.zip')
      // 提交中和跟踪中的一起算
      const many = ArchiveRules.bannerFor([bannerJob('extract', 'b.zip', '')], [bannerJob('compress', 'a.zip', 'queued')])
      expect(many.mode).assertEqual('running')
      expect(many.text).assertEqual('2 个任务进行中')
    })
    it('finished_statuses', 0, () => {
      expect(ArchiveRules.isTaskFinished('completed')).assertTrue()
      expect(ArchiveRules.isTaskFinished('error')).assertTrue()
      expect(ArchiveRules.isTaskFinished('canceled')).assertTrue()
      expect(ArchiveRules.isTaskFinished('processing')).assertFalse()
      expect(ArchiveRules.isTaskFinished('queued')).assertFalse()
    })
  })
}
