import { DateUtil } from "@pura/harmony-utils";
import { DirectoryInfo, ObjectInfo, Policy } from "../../model/net/ApiTypes";
import Constant from "../../model/Constant";
import LazyDataSource from "../../utils/LazyDataSource";
import { FileHeader } from "../../components/FileHeaderComponents";
import { FileTitle } from "../../components/FileTitleComponents";
import { cloudGetFiles } from "../../model/net/Api";
import { showToastTips, ToastType } from "../../utils/ToastUtil";
import { FileItemComponents } from "../../components/FileItemComponents";

@Component
export struct TabFiles {
  @StorageProp(Constant.SYSTEM_TOP_RECT_HEIGHT) sysTopRectHeight: number = 0;
  @State policy: Policy|null = null;
  @State isRoot: boolean = true;
  private scrollerForScroll: Scroller = new Scroller()
  private scrollerForList: Scroller = new Scroller()
  private dataSource: LazyDataSource<ObjectInfo> = new LazyDataSource()

  aboutToAppear() {
    this.getFiles(true, '/')
  }

  getFiles(isRefresh: boolean, path: string) {
    cloudGetFiles(path, {
      onSuccess: (data: DirectoryInfo) => {
        this.policy = data.policy
        data.objects.forEach((value: ObjectInfo) => {
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
          FileHeader({ isRoot: this.isRoot })
            .height(40)
            .align(Alignment.Center)
          FileTitle({ mainTitle: $r('app.string.files_main_title'), subTitle: this.policy?.name })
            .height(40)
            .align(Alignment.Center)
        }
        .height(80)
        .margin({top: 20})
        .justifyContent(FlexAlign.Center)

        Grid(this.scrollerForList) {
          LazyForEach(this.dataSource, (item: ObjectInfo, index: number) => {
            GridItem() {
              FileItemComponents({item: item})
            }
          }, (item: ObjectInfo, index: number) => JSON.stringify(item) + index)
        }
        .maxCount(2)
        .padding(10)
        .width('100%')
        .margin({top: 20})
        .layoutWeight(1)
        .rowsGap(10)
        .columnsGap(10)
        .columnsTemplate('1fr 1fr')
        .edgeEffect(EdgeEffect.None)
        .friction(0.6)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.nav_background'))
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }
}