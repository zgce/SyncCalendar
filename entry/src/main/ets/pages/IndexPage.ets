import { GoogleCalendarDataManager } from '../business/GoogleCalendarDataManager';
import { GoogleCalendarRequests } from '../business/GoogleCalendarRequests';
import { GoogleCalendarSyncAction } from '../business/GoogleCalendarSyncAction';
import { GoogleClientInfo, GoogleClientInfoManager} from '../business/GoogleClientInfoManager';

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
            syncAction.action(info)
          })
        })
      }
      .width('100%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      List({ space: 5 }) {
        ForEach(this.infosMgr?.getClientInfos(), (item: GoogleClientInfo, index: number) => {
          ListItem() {
            Row() {
              if (this.swipIndex == index) {
                Button() {
                  Text('删除')
                    .fontSize(14)
                    .fontColor(Color.White)
                }
                .backgroundColor('#FF4444')
                .width(50)
                .height(50)
                .margin({ right: 5 })
                .onClick(() => {
                  this.showDeleteInfoDialog(item)
                  this.swipIndex = null
                })
              }
              Button() {
                Row() {
                  Image($r('app.media.GoogleCalendar'))
                    .width(48)
                    .height(48)
                  Text(item.name)
                    .fontSize(18)
                }
                .width('100%')
                .height('auto')
                .justifyContent(FlexAlign.Start)
              }
              .backgroundColor(Color.White)
              .margin({ left: 8, right: 8 })
              .height('auto')
              .border({ width: 1, color: 0xD9D9D9 })
              .borderRadius(4)
              .gesture(PanGesture({
                fingers: 1,
                direction: PanDirection.Right,
                distance: 10
              }).onActionEnd((evt: GestureEvent) => {
                this.swipIndex = index
              }))
              .gesture(PanGesture({
                fingers: 1,
                direction: PanDirection.Left,
                distance: 10
              }).onActionEnd((evt: GestureEvent) => {
                this.swipIndex = null
              }))
              .onClick(() => {
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
          }
        })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .height('auto')
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