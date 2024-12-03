import { DirectoryInfo, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { TabFilesTitle } from "../../components/TabFilesTitle";
import { cloudGetFilesInfo, cloudGetThumb } from "../../model/net/Api";
import { showToastTips, ToastType } from "../../utils/ToastUtil";
import { image } from "@kit.ImageKit";
import { FileItem } from "../../components/FileItem";
import { TabFilesHeader } from "../../components/TabFilesHeader";
import { FileMenu } from "../../components/FileMenu";
import { LengthMetrics } from "@kit.ArkUI";

@Component
export struct TabFiles {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @State policy: Policy|null = null
  @State isRoot: boolean = true
  @State mainTitle: string|Resource = $r('app.string.files_main_title')
  @State subTitle: string|Resource = $r('app.string.files_sub_title')
  @Provide thumbImage: Map<string, PixelMap> = new Map()
  private currentPath: string = '/'
  private scrollerForScroll: Scroller = new Scroller()
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

  aboutToAppear() {
    this.getFileList(true, '/')
  }

  getDirectoryPath(filePath: string): string {
    const lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex === -1) {
      return '/';
    }
    const directoryPath = filePath.substring(0, lastSlashIndex);
    //console.debug('TabFiles', `filePath:`, filePath, 'dir:', directoryPath)
    return directoryPath === '' ? '/' : directoryPath;
  }

  getLastDirectoryName(filePath: string): string {
    // 分割路径并去除空字符串
    const parts = filePath.split('/').filter(part => part !== '');
    // console.debug('TabFiles', `split:` + JSON.stringify(parts))
    const lastDirectoryName = parts.length >= 1 ? parts[parts.length - 1] : '/';
    return lastDirectoryName;
  }

  async getThumbFile(item: ObjectInfo) {
    if (item.thumb) {
      cloudGetThumb(item.id, {
        onSuccess: (data: ArrayBuffer) => {
          let imageSource: image.ImageSource = image.createImageSource(data)
          imageSource.createPixelMap().then((pixMap: PixelMap) => {
            this.setThumbData(item.id, pixMap)
          })
        },
        onFailure: (msg) => {

        }
      })
    }
  }

  async getFileList(isRefresh: boolean, path: string) {
    if (isRefresh) {
      this.thumbImage.clear()
      this.dataSource.clear()
    }
    if (path === '/') {
      this.isRoot = true
    }
    else {
      this.isRoot = false
    }
    this.currentPath = path
    this.mainTitle = this.isRoot ? $r('app.string.files_main_title') : this.getLastDirectoryName(path)
    cloudGetFilesInfo(path, {
      onSuccess: (data: DirectoryInfo) => {
        this.policy = data.policy
        this.subTitle = this.policy.name
        data.objects.forEach((value: ObjectInfo, index: number) => {
          if (value.thumb) {
            this.getThumbFile(value)
          }
          this.dataSource.pushData(value)
        })
      },
      onFailure: (msg) => {
        showToastTips('获取文件失败', ToastType.Error)
        //决定是否重新登录
      }
    })
  }

  build() {
    Scroll(this.scrollerForScroll) {
      Column() {
        Blank().height(this.sysTopRectHeight)

        Column({ space: 10 }) {
          TabFilesHeader({
            isRoot: this.isRoot,
            onBackClick: async () => {
              await this.getFileList(true, this.getDirectoryPath(this.currentPath))
            }
          })
          TabFilesTitle({ mainTitle: this.mainTitle, subTitle: this.subTitle})
        }
        .height(80)
        .margin({top: 20})
        .justifyContent(FlexAlign.Center)

        Grid(this.scrollerForList) {
          LazyForEach(this.dataSource, (item: ObjectInfo, index: number) => {
            GridItem() {
              FileItem({
                item,
                onItemClick: async (item) => {
                  await this.getFileList(true, item.path === '/' ? item.path+item.name : `${item.path}/${item.name}`)
                }
              })
            }
          }, (item: ObjectInfo, index: number) => JSON.stringify(item) + index)
        }
        .maxCount(2)
        .padding(10)
        .width('100%')
        .margin({ top: 20 })
        .layoutWeight(1)
        .rowsGap(10)
        .columnsGap(10)
        .columnsTemplate('1fr 1fr')
        .edgeEffect(EdgeEffect.None)
        .friction(0.6)
        .scrollBarWidth(2)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST,
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.nav_background'))
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}