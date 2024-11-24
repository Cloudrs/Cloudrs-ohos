import axios, { AxiosError, AxiosRequestConfig, AxiosResponse, InternalAxiosRequestConfig } from "@ohos/axios";
import { UserInfo, GroupInfo, SiteCommon } from "../types/ApiTypes";
import { REQUEST_TIMEOUT, CLOUDREVE_URL_PREFIX, CLOUDREVE_URL_LOGIN, CLOUDREVE_URL_PING } from "../common/Common";

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: REQUEST_TIMEOUT,
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
  console.log('AxiosRequest', `baseUrl: ${url}`)
  axiosInstance.defaults.baseURL = url + CLOUDREVE_URL_PREFIX
}

export function cookieSet(cookie: string) {
  console.log('AxiosRequest', "Set-Cookie :", cookie);
  axiosInstance.defaults.headers.common['Cookie'] = cookie
}

/**
 * 网站测试
 * @returns
 */
export async function cloudPingRequest(): Promise<boolean> {
  try {
    let resp: AxiosResponse<SiteCommon<string>> = await axiosInstance.get<SiteCommon<string>, AxiosResponse<SiteCommon<string>>, null>(CLOUDREVE_URL_PING)
    if ( resp.status === 200 && resp.data.code === 0) {
      console.log('AxiosRequest', "success : ", JSON.stringify(resp))
      return true
    } else {
      console.error('AxiosRequest', `failed : ${resp.status}`, JSON.stringify(resp))
      return false
    }
  } catch (e) {
    console.error('AxiosRequest', `failed : ${e}`)
    return false
  }
}

/**
 * 网站登录
 * @param username  用户邮箱
 * @param password  用户密码
 * @returns Promise<UserInfo | null>
 */
export async function cloudLogin(username: string, password: string): Promise<UserInfo | null> {
  try {
    let resp: AxiosResponse<SiteCommon<UserInfo>> = await axiosInstance.post<SiteCommon<UserInfo>>(CLOUDREVE_URL_LOGIN, {
      username: username,
      password: password,
      captchaCode: ''
    })
    if ( resp.status === 200 && resp.data.code === 0) {
      console.log('AxiosRequest', "success :", JSON.stringify(resp))
      let cookie: string | undefined = resp.headers["set-cookie"]?.toString()
      if (cookie) {
        let regex = /cloudreve-session=([^;]+);/;
        let match = cookie.match(regex)
        if (match) {
          cookieSet(match[1])
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
