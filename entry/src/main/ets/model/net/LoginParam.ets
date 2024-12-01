export class LoginParam {
  isAdd: boolean = false
  nextPage: string = ''
  url: string = ''
  username: string = ''
  password: string = ''

  constructor(isAdd?: boolean, nextPage?: string, url?: string, username?: string, password?: string) {
    this.isAdd = isAdd ?? false
    this.nextPage = nextPage ?? ''
    this.url = url ?? ''
    this.username = username ?? ''
    this.password = password ?? ''
  }
}