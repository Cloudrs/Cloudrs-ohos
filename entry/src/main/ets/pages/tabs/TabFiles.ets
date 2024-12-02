import { DateUtil } from "@pura/harmony-utils";
import { DirectoryInfo, ObjectInfo, Policy, SiteURI } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { FileHeader } from "../../components/FileHeaderComponents";
import { FileTitle } from "../../components/FileTitleComponents";
import { cloudGetFiles } from "../../model/net/Api";
import { showToastTips, ToastType } from "../../utils/ToastUtil";
import { baseUrlGet, cloudGetFile } from "../../utils/AxiosRequest";
import { image } from "@kit.ImageKit";
import { fileUri } from "@kit.CoreFileKit";
import File from "@system.file";

@Extend(Column)
function itemStyle() {
  .borderRadius(7)
  .alignItems(HorizontalAlign.Start)
  .justifyContent(FlexAlign.Center)
  .backgroundColor(Color.White)
}

@Component
export struct TabFiles {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0;
  @State policy: Policy|null = null;
  @State isRoot: boolean = true;
  @State isMorePress: boolean = false;
  private currentPath: string = '/'
  private scrollerForScroll: Scroller = new Scroller()
  private scrollerForList: Scroller = new Scroller()
  private dataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  @State thumbImage: Map<string, PixelMap> = new Map()

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
    this.getFiles(true, '/')
  }

  getDirectoryPath(filePath: string): string {
    // 查找最后一个斜杠的位置
    const lastSlashIndex = filePath.lastIndexOf('/');
    // 如果路径中没有斜杠，返回根目录
    if (lastSlashIndex === -1) {
      return '/';
    }
    // 提取父目录路径
    const directoryPath = filePath.substring(0, lastSlashIndex);
    //console.debug('TabFiles', `filePath:`, filePath, 'dir:', directoryPath)
    return directoryPath === '' ? '/' : directoryPath;
  }

  async getFiles(isRefresh: boolean, path: string) {
    if (isRefresh) {
      this.dataSource.clear()
    }
    cloudGetFiles(path, {
      onSuccess: (data: DirectoryInfo) => {
        if (path === '/') {
          this.isRoot = true
        }
        else {
          this.isRoot = false
        }
        this.currentPath = path
        this.policy = data.policy
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

  async getThumbFile(item: ObjectInfo) {
    if (item.thumb) {
      cloudGetFile(SiteURI.THUMB + '/' + item.id, {
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

  build() {
    Scroll(this.scrollerForScroll) {
      Column() {
        Blank().height(this.sysTopRectHeight)

        Column({ space: 10 }) {
          this.fileHeader()
          this.fileTitle()
        }
        .height(80)
        .margin({top: 20})
        .justifyContent(FlexAlign.Center)

        Grid() {
          LazyForEach(this.dataSource, (item: ObjectInfo, index: number) => {
            GridItem() {
              if (item.type === 'dir') {
                this.directoryItem(item)
              } else if (item.type === 'file') {
                this.fileItem(item)
              }
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
        //如果头部是系统的Tabs组件会自动吸顶的，不需要单独再去List那边监听nestedScroll来实现吸顶效果，可参考EffectDemo1Page
        //父组件和子组件都有滚动的效果
        .nestedScroll({
          //PARENT_FIRST:父组件先滚动，子组件再滚动
          //PARALLEL:父子组件一起滚动
          //SELF_FIRST:子组件先滚动，到了父组件才进行父组件的滚动
          //scrollForward:可滚动组件往末端滚动式嵌套的滚动选项（从下往上滚动）
          scrollForward: NestedScrollMode.PARENT_FIRST,
          //scrollBackward:可滚动组件往起始端滚动时嵌套的滚动选项（从上往下滚动）
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

  @Builder
  fileHeader() {
    Column() {
      Row() {
        Row({ space: 10 }) {
          if (!this.isRoot) {
            Button() {
              Image($r('app.media.ic_back'))
                .padding(5)
                .fillColor(Color.Black)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(Color.White)
            .onClick(async () => {
              await this.getFiles(true, this.getDirectoryPath(this.currentPath))
            })
            .transition(TransitionEffect.OPACITY.animation({duration: 200})
              .combine(TransitionEffect.scale({x: 0, y: 0}).animation({duration: 200})))
          }

          Search({ placeholder: $r("app.string.header_search") })
            .searchIcon({ color: Color.Black })
            .backgroundColor(Color.White)
        }
        .width('50%')

        Row({ space: 10 }) {
          Button() {
            Image($r('app.media.ic_transport'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.light_light_gray'))

          Button() {
            Image($r('app.media.ic_person'))
              .padding(10)
              .fillColor(Color.Black)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.White)
        }
        .width(100)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(36)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding({ left: 10, right: 10 })
    .width('100%')
    .height(40)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  fileTitle() {
    Column({space: 10}) {
      Row() {
        Column() {
          Text($r('app.string.files_main_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)

          Text(this.policy?.name)
            .fontSize(11)
            .fontColor($r('app.color.light_gray'))
        }
        .height(30)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)

        Image($r('app.media.ic_square_more'))
          .padding(5)
          .fillColor(this.isMorePress ? $r('app.color.light_gray') : Color.Black)
          .width(30)
          .height(30)
          .onClick((e) => {
            this.isMorePress = !this.isMorePress
          })
      }
      .padding({left: 20, right: 25})
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(40)
    .align(Alignment.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  directoryItem(item: ObjectInfo) {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.ic_folder_fill'))
          .width(40)
          .height(40)
          .fillColor($r('app.color.file_folder'))

        Column({ space: 3 }) {
          Text(item.name)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd'))
            .fontSize(12)
            .fontColor($r('app.color.light_gray'))
        }
        .layoutWeight(1)
        .height(40)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(60)
    .padding({left: 10, right: 10})
    .itemStyle()
    .onClick(async () => {
      await this.getFiles(true, item.path === '/' ? item.path+item.name : `${item.path}/${item.name}`)
    })
  }

  @Builder
  fileItem(item: ObjectInfo) {
    Column({space: 10}) {
      Text() {
          ImageSpan(item.thumb ? this.getThumbData(item.id) : $r('app.media.ic_doc_text_fill'))
            .objectFit(item.thumb? ImageFit.Cover : ImageFit.CENTER)
      }
      .textAlign(TextAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.file_icon_background'))

      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1)
          .textOverflow({overflow: TextOverflow.Ellipsis})
          .width('100%')

        Text(DateUtil.getFormatDateStr(new Date(item.date), 'yyyy-MM-dd'))
          .fontSize(12)
          .fontColor($r('app.color.light_gray'))
      }
      .height(40)
      .padding({left: 10, right: 10})
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(160)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .itemStyle()
    .onClick(() => {

    })
  }
}