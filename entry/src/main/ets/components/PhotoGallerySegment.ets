import { CloudThemeToken } from '../model/CloudTheme';
import { GallerySegment } from '../model/PhotoGalleryModel';

const SEG_INNER_HEIGHT: number = 40;
const SEG_PADDING: number = 4;

@Component
export struct PhotoGallerySegment {
  @Prop current: GallerySegment = GallerySegment.TIME;
  onSelect: (seg: GallerySegment) => void = () => {};

  @Builder seg(title: string, value: GallerySegment) {
    Text(title)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .height(SEG_INNER_HEIGHT)
      .fontSize(CloudThemeToken.textSizeBodyPlus)
      .fontWeight(this.current === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.current === value ? CloudThemeToken.onPrimary : CloudThemeToken.textSecondary)
      .backgroundColor(this.current === value ? CloudThemeToken.primary : Color.Transparent)
      .borderRadius(SEG_INNER_HEIGHT / 2)
      .onClick(() => { this.onSelect(value); })
  }

  build() {
    Row() {
      this.seg('时间', GallerySegment.TIME)
      this.seg('相册', GallerySegment.ALBUM)
    }
    .width('100%')
    .padding(SEG_PADDING)
    .borderRadius(SEG_INNER_HEIGHT / 2 + SEG_PADDING)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }
}
