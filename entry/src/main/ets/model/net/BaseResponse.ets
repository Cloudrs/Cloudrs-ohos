export class BaseResponse<T> {
  data?: T
  errorCode?: number
  errorMsg?: string
}