import { window } from '@kit.ArkUI';

@Entry
struct BottomPopsUpAsTheTopOfKeyboard {
  scroller: Scroller = new Scroller();
  private arr: number[] = [0];
  @State scrollHeight: number = 0;
  @State isRebuild: boolean = false;
  @State keyHeight: number = 0;
  @State text: string = '';
  aboutToAppear() {
    window.getLastWindow(getContext(this)).then(currentWindow => {
      // 设置窗口的布局为沉浸式布局
      currentWindow.setWindowLayoutFullScreen(true);
      let property = currentWindow.getWindowProperties();
      // 初始化窗口高度
      let avoidArea = currentWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.scrollHeight = px2vp(property.windowRect.height - avoidArea.bottomRect.height);
      // 监听软键盘的隐藏和显示
      currentWindow.on('avoidAreaChange', data => {
        if (data.type == window.AvoidAreaType.TYPE_KEYBOARD) {
          this.keyHeight = px2vp(data.area.bottomRect.height);
          this.scrollHeight =
            px2vp(currentWindow.getWindowProperties().windowRect.height - data.area.bottomRect.height);
          return;
        }
      })
    })
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll(this.scroller) {
          Column() {
            TextInput({ text: this.text, placeholder: 'input your word...' })
              .placeholderFont({
                size: 14,
                weight: 400
              })
              .width(320)
              .height(40)
              .margin(200)
              .fontSize(14)
              .fontColor(Color.Black)
              .backgroundColor(Color.White)
            ForEach(this.arr, (item: number) => {
              Text(item.toString())
                .width('90%')
                .height(150)
                .backgroundColor(0xFFFFFF)
                .borderRadius(15)
                .fontSize(16)
                .textAlign(TextAlign.Center)
                .margin({ top: 10 })
            })
          }
        }
        .width('100%')
        .height(this.scrollHeight)
        .layoutWeight(1)
        Text('这是一个测试文本')
          .width('100%')
          .height(50)
          .backgroundColor(Color.Red)
          .margin({ bottom: this.keyHeight })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xDCDCDC)
  }
}