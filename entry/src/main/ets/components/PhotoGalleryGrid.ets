import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem } from '../model/PhotoBackupModel';
import {
  PhotoGroup,
  GalleryCell,
  GalleryRenderRow,
  GalleryRowKind,
  buildRenderRows,
  badgeForStatus,
  PhotoBadge
} from '../model/PhotoGalleryModel';
import LazyDataSource from '../utils/LazyDataSource';
import {
  PhotoThumbnailListener,
  PhotoThumbnailStore
} from '../utils/PhotoThumbnailStore';

const ROW_TARGET_HEIGHT: number = 112;
const GAP: number = 3;
const BADGE_SIZE: number = 18;
const BADGE_MARGIN: number = 4;
const BADGE_ICON_SIZE: number = 12;
const BACK_TOP_ROW_THRESHOLD: number = 8;
const FAB_SIZE: number = 46;
const FAB_ICON_SIZE: number = 22;

/**
 * 缩略图状态下沉到单个格子。
 *
 * 列表滚动复用时先同步读取缓存；异步缩略图到达时只更新对应格子，
 * 不会让整张 LazyForEach 因共享 Map 变化而重新求值。
 */
@Component
struct PhotoThumbnail {
  @Prop itemId: string = '';
  @Prop imageWidth: number = 0;
  @Prop imageHeight: number = 0;
  onRequest: () => void = () => {};
  @State pixelMap: PixelMap | undefined = undefined;
  private subscribedId: string = '';
  private listener: PhotoThumbnailListener = (pixelMap: PixelMap) => {
    this.pixelMap = pixelMap;
  };

  aboutToAppear(): void {
    this.subscribedId = this.itemId;
    PhotoThumbnailStore.subscribe(this.subscribedId, this.listener);
    const cached = PhotoThumbnailStore.get(this.subscribedId);
    if (cached) {
      this.pixelMap = cached;
    } else {
      this.onRequest();
    }
  }

  aboutToDisappear(): void {
    if (this.subscribedId.length > 0) {
      PhotoThumbnailStore.unsubscribe(this.subscribedId, this.listener);
      this.subscribedId = '';
    }
  }

  build() {
    if (this.pixelMap) {
      Image(this.pixelMap)
        .width(this.imageWidth)
        .height(this.imageHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(CloudThemeToken.cardRadius)
        .draggable(false)
    } else {
      Column()
        .width(this.imageWidth)
        .height(this.imageHeight)
        .borderRadius(CloudThemeToken.cardRadius)
        .backgroundColor(CloudThemeToken.surfaceSubtle)
    }
  }
}

@Component
export struct PhotoGalleryGrid {
  @Prop @Watch('onGroupsChanged') groups: PhotoGroup[] = [];
  @Prop backupEnabled: boolean = false;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onRequestThumb: (item: PhotoBackupItem) => void = () => {};
  onTapPhoto: (item: PhotoBackupItem) => void = () => {};
  onScroll: (yOffset: number) => void = () => {};
  scroller: Scroller = new Scroller();
  @BuilderParam headerContent: () => void = this.emptyHeader;

  @Builder emptyHeader() {
  }
  @State containerWidth: number = 0;
  @State rowSource: LazyDataSource<GalleryRenderRow> = new LazyDataSource();
  @State showBackTop: boolean = false;
  private collapsed: Set<string> = new Set<string>();

  aboutToAppear(): void {
    this.rebuildRows();
  }

  /** When the grouping dimension changes, drop collapse state (titles no longer apply). */
  onGroupsChanged(): void {
    this.collapsed = new Set<string>();
    this.rebuildRows();
  }

  /** Recompute the flat render-row list. Cheap O(n) over the photo set; runs only on data/width/collapse change. */
  rebuildRows(): void {
    const width = this.containerWidth > 0 ? this.containerWidth : CloudThemeToken.photoBackupGridFallbackWidth;
    this.rowSource.replaceAll(buildRenderRows(this.groups, width, ROW_TARGET_HEIGHT, GAP, this.collapsed));
  }

  private toggleCollapse(title: string): void {
    if (this.collapsed.has(title)) {
      this.collapsed.delete(title);
    } else {
      this.collapsed.add(title);
    }
    this.rebuildRows();
  }

  private badgeOf(item: PhotoBackupItem): PhotoBadge {
    return badgeForStatus(item.status, this.backupEnabled);
  }

  @Builder badge(item: PhotoBackupItem) {
    if (this.badgeOf(item) === PhotoBadge.CLOUD) {
      this.badgeDot($r('app.media.ic_icloud'), 'rgba(0,0,0,0.55)')
    } else if (this.badgeOf(item) === PhotoBadge.UPLOADING) {
      this.badgeDot($r('app.media.ic_arrowshape_up'), CloudThemeToken.primary)
    } else if (this.badgeOf(item) === PhotoBadge.FAILED) {
      this.badgeDot($r('app.media.ic_warn_circle'), CloudThemeToken.danger)
    }
    // NONE: render nothing
  }

  @Builder badgeDot(icon: ResourceStr, fill: ResourceColor) {
    Stack() {
      Circle({ width: BADGE_SIZE, height: BADGE_SIZE })
        .fill(fill)
      Image(icon)
        .width(BADGE_ICON_SIZE)
        .height(BADGE_ICON_SIZE)
        .fillColor(Color.White)
        .objectFit(ImageFit.Contain)
    }
    .width(BADGE_SIZE)
    .height(BADGE_SIZE)
    .margin({ right: BADGE_MARGIN, bottom: BADGE_MARGIN })
  }

  @Builder photoCell(item: PhotoBackupItem, w: number, h: number) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      PhotoThumbnail({
        itemId: item.id,
        imageWidth: w,
        imageHeight: h,
        onRequest: () => { this.onRequestThumb(item); }
      })
      this.badge(item)
    }
    .width(w)
    .height(h)
    .onClick(() => { this.onTapPhoto(item); })
  }

  @Builder sectionHeader(row: GalleryRenderRow) {
    Row({ space: CloudThemeToken.spacingSm }) {
      Image($r('app.media.ic_chevron_down'))
        .width(BADGE_ICON_SIZE)
        .height(BADGE_ICON_SIZE)
        .fillColor(CloudThemeToken.textSecondary)
        .rotate({ angle: row.collapsed ? -90 : 0 })
        .draggable(false)
      Text(row.title)
        .fontSize(CloudThemeToken.textSizeLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(CloudThemeToken.textPrimary)
      Text(row.count.toString())
        .fontSize(CloudThemeToken.textSizeSmall)
        .fontColor(CloudThemeToken.textSecondary)
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.toggleCollapse(row.title); })
  }

  @Builder backTopFab() {
    Button({ type: ButtonType.Circle }) {
      Image($r('app.media.ic_chevron_down'))
        .width(FAB_ICON_SIZE)
        .height(FAB_ICON_SIZE)
        .fillColor(CloudThemeToken.textPrimary)
        .rotate({ angle: 180 })
        .draggable(false)
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .backgroundColor('rgba(150, 150, 150, 0.25)')
    .backdropBlur(18)
    .border({ width: CloudThemeToken.lineWidth, color: CloudThemeToken.line })
    .margin({ right: CloudThemeToken.spacingPage, bottom: this.bottomInset + CloudThemeToken.spacingPage })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => { this.scroller.scrollToIndex(0, true); })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
    List({ space: CloudThemeToken.spacingSection, scroller: this.scroller }) {
      ListItem() {
        Row().width('100%').height(this.topInset)
      }
      ListItem() {
        this.headerContent()
      }
      LazyForEach(this.rowSource, (row: GalleryRenderRow) => {
        ListItem() {
          if (row.kind === GalleryRowKind.HEADER) {
            this.sectionHeader(row)
          } else {
            Row({ space: GAP }) {
              ForEach(row.cells, (cell: GalleryCell) => {
                this.photoCell(cell.item, cell.width, cell.height)
              }, (cell: GalleryCell) => cell.item.id)
            }
            .width('100%')
          }
        }
      }, (row: GalleryRenderRow) => row.key)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: CloudThemeToken.pagePadding,
      right: CloudThemeToken.pagePadding,
      bottom: this.bottomInset + CloudThemeToken.spacingPage
    })
    .cachedCount(3)
    // List 默认按内容区(CONTENT_ONLY)裁剪,底部 padding 区域会裁掉内容;
    // 改为按组件区域裁剪,让照片滚动时能透过悬浮 tabBar 显示(与 Grid 默认行为一致)。
    .clipContent(ContentClipMode.BOUNDARY)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onAreaChange((_o: Area, n: Area) => {
      const w = Number(n.width) - CloudThemeToken.pagePadding * 2;
      if (Math.abs(w - this.containerWidth) > 0.5) {
        this.containerWidth = w;
        this.rebuildRows();
      }
    })
    .onScrollIndex((first: number) => {
      const show = first > BACK_TOP_ROW_THRESHOLD;
      if (show !== this.showBackTop) {
        this.showBackTop = show;
      }
    })
    .onDidScroll(() => {
      this.onScroll(this.scroller.currentOffset().yOffset);
    })

      if (this.showBackTop) {
        this.backTopFab()
      }
    }
    .width('100%')
    .height('100%')
  }
}
