import { DirectoryInfo, ObjectDetail, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { TabFilesTitle } from "../../components/TabFilesTitle";
import { cloudGetFilesInfo, cloudGetObjectDetail, cloudGetThumb } from "../../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { image } from "@kit.ImageKit";
import { FileItem } from "../../components/FileItem";
import { TabFilesHeader } from "../../components/TabFilesHeader";
import { FileUtil } from "@pura/harmony-utils";
import { HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../../model/Params";
import { ExitLifecycle } from "../../lifecycle/ExitLifecycle";
import { FileMenuType } from "../../model/MenuModel";
import { filePreview } from "@kit.PreviewKit";
import { DetailData } from "../../model/DetailData";
import { DetailSheet } from "../../components/DetailSheet";

const TAG = 'TabFiles';

@Component
export struct TabFiles {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @State policy: Policy|null = null
  @State isRoot: boolean = true
  @State mainTitle: string|Resource = $r('app.string.files_main_title')
  @State subTitle: string|Resource = $r('app.string.files_sub_title')
  @Provide thumbImage: Map<string, PixelMap> = new Map()
  @State isRefreshing:boolean = false
  @State showObjectDetail: boolean = false
  @State detailData: DetailData = new DetailData('Unknown', false, new ObjectDetail())
  private currentPath: string = '/'
  private scrollerForList: Scroller = new Scroller()
  private dataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()

  setThumbData(id: string, pixMap: PixelMap) {
    this.thumbImage.set(id, pixMap)
  }

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  onBackPressedCallback(): boolean {
    console.debug(TAG, 'onBackPressedCallback ....')
    if (this.currentPath === '/') {
      return false
    }

    this.getFileList(true, this.getDirectoryPath(this.currentPath))
    return true
  }

  aboutToAppear() {
    this.dataSource.onDataGet = (index: number, item: ObjectInfo) => {
      console.debug(TAG, `onDataGet: index:${index}`)
      this.getThumbFile(index, item)
    }
    (HMRouterMgr.getCurrentLifecycleOwner()?.getLifecycle() as ExitLifecycle).onBackPressedCallback = this.onBackPressedCallback.bind(this)
    this.getFileList(true, '/')
  }

  getDirectoryPath(filePath: string): string {
    const lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex === -1) {
      return '/';
    }
    const directoryPath = filePath.substring(0, lastSlashIndex);
    return directoryPath === '' ? '/' : directoryPath;
  }

  getLastDirectoryName(filePath: string): string {
    // 分割路径并去除空字符串
    const parts = filePath.split('/').filter(part => part !== '');
    const lastDirectoryName = parts.length >= 1 ? parts[parts.length - 1] : '/';
    return lastDirectoryName;
  }

  async getThumbFile(index: number, item: ObjectInfo) {
    if (item.thumb && !this.getThumbData(item.id)) {
      cloudGetThumb(item.id, {
        onSuccess: (data: ArrayBuffer) => {
          let imageSource: image.ImageSource = image.createImageSource(data)
          imageSource.createPixelMap().then((pixMap: PixelMap) => {
            this.setThumbData(item.id, pixMap)
          })
        },
        onFailure: (msg) => {
          console.error(TAG, `Get thumb failed, msg:${msg}`)
        }
      })
    }
  }

  async getFileList(isRefresh: boolean, path: string) {
    if (path === '/') {
      this.isRoot = true
    }
    else {
      this.isRoot = false
    }
    this.currentPath = path
    this.mainTitle = this.isRoot ? $r('app.string.files_main_title') : this.getLastDirectoryName(path)
    cloudGetFilesInfo(path, {
      onStart: () => {
        if (isRefresh) {
          this.dataSource.clear()
          this.thumbImage.clear()
          this.scrollerForList.scrollEdge(Edge.Start)
        }
      },
      onSuccess: (data: DirectoryInfo) => {
        this.policy = data.policy
        this.subTitle = this.policy.name
        data.objects.forEach((value, index) => {
          this.dataSource.pushData(value)
        })
        this.isRefreshing = false
      },
      onFailure: (msg) => {
        showToastTips('获取文件失败', ToastType.Error)
        //决定是否重新登录
        this.isRefreshing = false
      }
    })
  }

  build() {
    Column() {
      Blank().height(this.sysTopRectHeight)

      Column({ space: 10 }) {
        TabFilesHeader({
          isRoot: this.isRoot,
          onBackClick: (async () => {
            await this.getFileList(true, this.getDirectoryPath(this.currentPath))
          })
        })
        TabFilesTitle({ mainTitle: this.mainTitle, subTitle: this.subTitle})
      }
      .height(80)
      .margin({top: 20})
      .justifyContent(FlexAlign.Center)

      Refresh({refreshing: $$this.isRefreshing}) {
        Grid(this.scrollerForList) {
          LazyForEach(this.dataSource, (item: ObjectInfo, index: number) => {
            GridItem() {
              FileItem({index, item, onMenuClick : (async (item, type) => {
                  await this.onMenuClick(item, type)
                })
              })
            }
            .onClick(async () => {
              this.onItemClick(item)
            })
          }, (item: ObjectInfo, index: number) => item.id)
        }
        .cachedCount(2)
        .maxCount(2)
        .padding({ left: 10, right: 10, bottom: 10 })
        .width('100%')
        .height('100%') //!!!使用lazyforeach必须设置高度才能有效
        .rowsGap(10)
        .columnsGap(10)
        .columnsTemplate('1fr 1fr')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBarWidth(2)
        .onScrollIndex((first, last) => {
          console.debug(TAG, `onScrollIndex: first:${first}, last:${last}`)
        })
      }
      .margin({ top: 20 })
      .layoutWeight(1)
      .refreshOffset(77)
      .pullToRefresh(true)
      .onRefreshing(async () => {
        await this.getFileList(true, this.currentPath);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.nav_background'))
    .bindSheet($$this.showObjectDetail, this.detailSheetBuilder(), {
      detents: [SheetSize.FIT_CONTENT],
      backgroundColor: Color.White,
      title: {title: $r('app.string.detail_title')}
    })
  }

  @Builder detailSheetBuilder() {
    DetailSheet({detailData: this.detailData})
  }

  async onItemClick(item: ObjectInfo) {
    console.debug(TAG)
    if (item.type == 'dir') {
      await this.getFileList(true,
        item.path === '/' ? item.path + item.name : `${item.path}/${item.name}`)
    }
    else {
      let fileType = FileUtil.getFileExtention(item.name).toLowerCase()
      if (fileType == 'png' || fileType == 'jpg') {
        HMRouterMgr.push({pageUrl: Constant.IAMGE_PREVIEW_PAGE, param: new ImagePreview(item.name, item.id, fileType)})
      } else {
        //filePreview.openPreview(getContext(), {title: item.name, uri: '', mimeType: ''})
        showToast('该类型不支持预览')
      }
    }
  }

  async onMenuClick(item: ObjectInfo, type: FileMenuType) {
    console.debug(TAG, 'onMenuClick type: ' + type)
    switch (type){
      case FileMenuType.PREVIEW:
      case FileMenuType.DIR_ENTER:
        this.onItemClick(item)
        break
      case FileMenuType.DETAIL:
        cloudGetObjectDetail(item.id, item.type == 'dir', {
          onSuccess: (data) => {
            this.detailData.isDir = item.type == 'dir'
            this.detailData.name = item.name
            this.detailData.detailInfo = data
            this.showObjectDetail = true
          },
          onFailure: () => {
            showToast('获取详细信息失败')
          }
        })
        break
      case FileMenuType.RENAME:
        break
      case FileMenuType.COPY:
        break
      case FileMenuType.MOVE:
        break
      case FileMenuType.DOWNLOAD:
        break
      case FileMenuType.DELETE:
        break
    }
  }
}