import { relationalStore } from '@kit.ArkData';
import AppLogger from '../utils/AppLogger';
import { FileModelState } from './FileModel';
import { ObjectInfo } from './net/ApiTypes';

const TAG = 'TransferDatabase';

export interface DownloadRecord {
  id: string
  item: ObjectInfo
  path: string
  url: string
  tid: string
  trans: number
  total: number
  state: FileModelState
  createdAt: number
}

export interface UploadRecord {
  id: string
  uri: string
  remotePath: string
  fileName: string
  overwrite: boolean
  sessionId: string
  chunkSize: number
  uploadUrls: string[]
  credential: string
  storagePolicyType: string
  storagePolicyRelay: boolean
  sessionExpiresAt: number
  total: number
  offset: number
  chunkIndex: number
  cachePath: string
  state: FileModelState
  createdAt: number
}

class TransferDatabase {
  rdbStore?: relationalStore.RdbStore
  dbName: string = 'Transfer.db'
  downloadTable: string = 'download_tasks'
  uploadTable: string = 'upload_tasks'

  async init(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: this.dbName,
      securityLevel: relationalStore.SecurityLevel.S2
    }

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config)
      AppLogger.info(TAG, `db ${this.dbName} ready`)

      const downloadSql = `CREATE TABLE IF NOT EXISTS ${this.downloadTable} (
        id TEXT PRIMARY KEY,
        item_json TEXT NOT NULL,
        path TEXT NOT NULL,
        url TEXT NOT NULL,
        tid TEXT NOT NULL,
        trans INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        state INTEGER NOT NULL,
        created_at INTEGER NOT NULL);`
      this.rdbStore.executeSync(downloadSql)

      const uploadSql = `CREATE TABLE IF NOT EXISTS ${this.uploadTable} (
        id TEXT PRIMARY KEY,
        uri TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        overwrite INTEGER NOT NULL DEFAULT 0,
        session_id TEXT NOT NULL DEFAULT '',
        chunk_size INTEGER NOT NULL DEFAULT 0,
        upload_urls_json TEXT NOT NULL DEFAULT '[]',
        credential TEXT NOT NULL DEFAULT '',
        storage_policy_type TEXT NOT NULL DEFAULT '',
        storage_policy_relay INTEGER NOT NULL DEFAULT 0,
        session_expires_at INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        offset INTEGER NOT NULL DEFAULT 0,
        chunk_index INTEGER NOT NULL DEFAULT 0,
        cache_path TEXT NOT NULL DEFAULT '',
        state INTEGER NOT NULL,
        created_at INTEGER NOT NULL);`
      this.rdbStore.executeSync(uploadSql)
    } catch (err) {
      AppLogger.error(TAG, `db init failed: ${JSON.stringify(err)}`)
    }
  }

  // -------- downloads --------

  upsertDownload(record: DownloadRecord): void {
    if (!this.rdbStore) return
    try {
      this.rdbStore.insertSync(this.downloadTable, {
        id: record.id,
        item_json: JSON.stringify(record.item),
        path: record.path,
        url: record.url,
        tid: record.tid,
        trans: record.trans,
        total: record.total,
        state: record.state,
        created_at: record.createdAt
      }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
    } catch (err) {
      AppLogger.error(TAG, `upsertDownload failed: ${JSON.stringify(err)}`)
    }
  }

  updateDownloadProgress(id: string, trans: number, state: FileModelState): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.downloadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.updateSync({ trans, state }, predicates)
    } catch (err) {
      AppLogger.error(TAG, `updateDownloadProgress failed: ${JSON.stringify(err)}`)
    }
  }

  updateDownloadTid(id: string, tid: string): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.downloadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.updateSync({ tid }, predicates)
    } catch (err) {
      AppLogger.error(TAG, `updateDownloadTid failed: ${JSON.stringify(err)}`)
    }
  }

  resetAllDownloadsToPaused(): void {
    if (!this.rdbStore) return
    try {
      this.rdbStore.executeSync(
        `UPDATE ${this.downloadTable} SET state = ? WHERE state NOT IN (?, ?)`,
        [FileModelState.PAUSED, FileModelState.COMPLETED, FileModelState.FAILED]
      )
    } catch (err) {
      AppLogger.error(TAG, `resetAllDownloadsToPaused failed: ${JSON.stringify(err)}`)
    }
  }

  resetAllUploadsToPaused(): void {
    if (!this.rdbStore) return
    try {
      this.rdbStore.executeSync(
        `UPDATE ${this.uploadTable} SET state = ? WHERE state NOT IN (?, ?)`,
        [FileModelState.PAUSED, FileModelState.COMPLETED, FileModelState.FAILED]
      )
    } catch (err) {
      AppLogger.error(TAG, `resetAllUploadsToPaused failed: ${JSON.stringify(err)}`)
    }
  }

  clearCompleted(): void {
    if (!this.rdbStore) return
    try {
      this.rdbStore.executeSync(`DELETE FROM ${this.downloadTable} WHERE state = ?`, [FileModelState.COMPLETED])
      this.rdbStore.executeSync(`DELETE FROM ${this.uploadTable} WHERE state = ?`, [FileModelState.COMPLETED])
    } catch (err) {
      AppLogger.error(TAG, `clearCompleted failed: ${JSON.stringify(err)}`)
    }
  }

  deleteDownload(id: string): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.downloadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.deleteSync(predicates)
    } catch (err) {
      AppLogger.error(TAG, `deleteDownload failed: ${JSON.stringify(err)}`)
    }
  }

  listDownloads(): DownloadRecord[] {
    const records: DownloadRecord[] = []
    if (!this.rdbStore) return records

    const predicates = new relationalStore.RdbPredicates(this.downloadTable)
    predicates.orderByAsc('created_at')

    let result: relationalStore.ResultSet | undefined = undefined
    try {
      result = this.rdbStore.querySync(predicates)
      if (!result.goToFirstRow()) return records
      do {
        const itemJson = result.getString(result.getColumnIndex('item_json'))
        let item: ObjectInfo
        try {
          item = JSON.parse(itemJson) as ObjectInfo
        } catch (_) {
          continue
        }
        records.push({
          id: result.getString(result.getColumnIndex('id')),
          item,
          path: result.getString(result.getColumnIndex('path')),
          url: result.getString(result.getColumnIndex('url')),
          tid: result.getString(result.getColumnIndex('tid')),
          trans: result.getLong(result.getColumnIndex('trans')),
          total: result.getLong(result.getColumnIndex('total')),
          state: result.getLong(result.getColumnIndex('state')) as FileModelState,
          createdAt: result.getLong(result.getColumnIndex('created_at'))
        })
      } while (result.goToNextRow())
    } catch (err) {
      AppLogger.error(TAG, `listDownloads failed: ${JSON.stringify(err)}`)
    } finally {
      this.closeResult(result)
    }
    return records
  }

  // -------- uploads --------

  upsertUpload(record: UploadRecord): void {
    if (!this.rdbStore) return
    try {
      this.rdbStore.insertSync(this.uploadTable, {
        id: record.id,
        uri: record.uri,
        remote_path: record.remotePath,
        file_name: record.fileName,
        overwrite: record.overwrite ? 1 : 0,
        session_id: record.sessionId,
        chunk_size: record.chunkSize,
        upload_urls_json: JSON.stringify(record.uploadUrls),
        credential: record.credential,
        storage_policy_type: record.storagePolicyType,
        storage_policy_relay: record.storagePolicyRelay ? 1 : 0,
        session_expires_at: record.sessionExpiresAt,
        total: record.total,
        offset: record.offset,
        chunk_index: record.chunkIndex,
        cache_path: record.cachePath,
        state: record.state,
        created_at: record.createdAt
      }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
    } catch (err) {
      AppLogger.error(TAG, `upsertUpload failed: ${JSON.stringify(err)}`)
    }
  }

  updateUploadProgress(id: string, offset: number, chunkIndex: number, state: FileModelState): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.uploadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.updateSync({ offset, chunk_index: chunkIndex, state }, predicates)
    } catch (err) {
      AppLogger.error(TAG, `updateUploadProgress failed: ${JSON.stringify(err)}`)
    }
  }

  updateUploadSession(id: string, sessionId: string, chunkSize: number, uploadUrls: string[],
                      credential: string, storagePolicyType: string, storagePolicyRelay: boolean,
                      sessionExpiresAt: number, cachePath: string, total: number): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.uploadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.updateSync({
        session_id: sessionId,
        chunk_size: chunkSize,
        upload_urls_json: JSON.stringify(uploadUrls),
        credential,
        storage_policy_type: storagePolicyType,
        storage_policy_relay: storagePolicyRelay ? 1 : 0,
        session_expires_at: sessionExpiresAt,
        cache_path: cachePath,
        total
      }, predicates)
    } catch (err) {
      AppLogger.error(TAG, `updateUploadSession failed: ${JSON.stringify(err)}`)
    }
  }

  updateUploadState(id: string, state: FileModelState): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.uploadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.updateSync({ state }, predicates)
    } catch (err) {
      AppLogger.error(TAG, `updateUploadState failed: ${JSON.stringify(err)}`)
    }
  }

  deleteUpload(id: string): void {
    if (!this.rdbStore) return
    const predicates = new relationalStore.RdbPredicates(this.uploadTable)
    predicates.equalTo('id', id)
    try {
      this.rdbStore.deleteSync(predicates)
    } catch (err) {
      AppLogger.error(TAG, `deleteUpload failed: ${JSON.stringify(err)}`)
    }
  }

  listUploads(): UploadRecord[] {
    const records: UploadRecord[] = []
    if (!this.rdbStore) return records

    const predicates = new relationalStore.RdbPredicates(this.uploadTable)
    predicates.orderByAsc('created_at')

    let result: relationalStore.ResultSet | undefined = undefined
    try {
      result = this.rdbStore.querySync(predicates)
      if (!result.goToFirstRow()) return records
      do {
        let uploadUrls: string[] = []
        try {
          uploadUrls = JSON.parse(result.getString(result.getColumnIndex('upload_urls_json'))) as string[]
        } catch (_) {}
        records.push({
          id: result.getString(result.getColumnIndex('id')),
          uri: result.getString(result.getColumnIndex('uri')),
          remotePath: result.getString(result.getColumnIndex('remote_path')),
          fileName: result.getString(result.getColumnIndex('file_name')),
          overwrite: result.getLong(result.getColumnIndex('overwrite')) === 1,
          sessionId: result.getString(result.getColumnIndex('session_id')),
          chunkSize: result.getLong(result.getColumnIndex('chunk_size')),
          uploadUrls,
          credential: result.getString(result.getColumnIndex('credential')),
          storagePolicyType: result.getString(result.getColumnIndex('storage_policy_type')),
          storagePolicyRelay: result.getLong(result.getColumnIndex('storage_policy_relay')) === 1,
          sessionExpiresAt: result.getLong(result.getColumnIndex('session_expires_at')),
          total: result.getLong(result.getColumnIndex('total')),
          offset: result.getLong(result.getColumnIndex('offset')),
          chunkIndex: result.getLong(result.getColumnIndex('chunk_index')),
          cachePath: result.getString(result.getColumnIndex('cache_path')),
          state: result.getLong(result.getColumnIndex('state')) as FileModelState,
          createdAt: result.getLong(result.getColumnIndex('created_at'))
        })
      } while (result.goToNextRow())
    } catch (err) {
      AppLogger.error(TAG, `listUploads failed: ${JSON.stringify(err)}`)
    } finally {
      this.closeResult(result)
    }
    return records
  }

  private closeResult(result?: relationalStore.ResultSet): void {
    if (!result) return
    try { result.close() } catch (_) {}
  }
}

export default new TransferDatabase();
