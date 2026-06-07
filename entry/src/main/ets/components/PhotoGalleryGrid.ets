import { CloudThemeToken } from '../model/CloudTheme';
import { PhotoBackupItem, PhotoBackupStatus } from '../model/PhotoBackupModel';
import { PhotoGroup, JustifiedRow, justifyRows, badgeForStatus, PhotoBadge } from '../model/PhotoGalleryModel';

const ROW_TARGET_HEIGHT: number = 112;
const GAP: number = 3;
const BADGE_SIZE: number = 18;
const BADGE_MARGIN: number = 4;
const BADGE_ICON_SIZE: number = 12;

@Component
export struct PhotoGalleryGrid {
  @Prop groups: PhotoGroup[] = [];
  @Prop backupEnabled: boolean = false;
  @Consume photoBackupThumbs: Map<string, PixelMap>;
  onRequestThumb: (item: PhotoBackupItem) => void = () => {};
  onTapPhoto: (item: PhotoBackupItem) => void = () => {};
  @State containerWidth: number = 0;

  private ratioOf(_item: PhotoBackupItem): number {
    return 1; // thumbnails are square; uniform 1:1 ratio
  }

  private badgeOf(item: PhotoBackupItem): PhotoBadge {
    return badgeForStatus(item.status, this.backupEnabled);
  }

  @Builder badge(item: PhotoBackupItem) {
    if (this.badgeOf(item) === PhotoBadge.CLOUD) {
      Stack() {
        Circle({ width: BADGE_SIZE, height: BADGE_SIZE })
          .fill('rgba(0,0,0,0.55)')
        Image($r('app.media.ic_icloud'))
          .width(BADGE_ICON_SIZE)
          .height(BADGE_ICON_SIZE)
          .fillColor(Color.White)
          .objectFit(ImageFit.Contain)
      }
      .width(BADGE_SIZE)
      .height(BADGE_SIZE)
      .margin({ right: BADGE_MARGIN, bottom: BADGE_MARGIN })
    } else if (this.badgeOf(item) === PhotoBadge.UPLOADING) {
      Stack() {
        Circle({ width: BADGE_SIZE, height: BADGE_SIZE })
          .fill(CloudThemeToken.primary)
        Image($r('app.media.ic_arrowshape_up'))
          .width(BADGE_ICON_SIZE)
          .height(BADGE_ICON_SIZE)
          .fillColor(Color.White)
          .objectFit(ImageFit.Contain)
      }
      .width(BADGE_SIZE)
      .height(BADGE_SIZE)
      .margin({ right: BADGE_MARGIN, bottom: BADGE_MARGIN })
    } else if (this.badgeOf(item) === PhotoBadge.FAILED) {
      Stack() {
        Circle({ width: BADGE_SIZE, height: BADGE_SIZE })
          .fill(CloudThemeToken.danger)
        Image($r('app.media.ic_warn_circle'))
          .width(BADGE_ICON_SIZE)
          .height(BADGE_ICON_SIZE)
          .fillColor(Color.White)
          .objectFit(ImageFit.Contain)
      }
      .width(BADGE_SIZE)
      .height(BADGE_SIZE)
      .margin({ right: BADGE_MARGIN, bottom: BADGE_MARGIN })
    }
    // NONE: render nothing
  }

  @Builder photoCell(item: PhotoBackupItem, w: number, h: number) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.photoBackupThumbs.has(item.id)) {
        Image(this.photoBackupThumbs.get(item.id))
          .width(w)
          .height(h)
          .objectFit(ImageFit.Cover)
          .borderRadius(CloudThemeToken.cardRadius)
          .draggable(false)
      } else {
        Column()
          .width(w)
          .height(h)
          .borderRadius(CloudThemeToken.cardRadius)
          .backgroundColor(CloudThemeToken.surfaceSubtle)
          .onAppear(() => { this.onRequestThumb(item); })
      }
      this.badge(item)
    }
    .width(w)
    .height(h)
    .onClick(() => { this.onTapPhoto(item); })
  }

  build() {
    List({ space: CloudThemeToken.spacingSection }) {
      ForEach(this.groups, (group: PhotoGroup) => {
        ListItem() {
          Column({ space: GAP }) {
            Text(group.title)
              .fontSize(CloudThemeToken.textSizeBody)
              .fontWeight(FontWeight.Bold)
              .fontColor(CloudThemeToken.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)
            ForEach(
              justifyRows(
                group.items.map((it: PhotoBackupItem) => this.ratioOf(it)),
                this.containerWidth > 0 ? this.containerWidth : CloudThemeToken.photoBackupGridFallbackWidth,
                ROW_TARGET_HEIGHT,
                GAP
              ),
              (row: JustifiedRow) => {
                Row({ space: GAP }) {
                  ForEach(row.widths, (w: number, i: number) => {
                    this.photoCell(group.items[row.startIndex + i], w, row.height)
                  })
                }
                .width('100%')
              }
            )
          }
          .width('100%')
        }
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onAreaChange((_o: Area, n: Area) => { this.containerWidth = Number(n.width); })
  }
}
