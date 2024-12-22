import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from "@ohos/axios";
import {BaseResponse, HttpCallback, HttpCode, SiteURI } from "../model/net/ApiTypes";
import Constant from "../model/Constant";
import { JSON } from "@kit.ArkTS";
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: Constant.REQUEST_TIMEOUT,
  method: 'get',
})

const rcpSession = rcp.createSession()

// 请求拦截器
axiosInstance.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    // console.debug('AxiosRequest:', JSON.stringify(config));
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
  return axiosInstance.defaults.headers.common['Cookie']?.toString()
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
  axiosInstance.defaults.timeout = Constant.REQUEST_TIMEOUT
  axiosInstance.get<BaseResponse<T>>(encodeURI(path))
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "GET success :", JSON.stringify(resp))
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `GET failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `GET error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}

/**
 * 网站通用DELETE请求,T为返回json结构中data数据
 * @param path  请求uri路径
 * @param body  请求数据体
 * @param callback 回调函数
 * @returns Promise<T | null>
 */
export function cloudDelete<T, V>(path: string, body: V, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.defaults.timeout = Constant.REQUEST_TIMEOUT
  axiosInstance.delete<BaseResponse<T>>(encodeURI(path), {data: body})
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "DELETE success :", JSON.stringify(resp))
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `DELETE failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `DELETE error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}

/**
 * 网站通用PUT请求,T为返回json结构中data数据
 * @param path  请求uri路径
 * @param body  请求数据体
 * @param callback 回调函数
 * @returns Promise<T | null>
 */
export function cloudPut<T, V>(path: string, body: V, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.defaults.timeout = Constant.REQUEST_TIMEOUT
  axiosInstance.put<BaseResponse<T>>(encodeURI(path), body)
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "PUT success :", JSON.stringify(resp))
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `PUT failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `PUT error : ${error.message}`)
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
  axiosInstance.defaults.timeout = Constant.REQUEST_TIMEOUT
  axiosInstance.post<BaseResponse<T>>(encodeURI(path), body)
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "POST success :", JSON.stringify(resp))

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
        console.error('AxiosRequest', `POST failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
      console.error('AxiosRequest', `POST error : ${error.message}`)
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
  axiosInstance.defaults.timeout = 60000
  axiosInstance.get<ArrayBuffer>(encodeURI(path))
    .then((resp: AxiosResponse<ArrayBuffer>) => {
      // 这里认为返回的数据小于500为异常，可能返回的是json状态错误码
      if ( resp.status === 200 && resp.data.byteLength > 500) {
        if (callback?.onSuccess) {
          console.debug('AxiosRequest', `GET file: ${path} success`)
          callback.onSuccess(resp.data)
        }
      } else {
        let json = new Uint8Array(resp.data).toString()
        let data = JSON.parse(json)
          if (data) {
            let baseResp = data as BaseResponse<string>
            console.error('AxiosRequest', `GET file failed : ${resp.status}, code : ${baseResp.code}, msg: ${baseResp.msg}`, JSON.stringify(resp))
            if (callback?.onFailure) {
              callback.onFailure(baseResp.msg)
            }
          }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `GET file error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}

/**
 * 网站通用patch请求,T为返回json结构中data数据
 * @param path  请求uri路径
 * @param body  请求数据体
 * @param callback 回调函数
 * @returns Promise<T | null>
 */
export function cloudPatch<T, V>(path: string, body: V, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }
  axiosInstance.defaults.timeout = Constant.REQUEST_TIMEOUT
  axiosInstance.patchForm<BaseResponse<T>>(encodeURI(path), body)
    .then((resp: AxiosResponse<BaseResponse<T>>) => {
      if ( resp.status === 200 && resp.data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "PATCH success :", JSON.stringify(resp))
        if (callback?.onSuccess) {
          callback.onSuccess(resp.data.data)
        }
      } else {
        console.error('AxiosRequest', `PATCH failed : ${resp.status}`, JSON.stringify(resp))
        if (callback?.onFailure) {
          callback.onFailure(resp.data.msg)
        }
      }
    }).catch((error: AxiosError) => {
    console.error('AxiosRequest', `PATCH error : ${error.message}`)
    if (callback?.onFailure) {
      callback.onFailure(error.message)
    }
  })
}

/**
 * 网站通用patch请求,T为返回json结构中data数据，由于axio不支持patch暂使用rcp替代，后续支持删除
 * @param path  请求uri路径
 * @param body  请求数据体
 * @param callback 回调函数
 * @returns Promise<T | null>
 */
export function cloudPatchWithRcp<T>(path: string, body: object, callback?:HttpCallback<T>) {
  if (callback?.onStart) {
    callback.onStart()
  }

  let request: rcp.Request = new rcp.Request(baseUrlGet() + path, 'PATCH')
  let cookies: string|undefined = cookieGet()
  if (cookies) {
    let temp = cookies.split('=')
    if (temp.length > 1) {
      request.cookies = {
        'cloudreve-session': temp[1]
      }
    }
  }
  request.headers = {
    'content-type': 'application/json'
  }
  request.content = JSON.stringify(body)

  rcpSession.fetch(request)
    .then((resp: rcp.Response) => {
      let data = resp.toJSON() as BaseResponse<T>
      if ( resp.statusCode === 200 && data.code === HttpCode.SUCCESS) {
        console.debug('AxiosRequest', "PATCH success :", JSON.stringify(data))
        if (callback?.onSuccess) {
          callback.onSuccess(data.data)
        }
      } else {
        console.error('AxiosRequest', `PATCH failed : ${resp.statusCode}`, JSON.stringify(data))
        if (callback?.onFailure) {
          callback.onFailure(data.msg)
        }
      }
    }).catch((error: BusinessError) => {
      console.error('AxiosRequest', `PATCH error : ${error.message}`)
      if (callback?.onFailure) {
        callback.onFailure(error.message)
      }
  })
}
