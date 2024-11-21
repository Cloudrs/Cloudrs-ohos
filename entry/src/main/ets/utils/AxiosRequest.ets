import axios, { AxiosError, AxiosResponse } from "@ohos/axios";
import { SitePing } from "../model/Response";

const HTTP_URI_PREFIX:string = '/api/v3'

const axiosInstance = axios.create({
  baseURL: 'https://cloudrs.cn/api/v3',
  timeout: 3000,
  method: 'get',
})

export function baseUrlSet(url: string) {
  axiosInstance.defaults.baseURL = url + HTTP_URI_PREFIX
}

export async function pingRequest(): Promise<boolean> {
  try {
    let resp: AxiosResponse<SitePing> = await axiosInstance.get<SitePing, AxiosResponse<SitePing>, null>('/site/ping')
    console.log('AxiosRequest', "response: ", JSON.stringify(resp))
    if ( resp.status === 200 && resp.data.code === 0) {
      return true
    } else {
      return false
    }
  } catch (e) {
    console.log('AxiosRequest', `PingRequest failed, ${e} `)
    return false
  }
}
