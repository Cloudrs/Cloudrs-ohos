export const init: (baseUrl: string) => Promise<string>;
export const getApiVersionInfo: () => Promise<string[]>;
export const restoreSession: (baseUrl: string, accessToken: string, refreshToken: string, isV3: boolean) => void;
export const takeRefreshedSession: () => string[];
/** 登出/删凭据：丢弃存着的 v4 refresh token、未取走的续期结果和当前客户端的 token。 */
export const clearSession: () => void;
export const getSiteConfig: () => Promise<string>;
export const login: (username: string, password: string) => Promise<string[]>;
export const login2fa: (code: string) => Promise<string[]>;
export const loginWithRefreshToken: (baseUrl: string, refreshToken: string) => Promise<string[]>;
export const getUserStorage: () => Promise<string>;
export const getUserAvatar: (userId: string) => Promise<Uint8Array>;
/** v4 账号设置的扁平 JSON（AccountSettings）；v3 返回 {"supported":false,...} */
export const getAccountSettings: () => Promise<string>;
export const updateNickname: (nick: string) => Promise<void>;
export const changePassword: (current: string, next: string) => Promise<void>;
/** 返回 TOTP secret，服务端 10 分钟内有效 */
export const initTwoFactor: () => Promise<string>;
export const setTwoFactor: (enabled: boolean, code: string) => Promise<void>;
/** base64Data 为图片原始字节的 base64 */
export const uploadAvatar: (base64Data: string, contentType: string) => Promise<void>;
export const resetAvatar: () => Promise<void>;
export const deletePasskey: (id: string) => Promise<void>;
export const getDirectory: (path: string) => Promise<string>;
export const getObjectDetail: (id: string, isFolder: boolean) => Promise<string>;
export const deleteObjects: (items: string[], dirs: string[]) => Promise<void>;
export const deleteObjectLockAware: (path: string) => Promise<string>;
export const unlockFiles: (tokens: string[]) => Promise<void>;
/** 一次删除整批，返回 BatchOutcome 的 JSON；未出现在 failed 里的即为成功 */
export const deleteObjectsBatch: (items: string[], dirs: string[]) => Promise<string>;
/** 一次移动（copy=false）或复制（copy=true）整批，返回结构同 deleteObjectsBatch */
export const transferObjectsBatch: (items: string[], dirs: string[], srcDir: string, dst: string, copy: boolean) => Promise<string>;
export const getFileMetadata: (path: string) => Promise<string>;
export const searchFiles: (keyword: string, path: string) => Promise<string>;
export const moveObjects: (items: string[], dirs: string[], srcDir: string, dst: string) => Promise<void>;
export const copyObjects: (items: string[], dirs: string[], srcDir: string, dst: string) => Promise<void>;
export const renameObject: (id: string, newName: string, isDir: boolean) => Promise<void>;
export const newDirectory: (path: string) => Promise<void>;
export const newFile: (path: string) => Promise<void>;
export const getDownloadUri: (id: string) => Promise<string>;
export const getUploadUri: (path: string, size: number, name: string, lastModified: number, mimeType: string, chunkSize: number) => Promise<string>;
export const deleteUploadSession: (path: string, sessionId: string) => Promise<void>;
/** 删掉当前账号名下全部上传占位（V3 专属兜底，sessionId 丢了时用）。V4 无此接口，返回 false。 */
export const deleteAllUploadSessions: () => Promise<boolean>;
/** 覆盖已存在文件的内容：V3 走 PUT /file/update/{id}，V4 走覆盖上传。 */
export const updateFileContent: (id: string, remotePath: string, localPath: string, lastModifiedMs?: number | null) => Promise<void>;
export const uploadLocalFile: (localPath: string, remotePath: string, overwrite: boolean, lastModifiedMs?: number | null) => Promise<void>;
export const uploadLocalFileChunk: (localPath: string, sessionId: string, index: number, offset: number, length: number) => Promise<number>;
export const uploadLocalFileChunkWithProgress: (localPath: string, sessionId: string, index: number, offset: number, length: number, progress: (uploaded: number) => void) => Promise<number>;
export const uploadLocalFileChunkToUrl: (localPath: string, uploadUrl: string, credential: string, index: number, offset: number, length: number) => Promise<number>;
export const uploadLocalFileChunkToUrlWithProgress: (localPath: string, uploadUrl: string, credential: string, index: number, offset: number, length: number, progress: (uploaded: number) => void) => Promise<number>;
export const aria2Downloading: () => Promise<string>;
export const aria2Finished: (page: number) => Promise<string>;
export const aria2CreateTask: (dst: string, urls: string[]) => Promise<void>;
export const aria2CancelTask: (gid: string) => Promise<void>;
export const aria2DeleteTask: (gid: string) => Promise<void>;
export const aria2CanDeleteFinished: () => Promise<boolean>;
export const getUserTasks: (page: number) => Promise<string>;
export const getThumb: (id: string) => Promise<string>;
export const createShareLink: (path: string, expireDays: number, password: string) => Promise<string>;
export const listShareLinks: () => Promise<string>;
export const deleteShareLink: (shareId: string) => Promise<void>;
export const createArchive: (srcPaths: string[], dstPath: string) => Promise<string>;
export const extractArchive: (srcPaths: string[], dstPath: string) => Promise<string>;
