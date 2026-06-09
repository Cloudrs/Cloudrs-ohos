import { relationalStore } from '@kit.ArkData';
import { DbUserInfo, UserInfo } from './net/ApiTypes';
import AppLogger from '../utils/AppLogger';

class UserDatabase {
  rdbStore?: relationalStore.RdbStore
  dbName: string = 'UserInfo.db'
  usersTable: string = 'users'

  async init(context: Context) {
    let config: relationalStore.StoreConfig = {
      name: this.dbName,
      securityLevel: relationalStore.SecurityLevel.S4,
    }

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config)
      console.info('UserDatabase', `数据库${this.dbName}初始化成功`)

      // 建表
      let sql = `CREATE TABLE IF NOT EXISTS ${this.usersTable} (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT NOT NULL,
                    username TEXT NOT NULL,
                    password TEXT NOT NULL,
                    cookie TEXT NOT NULL,
                    expires TEXT,
                    refresh_token TEXT DEFAULT '',
                    userinfo TEXT,
                    UNIQUE (url, username) ON CONFLICT REPLACE);`
      try {
        this.rdbStore.executeSync(sql)
      } catch (err) {
        AppLogger.error('UserDatabase', `创建用户表失败, 错误：${JSON.stringify(err)}`)
        return
      }
      // 迁移：为旧表添加 refresh_token 列（已存在则忽略）
      try {
        this.rdbStore.executeSync(`ALTER TABLE ${this.usersTable} ADD COLUMN refresh_token TEXT DEFAULT ''`)
      } catch (_) {}
      try {
        this.rdbStore.executeSync(`UPDATE ${this.usersTable} SET password = '' WHERE password != ''`)
      } catch (err) {
        AppLogger.error('UserDatabase', `清理历史密码失败, 错误：${JSON.stringify(err)}`)
      }
    } catch (e) {
      AppLogger.error('UserDatabase', `数据库${this.dbName}初始化失败, 错误：${e}`)
    }
  }

  insertUserInfo(dbUserInfo: DbUserInfo): number {
    if (!this.rdbStore) {
      AppLogger.error('UserDatabase', '插入数据失败，数据库未初始化')
      return -1
    }

    let id = -1
    try {
      id = this.rdbStore.insertSync(this.usersTable, {
        url: dbUserInfo.url,
        username: dbUserInfo.username,
        password: '',
        cookie: dbUserInfo.cookie,
        expires: dbUserInfo.expires,
        refresh_token: dbUserInfo.refresh_token ?? '',
        userinfo: JSON.stringify(dbUserInfo.userinfo)
      })
    } catch (err) {
      AppLogger.error('UserDatabase', `插入数据库失败，username:${dbUserInfo.username}, 错误：${JSON.stringify(err)}`)
      return -1
    }

    if (id < 0) {
      AppLogger.error('UserDatabase', `插入数据库失败，username:${dbUserInfo.username}`)
      return -1
    }

    return id
  }

  checkUserValid(username: string, url?: string): boolean {
    if (!this.rdbStore) {
      AppLogger.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return false
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)
    if (url && url.length > 0) {
      predicates.equalTo('url', url)
    }

    let result: relationalStore.ResultSet | undefined = undefined
    try {
      result = this.rdbStore.querySync(predicates)
      if (result.rowCount > 0) {
        return true
      }
      else {
        AppLogger.warn('UserDatabase', `数据库未查询到该用户${username}`)
      }
    } catch (err) {
      AppLogger.error('UserDatabase', `查询用户失败，username:${username}, 错误：${JSON.stringify(err)}`)
    } finally {
      this.closeResult(result)
    }

    return false
  }

  getUserInfo(username: string, url?: string): DbUserInfo|null {
    if (!this.rdbStore) {
      AppLogger.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return null
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)
    if (url && url.length > 0) {
      predicates.equalTo('url', url)
    }

    let result: relationalStore.ResultSet | undefined = undefined
    try {
      result = this.rdbStore.querySync(predicates, ['url', 'password', 'cookie', 'expires', 'refresh_token', 'userinfo'])
      if (result.goToFirstRow()) {
        console.info('UserDatabase', `数据库查询用户${username}成功，个数:${result.rowCount}`)

        let url = result.getString(result.getColumnIndex('url'))
        let password = result.getString(result.getColumnIndex('password'))
        let cookie = result.getString(result.getColumnIndex('cookie'))
        let expires = result.getString(result.getColumnIndex('expires'))
        let refresh_token = result.getString(result.getColumnIndex('refresh_token'))
        let userinfo = result.getString(result.getColumnIndex('userinfo'))
        let dbUserInfo: DbUserInfo = {
          url,
          username,
          password,
          cookie,
          expires,
          refresh_token,
          userinfo: this.parseUserInfo(userinfo)
        }
        return dbUserInfo
      }
      else {
        AppLogger.warn('UserDatabase', `数据库未查询到该用户${username}的cookie`)
      }
    } catch (err) {
      AppLogger.error('UserDatabase', `获取用户信息失败，username:${username}, 错误：${JSON.stringify(err)}`)
    } finally {
      this.closeResult(result)
    }

    return null
  }

  listUserInfo(): DbUserInfo[] {
    let users: DbUserInfo[] = []
    if (!this.rdbStore) {
      AppLogger.error('UserDatabase', '获取用户列表失败，数据库未初始化')
      return users
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    try {
      predicates.orderByDesc('id')
    } catch (_) {}

    let result: relationalStore.ResultSet | undefined = undefined
    try {
      result = this.rdbStore.querySync(predicates, [
        'url',
        'username',
        'password',
        'cookie',
        'expires',
        'refresh_token',
        'userinfo'
      ])
      if (!result.goToFirstRow()) {
        return users
      }

      do {
        let username = result.getString(result.getColumnIndex('username'))
        users.push({
          url: result.getString(result.getColumnIndex('url')),
          username,
          password: result.getString(result.getColumnIndex('password')),
          cookie: result.getString(result.getColumnIndex('cookie')),
          expires: result.getString(result.getColumnIndex('expires')),
          refresh_token: result.getString(result.getColumnIndex('refresh_token')),
          userinfo: this.parseUserInfo(result.getString(result.getColumnIndex('userinfo')))
        })
      } while (result.goToNextRow())
    } catch (err) {
      AppLogger.error('UserDatabase', `获取用户列表失败，错误：${JSON.stringify(err)}`)
    } finally {
      this.closeResult(result)
    }

    return users
  }

  deleteUserInfo(username: string, url?: string): void {
    if (!this.rdbStore) {
      AppLogger.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)
    if (url && url !== '') {
      predicates.equalTo('url', url)
    }

    let id = 0
    try {
      id = this.rdbStore.deleteSync(predicates)
    } catch (err) {
      AppLogger.error('UserDatabase', `数据库删除用户${username}失败，错误：${JSON.stringify(err)}`)
      return
    }
    if (id > 0) {
      console.info('UserDatabase', `数据库删除用户${username}成功，个数:${id}`)
    }
    else {
      AppLogger.warn('UserDatabase', `数据库未查询到该用户${username}`)
    }
  }

  private parseUserInfo(userinfo: string): UserInfo {
    if (!userinfo || userinfo.length === 0) {
      return this.createEmptyUserInfo()
    }
    try {
      return JSON.parse(userinfo) as UserInfo
    } catch (err) {
      AppLogger.error('UserDatabase', `解析用户信息失败，错误：${JSON.stringify(err)}`)
      return this.createEmptyUserInfo()
    }
  }

  private closeResult(result?: relationalStore.ResultSet): void {
    if (!result) {
      return
    }
    try {
      result.close()
    } catch (err) {
      AppLogger.error('UserDatabase', `关闭查询结果失败，错误：${JSON.stringify(err)}`)
    }
  }

  private createEmptyUserInfo(): UserInfo {
    return {
      id: '',
      user_name: '',
      nickname: '',
      status: 0,
      avatar: '',
      created_at: '',
      preferred_theme: '',
      anonymous: false,
      group: {
        id: '',
        name: '',
        allowShare: false,
        allowRemoteDownload: false,
        allowArchiveDownload: false,
        shareDownload: false,
        compress: false,
        webdav: false,
        sourceBatch: 0,
        advanceDelete: false,
        allowWebDAVProxy: false
      }
    }
  }
}

export default new UserDatabase();
