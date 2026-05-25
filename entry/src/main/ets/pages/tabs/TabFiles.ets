import { DirectoryInfo, DirFileInfo, ObjectDetail, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { TabFilesTitle } from "../../components/TabFilesTitle";
import { CloudApi } from "../../model/net/CloudApi";
import { showToast, showToastTips, ToastType } from "../../utils/ToastUtil";
import { image } from "@kit.ImageKit";
import { http } from '@kit.NetworkKit';
import { ObjectItem } from "../../components/ObjectItem";
import { TabFilesHeader } from "../../components/TabFilesHeader";
import { HMRouterMgr } from "@hadss/hmrouter";
import { ImagePreview } from "../../model/Params";
import { ExitLifecycle } from "../../lifecycle/ExitLifecycle";
import { FileMenuType, MoreMenuType, ShowType, SortType } from "../../model/MenuModel";
import { filePreview } from "@kit.PreviewKit";
import { DetailData } from "../../model/DetailData";
import { DetailSheet } from "../../components/DetailSheet";
import { DialogAction, DialogHelper } from "@pura/harmony-dialog";
import { CommonUtil, FileType } from "../../utils/CommonUtil";
import { PathSelectSheet } from "../../components/PathSelectSheet";
import { ObjectCopy, ObjectMove, ObjectSrc } from "../../model/net/ObjectParam";
import { common } from "@kit.AbilityKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { picker } from '@kit.CoreFileKit';
import { FileUtil } from "@pura/harmony-utils";
import { TransportObject } from "../../model/TransportObject";
import { requestDownload } from "../../utils/RequestDownload";
import { FileModel, FileModelState } from "../../model/FileModel";

const TAG = 'TabFiles';

class ObjectSelect {
  index: number = -1
  type: FileMenuType = FileMenuType.COPY
  selectPathTitle: ResourceStr = ''
  selectPathId: string = ''
  copyMoveObjects: ObjectInfo[] = []

  constructor(type?: FileMenuType, selectPathTitle?: ResourceStr, selectPathId?: string, copyMoveObjects?: ObjectInfo[]) {
    if (type) {
      this.type = type;
    }

    if (selectPathTitle) {
      this.selectPathTitle = selectPathTitle;
    }

    if (selectPathId) {
      this.selectPathId = selectPathId;
    }

    if (copyMoveObjects) {
      this.copyMoveObjects = copyMoveObjects;
    }
  }
}

@Component
export struct TabFiles {
  @Link overLap: boolean
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0
  @StorageProp(Constant.TAB_BAR_HEIGHT) tabBarHeight: number = 0;
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
  private objectsInfo: DirFileInfo = new DirFileInfo();
  @State isGridPadding: boolean = false;
  @State showPathSelect: boolean = false
  private objectSelect: ObjectSelect = new ObjectSelect()

  @State downloadingCount: number = 0;
  @State uploadingCount: number = 0;
  @State downloadObjects: LazyDataSource<TransportObject> = new LazyDataSource()
  @State uploadObjects: LazyDataSource<TransportObject> = new LazyDataSource()

  setThumbData(id: string, pixMap: PixelMap) {
    const updated: Map<string, PixelMap> = new Map(this.thumbImage);
    updated.set(id, pixMap);
    this.thumbImage = updated;
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
      CloudApi.getThumb(item.id, {
        onSuccess: async (url: string) => {
          const req = http.createHttp();
          try {
            const resp = await req.request(url, {
              method: http.RequestMethod.GET,
              expectDataType: http.HttpDataType.ARRAY_BUFFER,
            });
            if (resp.responseCode === 200) {
              const imageSource = image.createImageSource(resp.result as ArrayBuffer);
              const pixMap = await imageSource.createPixelMap();
              imageSource.release();
              this.setThumbData(item.id, pixMap);
            }
          } catch (err) {
            console.error(TAG, `Get thumb failed: ${(err as Error)?.message ?? err}`)
          } finally {
            req.destroy();
          }
        },
        onFailure: (msg) => {
          console.error(TAG, `Get thumb failed: ${msg}`)
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
    CloudApi.getFilesInfo(path, {
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
        showToastTips($r('app.string.get_failed'), ToastType.Error)
        //决定是否重新登录
        this.isRefreshing = false
      }
    })
  }

  dataSourceDelete() {
    let objects = this.objectSelect.copyMoveObjects
    if (objects.length > 1) {
      objects.forEach((item) => {
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.dirDataSource.deleteDataByItem(item)
          this.isGridPadding = this.dirDataSource.totalCount() % 2 ? true : false
        } else {
          this.fileDataSource.deleteDataByItem(item)
        }
      })
    } else if (this.objectSelect.index !== -1) {
      if (objects[0].type == Constant.OBJECT_DIR_TYPE) {
        this.dirDataSource.deleteData(this.objectSelect.index)
        this.isGridPadding = this.dirDataSource.totalCount() % 2 ? true : false
      } else {
        this.fileDataSource.deleteData(this.objectSelect.index)
      }
    }
  }

  copyMoveObjects(dst: string) {
    if (this.objectSelect.copyMoveObjects?.length > 0) {
      let src: ObjectSrc = new ObjectSrc()
      this.objectSelect.copyMoveObjects.forEach((item, index) => {
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          src.dirs.push(item.id)
        } else {
          src.items.push(item.id)
        }
      })

      if (this.objectSelect.type == FileMenuType.COPY) {
        let param: ObjectCopy = new ObjectCopy(this.currentPath, src, dst)
        CloudApi.copyObjects(param, {
          onSuccess: (data) => {
            showToast($r('app.string.copy_success'))
          },
          onFailure: (msg) => {
            console.error(TAG, 'copy failed, msg: ' + msg)
            showToast($r('app.string.copy_failed'))
          }
        })
      } else if (this.objectSelect.type == FileMenuType.MOVE) {
        let param: ObjectMove = new ObjectMove(this.currentPath, src, dst)
        CloudApi.moveObjects(param, {
          onSuccess: (data) => {
            this.dataSourceDelete()
            showToast($r('app.string.move_success'))
          },
          onFailure: (msg) => {
            console.error(TAG, 'move failed, msg: ' + msg)
            showToast($r('app.string.move_failed'))
          }
        })
      }
    }
  }

  build() {
    Column() {
      Blank().height(this.sysTopRectHeight)

      Column({ space: 10 }) {
        TabFilesHeader({
          isRoot: this.isRoot,
          downloadObjects: this.downloadObjects,
          downloadingCount: this.downloadingCount,
          uploadObjects: this.uploadObjects,
          uploadingCount: this.uploadingCount,
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
      title: {title: $r('app.string.detail_title')},
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
    .padding({ left: 10, right: 10, bottom: this.tabBarHeight+10 })
    .width('100%')
    .height('100%') //!!!使用lazyforeach必须设置高度才能有效
    .rowsGap(7)
    .columnsGap(7)
    .columnsTemplate(this.showType == ShowType.SHOW_ICON ? '1fr 1fr' : '1fr')
    .edgeEffect(EdgeEffect.Spring, {alwaysEnabled: true})
    .animation({duration: 300})
    .scrollBarWidth(2)
    .bindSheet($$this.showPathSelect, this.selectPathSheet(), {
      showClose: false
    })
  }

  @Builder selectPathSheet() {
    PathSelectSheet({
      title: this.objectSelect.selectPathTitle,
      filterDirId: this.objectSelect.selectPathId,
      onClose: (isFinished: boolean, path?: string) => {
        this.showPathSelect = false
        if (isFinished && path && path != '') {
          console.debug(TAG, 'select path: ' + path)
          this.copyMoveObjects(path)
        }
    }
    })
  }

  @Builder detailSheet() {
    DetailSheet({detailData: this.detailData})
  }

  async onItemClick(item: ObjectInfo) {
    if (item.type == Constant.OBJECT_DIR_TYPE) {
      await this.getFileList(true, CloudApi.getTotalPath(item))
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
      case FileMenuType.MOVE:
        this.objectSelect.index = index
        if (type == FileMenuType.COPY) {
          this.objectSelect.selectPathTitle = $r('app.string.copy_to')
        } else if (type == FileMenuType.MOVE) {
          this.objectSelect.selectPathTitle = $r('app.string.move_to')
        }
        this.objectSelect.type = type
        this.objectSelect.copyMoveObjects.splice(0, this.copyMoveObjects.length)
        this.objectSelect.copyMoveObjects.push(item)
        if (item.type == Constant.OBJECT_DIR_TYPE) {
          this.objectSelect.selectPathId = item.id
        }
        else {
          this.objectSelect.selectPathId = ''
        }
        this.showPathSelect = true
        break
      case FileMenuType.DOWNLOAD:
        this.itemDownload(index, item)
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
    CloudApi.getObjectDetail(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
      onSuccess: (data) => {
        this.detailData.isDir = item.type == Constant.OBJECT_DIR_TYPE
        this.detailData.name = item.name
        this.detailData.detailInfo = data
        this.showObjectDetail = true
      },
      onFailure: (msg) => {
        console.error(TAG, '获取详细信息失败 msg: ' + msg)
        showToast($r('app.string.get_detail_failed'))
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
            CloudApi.renameObject(item.id, content, item.type == Constant.OBJECT_DIR_TYPE, {
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
                // 修改名称需要重新排序
                if (this.sortType == SortType.SORT_BY_NAME) {
                  this.objectsInfo.sortObjects(this.sortType, this.isSortTypeReverse(this.sortType))
                  this.dirDataSource.notifyDataReload()
                  this.fileDataSource.notifyDataReload()
                }
                showToast($r('app.string.rename_success'))
              },
              onFailure: (msg) => {
                console.error(TAG, '重命名失败 msg: ' + msg)
                showToast($r('app.string.rename_failed'))
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
          CloudApi.newObject(path + '/' + content, isDir, {
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
      onAction: (action: number, dialogId: string) => {
        if (action == DialogAction.TWO) {
          CloudApi.deleteObject(item.id, item.type == Constant.OBJECT_DIR_TYPE, {
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
    })
  }

  itemDownload(index: number, item: ObjectInfo) {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      let documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
        let filePath = FileUtil.getFilePath(documentSaveResult[0] + '/' + item.name );
        console.debug(TAG, 'documentViewPicker.save to file succeed and uris are:' + filePath);
        CloudApi.getDownloadUri(item.id, {
          onSuccess: (data) => {
            let url = (data.startsWith('http://') || data.startsWith('https://')) ? data : CloudApi.getBaseURL() + data
            let object: TransportObject = new TransportObject(item, filePath, url)
            this.downloadObjects.pushData(object)
            this.downloadingCount++

            let fileModel: FileModel = new FileModel(item.id, filePath, url, undefined, (trans, state) => {
              object.update(trans, state)
              if (state == FileModelState.COMPLETED) {
                console.debug(TAG, `${context.cacheDir}/${object.item.name} -> ` + filePath)
                FileUtil.moveFile(`${context.cacheDir}/${object.item.name}`, filePath, 0).then(() => {
                  console.debug(TAG, 'move to ' + filePath)
                }).catch((err: BusinessError) => {0
                  console.error(TAG, `err: ${err}`)
                })
                this.downloadingCount--
              }
            })

            // 创建下载任务
            requestDownload.downloadFileBackground(fileModel)
          },
          onFailure: (msg) => {
            console.error(TAG, 'get download uri failed, msg: ' + msg)
          }
        })
      }).catch((err: BusinessError) => {
        console.error(TAG, `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`);
      })
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error(TAG, `Error code: ${err.code}, message: ${err.message}`);
    }
  }
}