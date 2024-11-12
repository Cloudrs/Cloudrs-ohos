
@Observed
class Task {
  static taskIndex : number = 1

  name: string = '任务' + `${Task.taskIndex++}`

  finished: boolean = false

  deleted: boolean = false
}

@Component
struct TaskProgress {
  @Prop finishedTaskNum: number
  @Prop totalTaskNum: number

  build() {
    Row({space: 50}) {
      Text('任务进度')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({left: 20})

      Stack() {
        Progress({
          value: this.finishedTaskNum,
          total: this.totalTaskNum,
          type: ProgressType.Ring
        })
          .width(100)
          .style({strokeWidth: 15})
        Text(`${this.finishedTaskNum}` + ` / ${this.totalTaskNum}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .height(120)
    .borderRadius(10)
    .backgroundColor('#fff')
    .justifyContent(FlexAlign.SpaceEvenly)
  }
}

@Component
struct TaskItem {
  @ObjectLink item: Task
  onTaskChange?: () => void

  build() {
    Row() {
      if (this.item.finished) {
        Text(this.item.name)
          .width(60)
          .fontSize(16)
          .decoration({type: TextDecorationType.LineThrough})
          .fontColor('#B1B2B3')
      }
      else {
        Text(this.item.name)
          .width(60)
          .fontSize(16)
      }

      Blank()
      Checkbox()
        .height(20)
        .select(this.item.finished)
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .onChange(
          value => {
            this.item.finished = value
            if (this.onTaskChange) {
              this.onTaskChange()
            }
          }
        )
    }
    .width('100%')
    .height(50)
    .padding(10)
    .borderRadius(10)
    .backgroundColor('#fff')
  }
}

@Component
struct TaskList {
  @Link finishedTaskNum: number
  @Link totalTaskNum: number
  @State tasks: Task[] = []
  @State taskIcon: ResourceStr[] = []

  handleTaskChange() {
    this.totalTaskNum = this.tasks.length
    this.finishedTaskNum = this.tasks.filter(item => item.finished).length
  }

  build() {
    Column() {
      // 1.任务添加按钮
      Button('添加任务')
        .width('60%')
        .margin({bottom:10})
        .onClick(
          () => {
            this.tasks.push(new Task())
            this.taskIcon.push($r('app.media.ic_trash_close'))
            this.handleTaskChange()
          }
        )

      // 2.任务列表
      List({ space: 10 }) {
        ForEach(
          this.tasks,
          (item: Task, index) => {
            ListItem() {
              TaskItem({ item: item, onTaskChange: this.handleTaskChange.bind(this)})
            }
            .swipeAction({
              end: {
                actionAreaDistance: 100,
                onAction: () => {
                  this.tasks.splice(index, 1)
                  this.taskIcon.splice(index, 1)
                  this.handleTaskChange()
                },
                onEnterActionArea: () => {
                  this.taskIcon[index] = $r('app.media.ic_trash_open')
                },
                onExitActionArea: () => {
                  this.taskIcon[index] = $r('app.media.ic_trash_close')
                },
                builder: this.DeleteButton(index)
              }
            })
          }
        )
      }
      .width('100%')
      .layoutWeight(1)
      .alignListItem(ListItemAlign.Center)
    }
  }

  @Builder DeleteButton(index: number) {
    Button() {
      Image(this.taskIcon[index])
        .fillColor(Color.White)
        .height('50%')
    }
    .width(50)
    .height(40)
    .margin({left:5})
    .type(ButtonType.Circle)
    .backgroundColor(Color.Red)
    .onClick(() => {
      this.tasks.splice(index, 1)
      this.taskIcon.splice(index, 1)
      this.handleTaskChange()
    })
  }
}

@Entry
@Component
struct Index {
  @State finishedTaskNum: number = 0
  @State totalTaskNum: number = 0

  build() {
    Column({ space: 20 }) {
      // 1.任务进度
      TaskProgress({ finishedTaskNum: this.finishedTaskNum, totalTaskNum: this.totalTaskNum })

      // 2.任务列表及管理
      TaskList({ finishedTaskNum: this.finishedTaskNum, totalTaskNum: this.totalTaskNum })
    }
    .height('100%')
    .padding(20)
    .backgroundColor('#F1F2F3')
  }
}
