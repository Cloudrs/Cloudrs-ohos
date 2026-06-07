export enum PhotoBackupStatus {
  WAITING = 'waiting',
  UPLOADING = 'uploading',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export enum PhotoBackupState {
  IDLE = 'idle',
  SCANNING = 'scanning',
  WAITING_NETWORK = 'waitingNetwork',
  BACKING_UP = 'backingUp',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export class PhotoBackupSettings {
  static readonly DEFAULT_UPLOAD_CONCURRENT: number = 5
  static readonly MIN_UPLOAD_CONCURRENT: number = 1
  static readonly DEFAULT_REMOTE_PATH: string = '/Photos/Camera'

  enabled: boolean = false
  remotePath: string = PhotoBackupSettings.DEFAULT_REMOTE_PATH
  wifiOnly: boolean = true
  autoBackup: boolean = true
  uploadConcurrent: number = PhotoBackupSettings.DEFAULT_UPLOAD_CONCURRENT
  lastScanAt: number = 0

  static fromJson(json: string): PhotoBackupSettings {
    let settings = new PhotoBackupSettings()
    if (json.length === 0) {
      return settings
    }

    try {
      let value = JSON.parse(json) as PhotoBackupSettingsData
      settings.enabled = (value.enabled as boolean) ?? false
      settings.remotePath = (value.remotePath as string) ?? PhotoBackupSettings.DEFAULT_REMOTE_PATH
      settings.wifiOnly = (value.wifiOnly as boolean) ?? true
      settings.autoBackup = (value.autoBackup as boolean) ?? true
      settings.uploadConcurrent = Math.max((value.uploadConcurrent as number) ??
        PhotoBackupSettings.DEFAULT_UPLOAD_CONCURRENT, PhotoBackupSettings.MIN_UPLOAD_CONCURRENT)
      settings.lastScanAt = (value.lastScanAt as number) ?? 0
    } catch (err) {
      console.error('PhotoBackupSettings', `parse failed: ${(err as Error)?.message ?? err}`)
    }
    return settings
  }

  toJson(): string {
    return JSON.stringify({
      enabled: this.enabled,
      remotePath: this.remotePath,
      wifiOnly: this.wifiOnly,
      autoBackup: this.autoBackup,
      uploadConcurrent: this.uploadConcurrent,
      lastScanAt: this.lastScanAt
    })
  }
}

interface PhotoBackupSettingsData {
  enabled?: boolean
  remotePath?: string
  wifiOnly?: boolean
  autoBackup?: boolean
  uploadConcurrent?: number
  lastScanAt?: number
}

@ObservedV2
export class PhotoBackupItem {
  id: string = ''
  uri: string = ''
  name: string = ''
  size: number = 0
  modifiedAt: number = 0
  @Trace status: PhotoBackupStatus = PhotoBackupStatus.WAITING
  @Trace progress: number = 0
  @Trace error: string = ''

  constructor(uri: string, name: string, size: number, modifiedAt: number) {
    this.uri = uri
    this.name = name
    this.size = size
    this.modifiedAt = modifiedAt
    this.id = `${uri}_${size}_${modifiedAt}`
  }

  static fromData(data: PhotoBackupItemData): PhotoBackupItem {
    let item = new PhotoBackupItem(data.uri ?? '', data.name ?? '', data.size ?? 0, data.modifiedAt ?? 0)
    item.id = data.id ?? item.id
    item.status = data.status ?? PhotoBackupStatus.WAITING
    item.progress = data.progress ?? 0
    item.error = data.error ?? ''
    return item
  }

  toData(): PhotoBackupItemData {
    return {
      id: this.id,
      uri: this.uri,
      name: this.name,
      size: this.size,
      modifiedAt: this.modifiedAt,
      status: this.status,
      progress: this.progress,
      error: this.error
    }
  }
}

export interface PhotoBackupItemData {
  id?: string
  uri?: string
  name?: string
  size?: number
  modifiedAt?: number
  status?: PhotoBackupStatus
  progress?: number
  error?: string
}

export class PhotoBackupPathHistory {
  path: string = ''
  count: number = 0
  isCurrent: boolean = false

  constructor(path: string, count: number, isCurrent: boolean) {
    this.path = path
    this.count = count
    this.isCurrent = isCurrent
  }
}
