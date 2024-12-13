import { image } from "@kit.ImageKit";
import Constant from "../Constant";
import { SortType } from "../MenuModel";

export enum SiteURI {
  PREFIX = '/api/v3',
  CONFIG = '/site/config',
  PING = '/site/ping',
  LOGO = '/static/img/logo512.png',
  LOGIN = '/user/session',
  USER_STORAGE = '/user/storage',
  DIRECTORY = '/directory',
  THUMB = '/file/thumb',
  PREVIEW = '/file/preview',
  NEW_FILE = '/file/create',
  OBJECT = '/object',
  OBJECT_DETAIL = '/object/property',
  OBJECT_RENAME = '/object/rename',
  OBJECT_COPY = '/object/copy',
  SEARCH = '/file/search/keywords'
}

export const enum HttpCode {
  SUCCESS = 0
}

export interface HttpCallback<T> {
  onStart?: () => void
  onSuccess: (data: T) => void
  onFailure: (msg: string) => void
}

/**
 * 站点通用结构，T为具体
 */
export interface BaseResponse<T> {
  code: number;
  data: T;
  msg: string;
}

/**
 * 登录请求信息
 */
export interface LoginData {
  username: string;
  password: string;
  captchaCode: string;
}

/**
 * 用户组信息
 */
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

/**
 * 用户登录信息
 */
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

/**
 * 站点配置信息
 */
export interface SiteConfig {
  title: string;
  loginCaptcha: string;
  regCaptcha: false;
  forgetCaptcha: false;
  emailActive: false;
  themes: string;
  defaultTheme: string;
  home_view_method: string;
  share_view_method: string;
  authn: false;
  user: UserInfo;
  captcha_ReCaptchaKey: string;
  captcha_type: string;
  tcaptcha_captcha_app_id: string;
  registerEnabled: false;
  app_promotion: false;
  wopi_exts: string;
}

/**
 * 用户存储信息
 */
export interface UserStorage {
  used: number;
  free: number;
  total: number;
}

/**
 * 保存数据数据结构
 */
export interface DbUserInfo {
  url: string;
  username: string;
  password: string;
  cookie: string;
  expires: string;
  userinfo: UserInfo;
}

export interface ObjectInfo {
  id: string;
  name: string;
  path: string;
  thumb: boolean;
  size: number;
  type: string;
  date: string;
  create_date: string;
  source_enabled: boolean;
}

export interface Policy {
  id: string;
  name: string;
  type: string;
  max_size: number;
  file_type: null
}

export interface DirectoryInfo {
  parent: string;
  objects: ObjectInfo[];
  policy: Policy;
}

@Observed
export class DirFileInfo implements DirectoryInfo {
  parent: string = '';
  objects: ObjectInfo[] = [];
  policy: Policy = {id: '', name: '', type: '', max_size: 0, file_type: null};
  dirObjects: ObjectInfo[] = [];
  fileObjects: ObjectInfo[] = [];

  constructor(parent?: string, objects?: ObjectInfo[], policy?: Policy) {
    if (parent) {
      this.parent = parent;
    }
    if (objects) {
      this.objects = objects;
      this.dirObjects = this.objects.filter(value => value.type == Constant.OBJECT_DIR_TYPE)
      this.fileObjects = this.objects.filter(value => value.type == Constant.OBJECT_FILE_TYPE)
    }

    if (policy) {
      this.policy = policy;
    }
  }

  public getDirObjects() {
    return this.dirObjects
  }

  public getFileObjects() {
    return this.fileObjects
  }

  public sortObjects(sortType: SortType, isReserve: boolean) {
    switch (sortType) {
      case SortType.SORT_BY_NAME:
        this.dirObjects.sort((a,b) => isReserve ? b.name.localeCompare(a.name) : a.name.localeCompare(b.name))
        this.fileObjects.sort((a,b) => isReserve ? b.name.localeCompare(a.name) : a.name.localeCompare(b.name))
        break
      case SortType.SORT_BY_TIME:
        this.dirObjects.sort((a,b) => {
          let dateA = new Date(a.date).getTime()
          let dateB = new Date(b.date).getTime()
          return isReserve ? dateB - dateA : dateA - dateB
        })
        this.fileObjects.sort((a,b) => {
          let dateA = new Date(a.date).getTime()
          let dateB = new Date(b.date).getTime()
          return isReserve ? dateB - dateA : dateA - dateB
        })
        break
      case SortType.SORT_BY_SIZE:
        this.dirObjects.sort((a,b) => isReserve ? b.size - a.size : a.size - b.size)
        this.fileObjects.sort((a,b) => isReserve ? b.size - a.size : a.size - b.size)
        break
    }
  }
}

export class ObjectDetail {
  created_at: string = ''
  updated_at: string = ''
  policy: string = ''
  size: number = 0
  child_folder_num: number = 0
  child_file_num: number = 0
  path: string = ''
  query_date: string = ''
}