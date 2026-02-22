import { GoogleClientInfo, ProxyInfo, GoogleClientInfoManager} from '../business/GoogleClientInfoManager';
import { GoogleCalendarRequests } from '../business/GoogleCalendarRequests';
import { StrUtil } from '@pura/harmony-utils'
import { promptAction } from '@kit.ArkUI';

interface CalendarVendor {
  name: string;
  disable: boolean;
}

interface RouterParams {
  action?: string;
  clientId?: string;
}

@Entry
@Component
struct ConfigureInfo {
  @State options: CalendarVendor[] = [
    { name: "google日历", disable: false },
    { name: "163日历", disable: true },
    { name: "QQ日历", disable: true }
  ]
  @State selectedVendor: number = 0;
  @State action: string = ''
  @State title: string = ''
  @State proxyInfo: ProxyInfo = {
    proxyIp: '',
    proxyPort: 0,
    proxyUser: '',
    proxyPwd: ''
  }
  @State clientInfo: GoogleClientInfo = {
    name: '',
    clientId: '',
    clientSecret: '',
    clientRefreshToken: '',
    proxy: this.proxyInfo
  }
  @State infosMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
  @State googleReqMgr: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
  @State newIndex: number | null = null
  @State edtCliId: string | null = null

  aboutToAppear(): void {
    // 初始化加载数据
    this.infosMgr = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
    this.googleReqMgr = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
  }

  onPageShow(): void {
    const params = this.getUIContext().getRouter().getParams() as RouterParams;
    this.action = params?.action || 'new';
    if (this.action === 'new') {
      this.title = '新配置日历服务'
      this.newIndex = this.infosMgr?.getClientInfos().length || 1;
    } else if (this.action === 'edit') {
      this.title = '配置日历服务'
      this.edtCliId = params?.clientId || null;
      if (StrUtil.isNotBlank(this.edtCliId)) {
        const info = this.infosMgr?.getClientInfo(this.edtCliId as string);
        if (info) {
          this.clientInfo = info as GoogleClientInfo;
          this.proxyInfo = this.clientInfo.proxy
          this.googleReqMgr?.getAccessToken(this.clientInfo)
        }
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([Color.Black])
            .margin({ left: 12, right: 12 })
        }
        .backgroundColor(Color.White)
        .height('30')
        .onClick(() => {
          this.getUIContext().getRouter().back()
        })

        Text(this.title).fontSize(18)
      }
      .width('100%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Text('日历服务:      当前仅支持Google日历').fontSize(18)
      Row() {
        Text('配置名称: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? `Google日历${this.newIndex}` : this.clientInfo.name })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('70%')
          .onChange((value: string) => {
            this.clientInfo.name = value;
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('Client ID: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? 'GOOGLE_CLIENT_ID' : this.clientInfo.clientId })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('70%')
          .onChange((value: string) => {
            this.clientInfo.clientId = value;
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('Client Secret: ').fontSize(18)
        TextInput({
          placeholder: StrUtil.isBlank(this.edtCliId) ? 'GOOGLE_CLIENT_SECRET' : this.clientInfo.clientSecret
        })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('60%')
          .onChange((value: string) => {
            this.clientInfo.clientSecret = value
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('Refresh Token: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? 'GOOGLE_REFRESH_TOKEN': this.clientInfo.clientRefreshToken })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('60%')
          .onChange((value: string) => {
            this.clientInfo.clientRefreshToken = value
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Blank()

      Row() {
        Text('代理服务器IP: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? '直连可不填' : this.proxyInfo.proxyIp })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('60%')
          .onChange((value: string) => {
            this.proxyInfo.proxyIp = value
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('代理服务器端口: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? '直连可不填' : this.proxyInfo.proxyPort.toString() })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('54%')
          .type(InputType.Number)
          .onChange((value: string) => {
            this.proxyInfo.proxyPort = parseInt(value)
          })
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('用户名: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? '直连可不填' : this.proxyInfo.proxyUser })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('75%')
          .onChange((value: string) => {
            this.proxyInfo.proxyUser = value
          })
      }
      .width('95%')
      .height('auto') // 修改为自适应高度
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('密码: ').fontSize(18)
        TextInput({ placeholder: StrUtil.isBlank(this.edtCliId) ? '直连可不填' : this.proxyInfo.proxyPwd })
          .fontSize(14)
          .padding(2)
          .border({ width: 1, color: 0xD9D9D9 })
          .borderRadius(4)
          .width('80%')
          .onChange((value: string) => {
            this.proxyInfo.proxyPwd = value
          })
      }
      .width('95%')
      .height('auto') // 修改为自适应高度
      .justifyContent(FlexAlign.Start)

      Row() {
        Button('确定')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            if (this.action === 'new') {
              if (this.validClientInfo()) {
                this.addClientInfo()
                promptAction.openToast({
                  message: '添加成功',
                  duration: 3000,
                  textColor: Color.White,
                  backgroundColor: Color.Black
                }).catch((err: Error) => {
                  console.error(`显示提示失败 ${err.name}, ${err.message}`)
                })
                this.saveClientInfo();
                this.getUIContext().getRouter().back({ url: 'pages/Index', params: { needReload: true }})
              } else {
                this.getUIContext().showAlertDialog({
                  autoCancel: true,
                  message: '必须输入\nName/ClientID/ClientSecret/RefreshToken'
                })
              }
            } else if (this.action === 'edit' && StrUtil.isNotBlank(this.edtCliId)) {
              if (this.validClientInfo()) {
                this.edtClient();
                promptAction.openToast({
                  message: '修改配置成功',
                  duration: 3000,
                  textColor: Color.White,
                  backgroundColor: Color.Black
                }).catch((err: Error) => {
                  console.error(`显示提示失败 ${err.name}, ${err.message}`)
                })
                this.saveClientInfo();
                this.getUIContext().getRouter().back()
              } else {
                this.getUIContext().showAlertDialog({
                  autoCancel: true,
                  message: '必须输入\nName/ClientID/ClientSecret/RefreshToken'
                })
              }
            }
          })

        Button('取消')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            console.info('cancel all back to main frame.');
            this.getUIContext().getRouter().back()
          })
      }
    }
    .width('100%')
    .height('auto') // 修改为自适应高度
    .justifyContent(FlexAlign.Start)
  }

  private saveClientInfo(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      const context = ctx as Context
      this.infosMgr?.saveToFile(context.filesDir)
    }
  }

  private validClientInfo(): boolean {
    return StrUtil.isNotBlank(this.clientInfo.name) && StrUtil.isNotBlank(this.clientInfo.clientId) &&
    StrUtil.isNotBlank(this.clientInfo.clientSecret)
  }

  private addClientInfo(): void {
    this.clientInfo.proxy = this.proxyInfo;
    this.infosMgr?.addClientInfo(this.clientInfo)
    console.info(`add clientInfo ${this.clientInfo.name}`)
  }

  private edtClient(): void {
    this.clientInfo.proxy = this.proxyInfo;
    const data = this.infosMgr?.getClientInfo(this.clientInfo.clientId);
    if (data) {
      data.name = this.clientInfo.name
      data.clientId = this.clientInfo.clientId
      data.clientSecret = this.clientInfo.clientSecret
      data.clientRefreshToken = this.clientInfo.clientRefreshToken
      data.proxy = this.clientInfo.proxy
    }
  }
}