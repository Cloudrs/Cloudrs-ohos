/**
 * 可缩放图片组件:双指捏合/双击缩放、放大后单指平移,PC 端支持鼠标滚轮以光标为中心缩放。
 * 缩放跟手与边界钳制公式参考官方最佳实践《图片预览器》(bpta-picture-preview)。
 */

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2;
const WHEEL_ZOOM_STEP: number = 1.15;
const ZOOM_ANIMATION_MS: number = 200;
const ZOOMED_EPSILON: number = 1.001;
// 未放大时把 Pan 触发距离调大,让 Swiper 翻页手势先识别成功;放大后调小以便平移立即跟手。
const PAN_DISTANCE_ZOOMED: number = 3;
const PAN_DISTANCE_IDLE: number = 50;

@Component
export struct ZoomableImage {
  imageSource: PixelMap | ResourceStr | undefined = undefined;
  imageDraggable: boolean = false;
  // 系统 AI 识图(长按抠主体,动画与菜单均为系统内置);设备不支持或用户关闭时传 false。
  enableAiAnalyzer: boolean = false;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  onZoomChange: (zoomed: boolean) => void = () => {};
  // 单击回调与双击缩放在同一手势组内互斥判定,避免宿主页面用 onClick 时双击被当成两次单击。
  onSingleTap: (() => void) | undefined = undefined;
  onImageError: () => void = () => {};

  @State curScale: number = 1;
  @State curOffsetX: number = 0;
  @State curOffsetY: number = 0;
  @State isZoomed: boolean = false;
  private lastScale: number = 1;
  private lastOffsetX: number = 0;
  private lastOffsetY: number = 0;
  // 缩放中心的百分比位置(官方公式中的 1 - c 形式,0.5 表示图片中心)。
  private pinchCenterRatioX: number = 0.5;
  private pinchCenterRatioY: number = 0.5;
  private pinchStartCenterX: number = 0;
  private pinchStartCenterY: number = 0;
  private componentWidth: number = 0;
  private componentHeight: number = 0;
  // 主体分割 + 文字识别(长按选字复制);不开 OBJECT_LOOKUP(识图搜索),避免额外预分析功耗。
  private aiOptions: ImageAIOptions = { types: [ImageAnalyzerType.SUBJECT, ImageAnalyzerType.TEXT] };
  // 图片原始宽高比,由 onComplete 获取;fit 尺寸(scale=1 时 Contain 后的显示尺寸)据此推算。
  private imageRatio: number = 0;

  onActiveChanged(): void {
    if (!this.isActive) {
      this.resetZoom(false);
    }
  }

  private fitWidth(): number {
    if (this.imageRatio <= 0 || this.componentWidth <= 0 || this.componentHeight <= 0) {
      return this.componentWidth;
    }
    return Math.min(this.componentWidth, this.componentHeight * this.imageRatio);
  }

  private fitHeight(): number {
    if (this.imageRatio <= 0) {
      return this.componentHeight;
    }
    return this.fitWidth() / this.imageRatio;
  }

  /** 按当前缩放值钳制平移范围:超出屏幕方向可移动,未超出方向强制居中。 */
  private clampOffsets(): void {
    const scaledWidth = this.fitWidth() * this.curScale;
    const scaledHeight = this.fitHeight() * this.curScale;
    if (scaledWidth > this.componentWidth) {
      const maxOffsetX = (scaledWidth - this.componentWidth) / 2;
      this.curOffsetX = Math.max(-maxOffsetX, Math.min(maxOffsetX, this.curOffsetX));
    } else {
      this.curOffsetX = 0;
    }
    if (scaledHeight > this.componentHeight) {
      const maxOffsetY = (scaledHeight - this.componentHeight) / 2;
      this.curOffsetY = Math.max(-maxOffsetY, Math.min(maxOffsetY, this.curOffsetY));
    } else {
      this.curOffsetY = 0;
    }
  }

  /** 计算手势中心相对图片内容的百分比位置,存为公式所需的 (1 - c) 形式。 */
  private evaluateCenter(centerX: number, centerY: number): void {
    const displayWidth = this.fitWidth() * this.lastScale;
    const displayHeight = this.fitHeight() * this.lastScale;
    if (displayWidth <= 0 || displayHeight <= 0) {
      this.pinchCenterRatioX = 0.5;
      this.pinchCenterRatioY = 0.5;
      return;
    }
    const imgX = (this.componentWidth - displayWidth) / 2 + this.lastOffsetX;
    const imgY = (this.componentHeight - displayHeight) / 2 + this.lastOffsetY;
    const cX = Math.min(1, Math.max((centerX - imgX) / displayWidth, 0));
    const cY = Math.min(1, Math.max((centerY - imgY) / displayHeight, 0));
    this.pinchCenterRatioX = 1 - cX;
    this.pinchCenterRatioY = 1 - cY;
  }

  /** 缩放跟手:以手势中心为基准更新缩放值与偏移(offX/offY 为本次手势的平移分量)。 */
  private applyScale(scale: number, offX: number, offY: number): void {
    this.curScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.lastScale * scale));
    const effectiveScale = this.curScale / this.lastScale;
    this.curOffsetX = (this.lastOffsetX + offX) +
      (0.5 - this.pinchCenterRatioX) * this.fitWidth() * (1 - effectiveScale) * this.lastScale;
    this.curOffsetY = (this.lastOffsetY + offY) +
      (0.5 - this.pinchCenterRatioY) * this.fitHeight() * (1 - effectiveScale) * this.lastScale;
    this.clampOffsets();
  }

  private commitGesture(): void {
    this.lastScale = this.curScale;
    this.lastOffsetX = this.curOffsetX;
    this.lastOffsetY = this.curOffsetY;
    this.notifyZoomState();
  }

  private notifyZoomState(): void {
    const zoomed = this.curScale > ZOOMED_EPSILON;
    if (zoomed !== this.isZoomed) {
      this.isZoomed = zoomed;
      this.onZoomChange(zoomed);
    }
  }

  private resetZoom(animated: boolean): void {
    const apply = () => {
      this.curScale = 1;
      this.curOffsetX = 0;
      this.curOffsetY = 0;
    };
    if (animated) {
      this.getUIContext().animateTo({ duration: ZOOM_ANIMATION_MS }, apply);
    } else {
      apply();
    }
    this.lastScale = 1;
    this.lastOffsetX = 0;
    this.lastOffsetY = 0;
    this.notifyZoomState();
  }

  /** 双击:未放大时以点击点为中心放大,已放大时还原。 */
  private toggleDoubleTapZoom(tapX: number, tapY: number): void {
    if (this.curScale > ZOOMED_EPSILON) {
      this.resetZoom(true);
      return;
    }
    this.evaluateCenter(tapX, tapY);
    this.getUIContext().animateTo({ duration: ZOOM_ANIMATION_MS }, () => {
      this.applyScale(DOUBLE_TAP_SCALE, 0, 0);
    });
    this.commitGesture();
  }

  /** 滚轮/触控板缩放:以光标位置为中心按固定步进缩放。 */
  private wheelZoom(zoomIn: boolean, cursorX: number, cursorY: number): void {
    this.evaluateCenter(cursorX, cursorY);
    this.applyScale(zoomIn ? WHEEL_ZOOM_STEP : 1 / WHEEL_ZOOM_STEP, 0, 0);
    this.commitGesture();
  }

  build() {
    Column() {
      Image(this.imageSource, this.aiOptions)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .enableAnalyzer(this.enableAiAnalyzer)
        .draggable(this.imageDraggable)
        .scale({ x: this.curScale, y: this.curScale })
        .translate({ x: this.curOffsetX, y: this.curOffsetY })
        .onComplete((event) => {
          if (event && event.width > 0 && event.height > 0) {
            this.imageRatio = event.width / event.height;
          }
        })
        .onError(() => {
          this.onImageError();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .clip(true)
    .onAreaChange((_o: Area, n: Area) => {
      this.componentWidth = Number(n.width);
      this.componentHeight = Number(n.height);
      this.clampOffsets();
    })
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture({ count: 2 })
        .onAction((event: GestureEvent) => {
          const finger = event.fingerList[0];
          if (finger) {
            this.toggleDoubleTapZoom(finger.localX, finger.localY);
          }
        }),
      PinchGesture({ fingers: 2, distance: 1 })
        .onActionStart((event: GestureEvent) => {
          this.evaluateCenter(event.pinchCenterX, event.pinchCenterY);
          this.pinchStartCenterX = event.pinchCenterX;
          this.pinchStartCenterY = event.pinchCenterY;
        })
        .onActionUpdate((event: GestureEvent) => {
          // 捏合的平移分量取双指中心的位移,实现缩放同时可拖动。
          this.applyScale(event.scale,
            event.pinchCenterX - this.pinchStartCenterX,
            event.pinchCenterY - this.pinchStartCenterY);
        })
        .onActionEnd(() => {
          this.commitGesture();
        }),
      PanGesture({
        fingers: 1,
        direction: PanDirection.All,
        distance: this.isZoomed ? PAN_DISTANCE_ZOOMED : PAN_DISTANCE_IDLE
      })
        .onActionUpdate((event: GestureEvent) => {
          if (this.lastScale <= ZOOMED_EPSILON) {
            return;
          }
          this.curOffsetX = this.lastOffsetX + event.offsetX;
          this.curOffsetY = this.lastOffsetY + event.offsetY;
          this.clampOffsets();
        })
        .onActionEnd(() => {
          this.commitGesture();
        }),
      TapGesture({ count: 1 })
        .onAction(() => {
          if (this.onSingleTap) {
            this.onSingleTap();
          }
        })
    ))
    .onAxisEvent((event: AxisEvent) => {
      if (event.action !== AxisAction.UPDATE) {
        return;
      }
      const vertical = event.getVerticalAxisValue();
      if (vertical === 0) {
        return;
      }
      // 滚轮向上滚动时垂直轴值为负,对应放大。
      this.wheelZoom(vertical < 0, event.x, event.y);
    })
  }
}
