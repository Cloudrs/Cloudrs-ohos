
export interface SiteCommon<T> {
  code: number;
  data: T;
  msg: string;
}

export interface GroupInfo {
  id: string;
  name: string;
  allowShare: boolean;
  allowRemoteDownload: boolean;
  allowArchiveDownload: boolean;
  shareDownload: boolean;
  compress: boolean;
  webdav: boolean;
  sourceBatch: number;
  advanceDelete: boolean;
  allowWebDAVProxy: boolean;
}

export interface UserInfo {
  id: string;
  user_name: string;
  nick_name: string;
  status: number;
  avatar: string;
  created_at: string;
  preferred_theme: string;
  anonymous: boolean;
  group: GroupInfo;
}