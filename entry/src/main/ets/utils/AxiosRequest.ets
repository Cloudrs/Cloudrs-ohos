import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from "@ohos/axios";
import {BaseResponse, HttpCallback, HttpCode, SiteURI } from "../model/net/ApiTypes";
import Constant from "../model/Constant";
import { JSON } from "@kit.ArkTS";

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: Constant.REQUEST_TIMEOUT,
  method: 'get',
})

// 请求拦截器
axiosInstance.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    console.debug('AxiosRequest:', JSON.stringify(config));
    return config;
  },
  (error: AxiosError) => {
    console.error('AxiosRequest Error:', error);
    return Promise.reject(error);
  }
);

export function baseUrlSet(url: string) {
  console.debug('AxiosRequest', `baseUrl: ${url}`)
  axiosInstance.defaults.baseURL = url + SiteURI.PREFIX
}

export function baseUrlGet(): string {
  return axiosInstance.defaults.baseURL ?? ''
}

export function cookieSet(cookie: string) {
  console.debug('AxiosRequest', "Set-Cookie :", cookie);
  axiosInstance.defaults.headers.common['Cookie'] = cookie
}

export function cookieGet() {
  return axiosInstance.defaults.headers.common['Cookie']
}

/**
 * 网站通用GET请求,T为返回json结构中data数据
 * @param path  请求uri路径
 * @param callback 回调函数
 * @returns
 */
export function cloudGet<T>(path: string, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.get<BaseResponse<T>>(encodeURI(path))
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "success :", JSON.stringify(resp))
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}

/**
 * 网站通用POST请求,T为返回json结构中data数据
 * @param path  请求uri路径
 * @param body  请求数据体
 * @param callback 回调函数
 * @returns Promise<T | null>
 */
export function cloudPost<T, V>(path: string, body: V, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.post<BaseResponse<T>>(encodeURI(path), body)
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "success :", JSON.stringify(resp))

        /* 返回cookies进行保存 */
        let cookies: string | undefined = resp.headers["set-cookie"]?.toString()
        if (cookies) {
          let regexSession = /cloudreve-session=([^;]+);/;
          let matchCookie = cookies.match(regexSession)
          if (matchCookie) {
            let cookie = matchCookie[1]
            AppStorage.setOrCreate(Constant.CLOUD_COOKIE, `cloudreve-session=${cookie}`)
          }

          let regexExpires = /Expires=([^;]+);/;
          let matchExpires = cookies.match(regexExpires)
          if (matchExpires) {
            let expires = matchExpires[1]
            AppStorage.setOrCreate(Constant.CLOUD_COOKIE_EXPIRES, expires)
          }
        }
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
      console.error('AxiosRequest', `error : ${error.message}`)
      if (callback?.onFailure) {
        callback.onFailure(error.message)
      }
    })
}

/**
 * 网站通用文件GET请求,返回实际ArrayBuffer数据
 * @param path  请求uri路径
 * @param callback 回调函数
 * @returns
 */
export function cloudGetFile(path: string, callback?:HttpCallback<ArrayBuffer>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.get<ArrayBuffer>(encodeURI(path))
    .then((resp: AxiosResponse<ArrayBuffer>) => {
      // 这里认为返回的数据小于500为异常，可能返回的是json状态错误码
      if ( resp.status === 200 && resp.data.byteLength > 500) {
        if (callback?.onSuccess) {
          console.debug('AxiosRequest', "get file success")
          callback.onSuccess(resp.data)
        }
      } else {
        let json = new Uint8Array(resp.data).toString()
        let data = JSON.parse(json)
          if (data) {
            let baseResp = data as BaseResponse<string>
            console.error('AxiosRequest', `failed : ${resp.status}, code : ${baseResp.code}, msg: ${baseResp.msg}`, JSON.stringify(resp))
            if (callback?.onFailure) {
              callback.onFailure(baseResp.msg)
            }
          }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}
