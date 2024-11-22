import axios, { AxiosError, AxiosRequestConfig, AxiosResponse, InternalAxiosRequestConfig } from "@ohos/axios";
import { UserInfo, GroupInfo, SiteCommon } from "../model/Response";

const CLOUDREVE_URL_PREFIX:string = '/api/v3'
const CLOUDREVE_URL_PING: string = '/site/ping'
const CLOUDREVE_URL_LOGIN: string = '/user/session'

interface LoginData {
  userName: string,
  Password: string,
  captchaCode: string
}

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: 3000,
  method: 'get',
})

// 请求拦截器
axiosInstance.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    console.log('AxiosRequest:', JSON.stringify(config));
    return config;
  },
  (error: AxiosError) => {
    console.error('AxiosRequest Error:', error);
    return Promise.reject(error);
  }
);

export function baseUrlSet(url: string) {
  axiosInstance.defaults.baseURL = url + CLOUDREVE_URL_PREFIX
}

export function cookieSet(cookie: string) {
  console.log('AxiosRequest', "Set-Cookie :", cookie);
  axiosInstance.defaults.headers.common['Cookie'] = cookie
}

export async function cloudPingRequest(): Promise<boolean> {
  try {
    let resp: AxiosResponse<SiteCommon<string>> = await axiosInstance.get<SiteCommon<string>, AxiosResponse<SiteCommon<string>>, null>(CLOUDREVE_URL_PING)
    if ( resp.status === 200 && resp.data.code === 0) {
      console.log('AxiosRequest', "success : ", JSON.stringify(resp))
      return true
    } else {
      console.log('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
      return false
    }
  } catch (e) {
    console.log('AxiosRequest', `failed : ${e}`)
    return false
  }
}

export async function cloudLogin(username: string, password: string): Promise<UserInfo | null> {
  try {
    let loginData: LoginData = {
      userName: username,
      Password: password,
      captchaCode: ''
    };

    let resp: AxiosResponse<SiteCommon<UserInfo>> = await axiosInstance.post<SiteCommon<UserInfo>>(CLOUDREVE_URL_LOGIN, loginData)
    if ( resp.status === 200 && resp.data.code === 0) {
      console.log('AxiosRequest', "success :", JSON.stringify(resp))
      let cookie: string | undefined = resp.headers["set-cookie"]?.toString()
      if (cookie) {
        cookieSet(cookie.split(';')[0])
      }
      return resp.data.data
    } else {
      console.log('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
      return null
    }
  } catch (e) {
    console.log('AxiosRequest', `failed : ${e}`)
    return null
  }
}
