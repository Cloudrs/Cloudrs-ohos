import { DirectoryInfo, DirFileInfo, ObjectDetail, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { TabFilesTitle } from "../../components/TabFilesTitle";
import { CloudApi } from "../../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { image } from "@kit.ImageKit";
import { ObjectItem } from "../../components/ObjectItem";
import { TabFilesHeader } from "../../components/TabFilesHeader";
import { FileUtil } from "@pura/harmony-utils";
import { HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../../model/Params";
import { ExitLifecycle } from "../../lifecycle/ExitLifecycle";
import { FileMenuType, MoreMenuType, ShowType, SortType } from "../../model/MenuModel";
import { filePreview } from "@kit.PreviewKit";
import { DetailData } from "../../model/DetailData";
import { DetailSheet } from "../../components/DetailSheet";
import { DialogAction, DialogHelper } from "@pura/harmony-dialog";
import { CommonUtil, FileType } from "../../utils/CommonUtil";

const TAG = 'TabFiles';

@Component
export struct TabFiles {
  @Link overLap: boolean
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.CURRENT_SHOW_TYPE) showType: ShowType = ShowType.SHOW_ICON
  @StorageProp(Constant.CURRENT_SORT_TYPE) sortType: SortType = SortType.SORT_BY_NAME
  @StorageProp(Constant.CURRENT_SORT_TYPE_RESERVE) sortTypeReverse: Map<SortType, boolean> = new Map([])
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
  @State dirDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  @State fileDataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()
  @State isGridLast: boolean = false
  @State bottomPadding: number = 80;
  @State objectsInfo: DirFileInfo = new DirFileInfo();
  @State isGridPadding: boolean = false;

  setThumbData(id: string, pixMap: PixelMap) {
    this.thumbImage.set(id, pixMap)
  }

  getThumbData(id: string): PixelMap|undefined {
    if (this.thumbImage.has(id)) {
      return this.thumbImage.get(id)
    }
    return undefined
  }

  isSortTypeReverse(type: SortType): boolean {
    if (this.sortTypeReverse.has(type)) {
      return this.sortTypeReverse.get(type)!
    }
    return false
  }

  onBackPressedCallback(): boolean {
    console.debug(TAG, 'onBackPressedCallback ....')
    if (this.currentPath === '/') {
      return false
    }

    this.getFileList(true, CommonUtil.getDirectoryPath((this.currentPath)))
    return true
  }

  aboutToAppear() {
    this.fileDataSource.onDataGet = (index: number, item: ObjectInfo) => {
      //console.debug(TAG, `onDataGet: index:${index}`)
      this.getThumbFile(index, item)
    }
    (HMRouterMgr.getCurrentLifecycleOwner()?.getLifecycle() as ExitLifecycle).onBackPressedCallback = this.onBackPressedCallback.bind(this)
    this.getFileList(true, '/')
  }

  async getThumbFile(index: number, item: ObjectInfo) {
    if (item.thumb && !this.getThumbData(item.id)) {
      CloudApi.cloudGetThumb(item.id, {
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
    this.mainTitle = this.isRoot ? $r('app.string.files_main_title') : CommonUtil.getLastDirectoryName(path)
    CloudApi.cloudGetFilesInfo(path, {
      onStart: () => {
        if (isRefresh) {
          this.dirDataSource.clear()
          this.fileDataSource.clear()
          this.thumbImage.clear()
          this.scrollerForList.scrollEdge(Edge.Start)
        }
      },
      onSuccess: (data: DirectoryInfo) => {
        this.subTitle = data.policy.name
        this.objectsInfo = new DirFileInfo(data.parent, data.objects, data.policy)
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.dirDataSource.dataArray = this.objectsInfo.dirObjects
        this.dirDataSource.notifyDataReload()
        this.isGridPadding = this.dirDataSource.totalCount()%2 ? true : false
        this.fileDataSource.dataArray = this.objectsInfo.fileObjects
        this.fileDataSource.notifyDataReload()
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
            await this.getFileList(true, CommonUtil.getDirectoryPath(this.currentPath))
          })
        })
        TabFilesTitle({ mainTitle: this.mainTitle, subTitle: this.subTitle, onMoreClick: this.onMoreClick.bind(this)})
      }
      .height(80)
      .margin({top: 20})
      .justifyContent(FlexAlign.Center)

      Refresh({refreshing: $$this.isRefreshing}) {
        this.objectGrid()
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
    .bindSheet($$this.showObjectDetail, this.detailSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      backgroundColor: Color.White,
      title: {title: $r('app.string.detail_title')}
    })
  }

  @Builder objectGrid() {
    Grid(this.scrollerForList) {
      LazyForEach(this.dirDataSource, (item: ObjectInfo, index: number) => {
        GridItem() {
          ObjectItem({ index, item, showType: this.showType,
            onMenuClick : (async (item, type) => {
              await this.onMenuClick(index, item, type)
            })
          })
        }
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)

      /*文件夹奇数时最后一个填充一个空成员*/
      if (this.showType == ShowType.SHOW_ICON && this.isGridPadding) {
        GridItem()
      }

      LazyForEach(this.fileDataSource, (item: ObjectInfo, index: number) => {
        GridItem() {
          ObjectItem({ index, item, showType: this.showType,
            onMenuClick : (async (item, type) => {
              await this.onMenuClick(index, item, type)
            })
          })
        }
        .onClick(async () => {
          this.onItemClick(item)
        })
      }, (item: ObjectInfo, index: number) => item.id)
    }
    .cachedCount(5)
    .maxCount(2)
    .padding({ left: 10, right: 10, bottom: this.bottomPadding })
    .width('100%')
    .height('100%') //!!!使用lazyforeach必须设置高度才能有效
    .rowsGap(7)
    .columnsGap(7)
    .columnsTemplate(this.showType == ShowType.SHOW_ICON ? '1fr 1fr' : '1fr')
    .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
    .animation({duration: 300})
    .scrollBarWidth(2)
    .onScrollIndex((first, last) => {
      console.debug(TAG, `first: ${first}, last: ${last}`)
      if (last == -1) {
        return
      }
      if (last == this.dirDataSource.totalCount()+this.fileDataSource.totalCount()-(this.isGridPadding ? 1 : 0)) {
        this.isGridLast = true
      } else {
        this.isGridLast = false
      }
    })
    .onScrollFrameBegin((offset, state) => {
      if (this.isGridLast && offset != 0) {
        if (this.bottomPadding + offset > 80) {
          this.bottomPadding = 80
        } else if (this.bottomPadding + offset < 0) {
          this.bottomPadding = 0
        } else {
          this.bottomPadding += offset
        }
      }
      return {offsetRemain: offset}
    })
  }

  @Builder detailSheet() {
    DetailSheet({detailData: this.detailData})
  }

  async onItemClick(item: ObjectInfo) {
    if (item.type == Constant.OBJECT_DIR_TYPE) {
      await this.getFileList(true,
        item.path === '/' ? item.path + item.name : `${item.path}/${item.name}`)
    }
    else {
      let fileType = CommonUtil.getFileType(item.name)
      let fileExtension = CommonUtil.getFileExtention(item.name)
      if (fileType == FileType.IMAGE) {
        HMRouterMgr.push({pageUrl: Constant.IAMGE_PREVIEW_PAGE, param: new ImagePreview(item.name, item.id, fileExtension)})
      } else {
        //filePreview.openPreview(getContext(), {title: item.name, uri: '', mimeType: ''})
        showToast('该类型不支持预览')
      }
    }
  }

  async onMenuClick(index: number, item: ObjectInfo, type: FileMenuType) {
    console.debug(TAG, 'onMenuClick type: ' + type)
    switch (type){
      case FileMenuType.PREVIEW:
      case FileMenuType.DIR_ENTER:
        this.onItemClick(item)
        break
      case FileMenuType.DETAIL:
        this.itemDetail(item)
        break
      case FileMenuType.RENAME:
        this.itemRename(index, item)
        break
      case FileMenuType.COPY:
        break
      case FileMenuType.MOVE:
        break
      case FileMenuType.DOWNLOAD:
        break
      case FileMenuType.DELETE:
        this.itemDelete(index, item)
        break
    }
  }

  onMoreClick(type: MoreMenuType, isReserve?: boolean) {
    console.debug(TAG, 'onMoreClick type: ' + type)
    switch (type){
      case MoreMenuType.MULTI_SELECT:

        break;
      case MoreMenuType.SHOW_ICON:
        break
      case MoreMenuType.SHOW_LIST:
        break
      case MoreMenuType.SORT_BY_NAME:
      case MoreMenuType.SORT_BY_TYPE:
      case MoreMenuType.SORT_BY_TIME:
      case MoreMenuType.SORT_BY_SIZE:
        this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
        this.dirDataSource.notifyDataReload()
        this.fileDataSource.notifyDataReload()
        break
      case MoreMenuType.NEW_DIR:
        this.itemNew(this.currentPath, true)
        break
      case MoreMenuType.NEW_FILE:
        this.itemNew(this.currentPath, false)
        break
      case MoreMenuType.UPLOAD_FILE:
        break
    }
  }

  itemDetail(item: ObjectInfo) {
    CloudApi.cloudGetObjectDetail(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        this.detailData.isDir = item.type == Constant.OBJECT_DIR_TYPE
        this.detailData.name = item.name
        this.detailData.detailInfo = data
        this.showObjectDetail = true
      },
      onFailure: (msg) => {
        console.error(TAG, '获取详细信息失败 msg: ' + msg)
        showToast('获取详细信息失败')
      }
    })
  }

  itemRename(index: number, item: ObjectInfo) {
    DialogHelper.showTextInputDialog({
      primaryTitle: $r('app.string.rename'),
      text: item.name,
      onAction: (action: number, dialogId: string, content: string) => {
        if (action == DialogAction.TWO) {
          console.debug(TAG, `action: ${action}, content: ${content}`)
          if (item.name != content) {
            CloudApi.cloudRenameObject(item.id, content, item.type == Constant.OBJECT_DIR_TYPE, {
              onSuccess: (data) => {
                item.name = content
                if (item.type == Constant.OBJECT_DIR_TYPE) {
                  console.info(TAG, 'index dir ' + index)
                  this.dirDataSource.deleteData(index)
                  this.dirDataSource.addData(index, item)
                } else {
                  console.info(TAG, 'index file ' + index)
                  this.fileDataSource.deleteData(index)
                  this.fileDataSource.addData(index, item)
                }
                showToast('重命名成功')
              },
              onFailure: (msg) => {
                console.error(TAG, '重命名失败 msg: ' + msg)
                showToast('重命名失败')
              }
            })
          }
        }
      }
    })
  }

  itemNew(path: string, isDir: boolean) {
    DialogHelper.showTextInputDialog({
      primaryTitle: isDir ? $r('app.string.more_new_dir') : $r('app.string.more_new_file'),
      text: '',
      placeholder: isDir ? $r('app.string.new_dir_placeholder') : $r('app.string.new_file_placeholder'),
      onAction: (action: number, dialogId: string, content: string) => {
        if (action == DialogAction.TWO) {
          console.debug(TAG, `新建 content: ${content}`)
          CloudApi.cloudNewObject(path + '/' + content, isDir, {
            onSuccess: (data) => {
              this.getFileList(true, this.currentPath)
              showToast(`新建${content}成功`)
            },
            onFailure: (msg) => {
              console.error(TAG, '新建文件/文件夹失败 msg: ' + msg)
              showToast(`新建${content}失败`)
            }
          })
        }
      }
    })
  }

  itemDelete(index: number, item: ObjectInfo) {
    DialogHelper.showAlertDialog({
      primaryTitle:  $r('app.string.delete_confirm'),
      content: item.name,
      primaryButton: {value: $r('app.string.dialog_cancel')},
      secondaryButton: {value: $r('app.string.dialog_delete'), role: ButtonRole.ERROR},
      onAction: (action: number, dialogId: string, content: string) => {
        if (action == DialogAction.TWO) {
          console.debug(TAG, `action: ${action}, content: ${content}`)
          if (item.name != content) {
            CloudApi.cloudDeleteObject(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
              onSuccess: (data) => {
                if (item.type == Constant.OBJECT_DIR_TYPE) {
                  this.dirDataSource.deleteData(index)
                  this.isGridPadding = this.dirDataSource.totalCount()%2 ? true : false
                } else {
                  this.fileDataSource.deleteData(index)
                }
                showToast($r('app.string.delete_success'))
              },
              onFailure: (msg) => {
                console.error(TAG, '删除失败 msg: ' + msg)
                showToast($r('app.string.delete_failed'))
              }
            })
          }
        }
      }
    })
  }
}