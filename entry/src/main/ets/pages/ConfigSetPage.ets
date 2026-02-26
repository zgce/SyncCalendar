import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleClientInfo, ProxyInfo, GoogleClientInfoManager } from '../business/GoogleClientInfoManager';
import { StrUtil } from '@pura/harmony-utils'

const MODE = 0x0003
const LOG_TAG = 'ConfigSet'

@Entry
@Component
struct ConfigSetPage {
  @State proxyInfo: ProxyInfo = {
    proxyIp: '',
    proxyPort: 0,
    proxyUser: '',
    proxyPwd: ''
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

        Text('配置Google连接信息').fontSize(18)
      }
      .width('100%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text('代理服务器IP: ').fontSize(18)
        TextInput({ placeholder: '直连可不填' })
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
        TextInput({ placeholder: '直连可不填' })
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
        TextInput({ placeholder: '直连可不填' })
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
        TextInput({ placeholder: '直连可不填' })
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
        Button('开始配置')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            if (StrUtil.isNotBlank(this.proxyInfo.proxyUser)) {
              this.getUIContext()
                .getRouter()
                .pushUrl({ url: 'pages/ClientConfigurePage', params: { action: 'new', proxy: this.proxyInfo} },
                  (err: Error) => {
                    if (err) {
                      let message = (err as BusinessError).message;
                      let code = (err as BusinessError).code;
                      hilog.error(MODE, LOG_TAG, `pushUrl to ClientConfigurePage failed, code is ${code}, message is ${message}`);
                      return;
                    }
                    hilog.info(MODE, LOG_TAG, `pushUrl to ClientConfigurePage success`);
                  })
            } else {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginPage', params: { action: 'new', proxy: this.proxyInfo }},
                (err: Error) => {
                  if (err) {
                    let message = (err as BusinessError).message;
                    let code = (err as BusinessError).code;
                    hilog.error(MODE, LOG_TAG, `pushUrl to LoginPage failed, code is ${code}, message is ${message}`);
                    return;
                  }
                  hilog.info(MODE, LOG_TAG, `pushUrl to LoginPage success`);
                })
            }
          })

        Button('取消返回')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            hilog.info(MODE, LOG_TAG, 'cancel all back to main frame.');
            this.getUIContext().getRouter().back()
          })
      }
    }
    .width('95%')
    .height('auto') // 修改为自适应高度
    .justifyContent(FlexAlign.Start)
  }
}
