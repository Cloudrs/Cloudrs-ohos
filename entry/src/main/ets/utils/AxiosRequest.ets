import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from "@ohos/axios";
import {SiteCommon } from "../types/ApiTypes";
import { CLOUDREVE_REQUEST_TIMEOUT, CLOUDREVE_URL_PREFIX, USERPRIVDATA_NAME} from "../common/Common";
import UserPrivData from "./UserPrivData";

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: CLOUDREVE_REQUEST_TIMEOUT,
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
  axiosInstance.defaults.baseURL = url + CLOUDREVE_URL_PREFIX
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
 * @param
 * @returns Promise<T | null>
 */
export async function cloudGet<T>(path: string): Promise<T | null> {
  try {
    let resp: AxiosResponse<SiteCommon<T>> = await axiosInstance.get<SiteCommon<T>>(path)
    if ( resp.status === 200 && resp.data.code === 0) {
      console.info('AxiosRequest', "success :", JSON.stringify(resp))
      return resp.data.data
    } else {
      console.error('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
      return null
    }
  } catch (e) {
    console.error('AxiosRequest', `failed : ${e}`)
    return null
  }
}

/**
 * 网站通用POST请求,T为返回json结构中data数据
 * @param
 * @returns Promise<T | null>
 */
export async function cloudPost<T, V>(path: string, body: V): Promise<T | null> {
  try {
    let resp: AxiosResponse<SiteCommon<T>> = await axiosInstance.post<SiteCommon<T>>(path, body)
    if ( resp.status === 200 && resp.data.code === 0) {
      console.info('AxiosRequest', "success :", JSON.stringify(resp))
      /* 返回cookies进行保存 */
      let cookies: string | undefined = resp.headers["set-cookie"]?.toString()
      if (cookies) {
        let regex = /cloudreve-session=([^;]+);/;
        let match = cookies.match(regex)
        if (match) {
          let cookie = match[1]
          cookieSet(`cloudreve-session=${cookie}`)
        }
      }
      return resp.data.data
    } else {
      console.error('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
      return null
    }
  } catch (e) {
    console.error('AxiosRequest', `failed : ${e}`)
    return null
  }
}
