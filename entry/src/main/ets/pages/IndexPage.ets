import { GoogleCalendarDataManager } from '../business/GoogleCalendarDataManager';
import { GoogleCalendarRequests } from '../business/GoogleCalendarRequests';
import { GoogleCalendarSyncAction } from '../business/GoogleCalendarSyncAction';
import { GoogleClientInfo, GoogleClientInfoManager} from '../business/GoogleClientInfoManager';
import { promptAction } from '@kit.ArkUI';

interface RouterParams {
  needReload: boolean;
}

@Entry
@Component
struct Index {
  @State infosMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
  @State dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
  @State reqMgr: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
  @State swipIndex: number | null = null
  @State needReload: boolean = false
  @State swipeOffsets: Map<number, number> = new Map()
  private readonly DELETE_BTN_WIDTH: number = 70
  private readonly SYNC_BTN_WIDTH: number = 70

  aboutToAppear(): void {
    // 初始化加载数据
    this.infosMgr = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
    this.dataMgr = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
    this.reqMgr = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
  }

  onPageShow(): void {
    const params = this.getUIContext().getRouter().getParams() as RouterParams;
    this.needReload = params?.needReload || false
    if (this.needReload) {
      this.needReload = false
      this.getUIContext()
        .getRouter()
        .replaceUrl({ url: 'pages/IndexPage', params: { needReload: false } })
        .catch((err: Error) => {
          console.error(`replace current page [pages/IndexPage] failed! err: ${err.name}, ${err.message}`)
        })
    }
  }

  build() {
    Column({ space: 11 }) {
      Row() {
        Image($r('app.media.SyncCalendar'))
          .width(45)
          .height(45)
          .margin({ left: 24, right: 8 })

        Text('日历同步助手')
          .fontSize(21)

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(24)
            .fontColor([Color.Black])
            .margin({ left: 12, right: 12 })
        }
        .backgroundColor(Color.White)
        .bindTips('新增日历服务器')
        .height(30)
        .onClick(() => {
          this.getUIContext()
            .getRouter()
            .pushUrl({ url: 'pages/ConfigSetPage', params: { action: 'new' } }, (err: Error) => {
              if (err) {
                let message = (err as BusinessError).message;
                let code = (err as BusinessError).code;
                console.error(`pushUrl failed, code is ${code}, message is ${message}`);
                return;
              }
              console.info('pushUrl to ConfigureInfo success');
            })
        })

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(24)
            .fontColor([Color.Black])
            .margin({ left: 12, right: 12 })
        }
        .backgroundColor(Color.White)
        .height(30)
        .onClick(() => {
          this.infosMgr?.getClientInfos().forEach(info => {
            const syncAction = new GoogleCalendarSyncAction()
            syncAction.action(info).then(() => {
              promptAction.openToast({
                message: '同步完成',
                duration: 2000,
                textColor: Color.White,
                backgroundColor: Color.Black
              }).catch((err: Error) => {
                console.error(`显示提示失败 ${err.name}, ${err.message}`)
              })
            })
            promptAction.openToast({
              message: '正在同步中，请稍候...',
              duration: 3000,
              textColor: Color.White,
              backgroundColor: Color.Black
            }).catch((err: Error) => {
              console.error(`显示提示失败 ${err.name}, ${err.message}`)
            })
          })
        })
      }
      .width('100%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      List({ space: 5 }) {
        ForEach(this.infosMgr?.getClientInfos(), (item: GoogleClientInfo, index: number) => {
          ListItem() {
            Stack({ alignContent: Alignment.End }) {
              // 同步按钮（淡黄色背景）
              Row({ space: 0 }) {
                Button() {
                  Text('同步')
                    .fontSize(14)
                    .fontColor(Color.Black)
                }
                .backgroundColor('#FFFACD')
                .width(this.SYNC_BTN_WIDTH)
                .height('100%')
                .onClick(() => {
                  const syncAction = new GoogleCalendarSyncAction()
                  syncAction.action(item).then(() => {
                    promptAction.openToast({
                      message: '同步完成',
                      duration: 2000,
                      textColor: Color.White,
                      backgroundColor: Color.Black
                    }).catch((err: Error) => {
                      console.error(`显示提示失败 ${err.name}, ${err.message}`)
                    })
                  })
                  promptAction.openToast({
                    message: '正在同步中，请稍候...',
                    duration: 3000,
                    textColor: Color.White,
                    backgroundColor: Color.Black
                  }).catch((err: Error) => {
                    console.error(`显示提示失败 ${err.name}, ${err.message}`)
                  })
                  this.closeSwipe(index)
                })

                // 右侧删除按钮（淡红色背景）
                Button() {
                  Text('删除')
                    .fontSize(14)
                    .fontColor(Color.White)
                }
                .backgroundColor('#FF6B6B')
                .width(this.DELETE_BTN_WIDTH)
                .height('100%')
                .onClick(() => {
                  this.showDeleteInfoDialog(item)
                  this.closeSwipe(index)
                })
              }

              // 主内容区域
              Row() {
                Image($r('app.media.GoogleCalendar'))
                  .width(86)
                  .height(86)
                  .border({ width: 0 })
                  .borderRadius(10)
                Text(item.name)
                  .fontSize(19)
                  .margin({ left: 12 })
              }
              .width('100%')
              .height(80)
              .justifyContent(FlexAlign.Start)
              .backgroundColor('#E3F2FD')
              .padding({ left: 16 })
              .border({ width: 1, color: 0xD9D9D9 })
              .borderRadius(4)
              .translate({ x: this.swipeOffsets.get(index) || 0 })
              .gesture(PanGesture({
                fingers: 1,
                direction: PanDirection.Horizontal,
                distance: 10
              }).onActionUpdate((evt: GestureEvent) => {
                const currentOffset = this.swipeOffsets.get(index) || 0
                const maxOffset = -(this.DELETE_BTN_WIDTH + this.SYNC_BTN_WIDTH)
                let newOffset = currentOffset + evt.offsetX
                // 限制滑动范围
                if (newOffset < maxOffset) {
                  newOffset = maxOffset
                } else if (newOffset > 0) {
                  newOffset = 0
                }
                this.swipeOffsets.set(index, newOffset)
              }).onActionEnd((evt: GestureEvent) => {
                const currentOffset = this.swipeOffsets.get(index) || 0
                const maxOffset = -(this.DELETE_BTN_WIDTH + this.SYNC_BTN_WIDTH)
                // 根据滑动距离决定是打开还是关闭
                if (currentOffset < maxOffset / 2) {
                  this.swipeOffsets.set(index, maxOffset)
                } else {
                  this.swipeOffsets.set(index, 0)
                }
              }))
              .onClick(() => {
                if ((this.swipeOffsets.get(index) || 0) !== 0) {
                  this.closeSwipe(index)
                  return
                }
                this.getUIContext()
                  .getRouter()
                  .pushUrl({ url: 'pages/ClientConfigurePage', params: { action: 'edit', clientId: item.clientId } },
                    (err: Error) => {
                      if (err) {
                        let message = (err as BusinessError).message;
                        let code = (err as BusinessError).code;
                        console.error(`pushUrl by ${item.name} failed, code is ${code}, message is ${message}`);
                        return;
                      }
                      console.info(`pushUrl to ${item.name} ConfigureInfo success`);
                    })
              })
            }
            .height(80)
            .width('100%')
            .clip(true)
          }
        })
      }
      .padding({ left: 8, right: 8 })
    }
    .layoutWeight(1)
    .width('100%')
    .height('auto')
  }

  private closeSwipe(index: number): void {
    this.swipeOffsets.set(index, 0)
  }

  private showDeleteInfoDialog(item: GoogleClientInfo): void {
    this.getUIContext().showAlertDialog({
      title: '确认删除',
      message: `确认要删除配置 ${item.name} 吗？`,
      autoCancel: true,
      primaryButton: {
        defaultFocus: false,
        value: '确定',
        action: () => {
          this.infosMgr?.removeClientInfo(item.clientId)
          this.infosMgr?.saveToFile(this.getUIContext().getHostContext()?.filesDir)
          this.dataMgr?.removeClientData(item.clientId)
          console.log(`delete client info ${item.name}`)
        }
      },
      secondaryButton: {
        defaultFocus: true,
        value: '取消',
        action: () => {
          console.log(`cancel delete client info ${item.name}`)
        }
      }
    })
  }
}