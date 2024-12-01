export enum TabId {
  FILES,
  PICTURES,
  REMOTE_DOWN,
  MINE
}

export interface TabItem {
  image: Resource
  text: Resource | string
  tabId: number
}

export const TabList: TabItem[] = [
  {
    image: $r("app.media.ic_tabbar_files"),
    text: $r("app.string.tab_bar_files"),
    tabId: TabId.FILES
  },
  {
    image: $r("app.media.ic_tabbar_pictures"),
    text: $r("app.string.tab_bar_pictures"),
    tabId: TabId.PICTURES
  },
  {
    image: $r("app.media.ic_tabbar_remote_down"),
    text: $r("app.string.tab_bar_remote_down"),
    tabId: TabId.REMOTE_DOWN
  },
  {
    image: $r("app.media.ic_tabbar_mine"),
    text: $r("app.string.tab_bar_mine"),
    tabId: TabId.MINE
  }
]