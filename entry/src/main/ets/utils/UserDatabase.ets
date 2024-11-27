import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbUserInfo } from '../types/ApiTypes';

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
                    userinfo TEXT,
                    UNIQUE (url, username) ON CONFLICT FAIL);`
      this.rdbStore.executeSync(sql)
    } catch (e) {
      console.error('UserDatabase', `数据库${this.dbName}初始化失败, 错误：${e}`)
    }
  }

  insertUserInfo(dbUserInfo: DbUserInfo): number {
    if (!this.rdbStore) {
      console.error('UserDatabase', '插入数据失败，数据库未初始化')
      return -1
    }

    let id = this.rdbStore.insertSync(this.usersTable, {
      url: dbUserInfo.url,
      username: dbUserInfo.username,
      password: dbUserInfo.password,
      cookie: dbUserInfo.cookie,
      expires: dbUserInfo.expires,
      userinfo: JSON.stringify(dbUserInfo.userinfo)
    })

    if (id < 0) {
      console.error('UserDatabase', `插入数据库成功，username:${dbUserInfo.username}`)
      return -1
    }

    return id
  }

  checkUserValid(username: string): boolean {
    if (!this.rdbStore) {
      console.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return false
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)

    let result = this.rdbStore.querySync(predicates)
    if (result.rowCount > 0) {
      return true
    }
    else {
      console.warn('UserDatabase', `数据库未查询到该用户${username}`)
    }

    return false
  }

  getUserInfo(username: string): DbUserInfo|null {
    if (!this.rdbStore) {
      console.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return null
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)

    let result = this.rdbStore.querySync(predicates, ['url', 'password', 'cookie', 'expires', 'userinfo'])
    if (result.goToFirstRow()) {
      console.info('UserDatabase', `数据库查询用户${username}成功，个数:${result.rowCount}`)

      let url = result.getString(result.getColumnIndex('url'))
      let password = result.getString(result.getColumnIndex('password'))
      let cookie = result.getString(result.getColumnIndex('cookie'))
      let expires = result.getString(result.getColumnIndex('expires'))
      let userinfo = result.getString(result.getColumnIndex('userinfo'))
      let dbUserInfo: DbUserInfo = { url, username, password, cookie, expires, userinfo: JSON.parse(userinfo)}
      return dbUserInfo
    }
    else {
      console.warn('UserDatabase', `数据库未查询到该用户${username}的cookie`)
    }

    return null
  }

  deleteUserInfo(username: string, url?: string): void {
    if (!this.rdbStore) {
      console.error('UserDatabase', '获取cookie失败，数据库未初始化')
      return
    }

    let predicates = new relationalStore.RdbPredicates(this.usersTable)
    predicates.equalTo('username', username)
    if (url && url !== '') {
      predicates.equalTo('url', url)
    }

    let id = this.rdbStore.deleteSync(predicates)
    if (id > 0) {
      console.info('UserDatabase', `数据库删除用户${username}成功，个数:${id}`)
    }
    else {
      console.warn('UserDatabase', `数据库未查询到该用户${username}`)
    }
  }
}

const userDatabase = new UserDatabase();
export default userDatabase as UserDatabase;