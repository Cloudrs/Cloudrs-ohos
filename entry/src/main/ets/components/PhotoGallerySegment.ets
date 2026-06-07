import { CloudThemeToken } from '../model/CloudTheme';
import { GallerySegment } from '../model/PhotoGalleryModel';

@Component
export struct PhotoGallerySegment {
  @Prop current: GallerySegment = GallerySegment.TIME;
  onSelect: (seg: GallerySegment) => void = () => {};

  @Builder seg(title: string, value: GallerySegment) {
    Text(title)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .height(CloudThemeToken.rowHeight2xl)
      .fontSize(CloudThemeToken.textSizeBody)
      .fontWeight(this.current === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.current === value ? CloudThemeToken.onPrimary : CloudThemeToken.textSecondary)
      .backgroundColor(this.current === value ? CloudThemeToken.primary : Color.Transparent)
      .borderRadius(CloudThemeToken.controlRadiusRoundMd)
      .onClick(() => { this.onSelect(value); })
  }

  build() {
    Row() {
      this.seg('时间', GallerySegment.TIME)
      this.seg('相册', GallerySegment.ALBUM)
    }
    .width('100%')
    .padding(CloudThemeToken.spacingXs)
    .borderRadius(CloudThemeToken.controlRadiusRoundXl)
    .backgroundColor(CloudThemeToken.surfaceSubtle)
  }
}
