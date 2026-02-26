import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleClientInfo, ProxyInfo, GoogleClientInfoManager} from '../business/GoogleClientInfoManager';
import { StrUtil } from '@pura/harmony-utils'
import webview from '@ohos.web.webview';
import {url} from '@kit.ArkTS'

const MODE = 0x0003
const LOG_TAG = 'LoginPage'

interface RouterParams {
  action?: string;
  proxy?: ProxyInfo;
}

// 注意：Client ID 需要在 Google Cloud Console 创建 "Web application" 类型
const GOOGLE_AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const CLIENT_ID = '124011874816-l2c48v1b3bocp385bc4v1q4dhbkdjraf.apps.googleusercontent.com'
const REDIRECT_URI = 'com.fam.sync.calendar:/oauth2callback'; // 自定义协议
const SCOPE = 'https://www.googleapis.com/auth/calendar'; // 请求日历权限

@Entry
@Component
struct LoginPage {
  controller: webview.WebviewController = new webview.WebviewController()
  @State configName: string = '请输入配置名称，默认为邮箱账号'
  @State proxyInfo: ProxyInfo = {
    proxyIp: '',
    proxyPort: 0,
    proxyUser: '',
    proxyPwd: ''
  }

  private makeAuthUrl(): string {
    const state = Math.random().toString(36).substring(2)
    const result = `${GOOGLE_AUTH_URL}?` +
      `response_type=code&` +
      `client_id=${CLIENT_ID}&` +
      `redirect_uri=${encodeURIComponent(REDIRECT_URI)}&` +
      `scope=${encodeURIComponent(SCOPE)}&` +
      `state=${state}&` +
      `access_type=offline&prompt=consent`
    hilog.info(MODE, LOG_TAG, `生成授权URL: ${result}`)
    return result;
  }

  private handleOAuthCallback(callbackstr: string) {
    try {
      const callbackurl = url.URL.parseURL(callbackstr)
      const authCode = callbackurl.params.get('code')
      const error = callbackurl.params.get('error')
      if (authCode) {
        hilog.info(MODE, LOG_TAG, `获得授权码: ${authCode}`)
      } else if (error) {
        hilog.error(MODE, LOG_TAG, `获取授权失败: ${error}`)
      }
    } catch(err) {
      hilog.error(MODE, LOG_TAG, `解析回调URL错误: ${Error(err).message}`)
    }
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as RouterParams;
    if (params?.proxy) {
      this.proxyInfo = params?.proxy
    }
    if (this.proxyInfo.proxyPort != 0) {
      const proxyConfig = new webview.ProxyConfig()
      const proxyURL = `${this.proxyInfo.proxyIp}:${this.proxyInfo.proxyPort}`
      proxyConfig.insertProxyRule(proxyURL, webview.ProxySchemeFilter.MATCH_HTTPS)
      try {
        webview.ProxyController.applyProxyOverride(proxyConfig, () => {
          hilog.info(MODE, LOG_TAG, `代理设置成 ${proxyURL}`)
          this.controller.loadUrl(this.makeAuthUrl())
        })
      } catch (err) {
        hilog.error(MODE, LOG_TAG, `代理设置失败: ${JSON.stringify(err)}`)
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
        Text('配置Google账号').fontSize(18)
      }
      .width('100%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text(`代理服务器IP: ${this.proxyInfo.proxyIp}`).fontSize(18)
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Text(`代理服务器端口: ${this.proxyInfo.proxyPort}`).fontSize(18)
      }
      .width('95%')
      .height('auto')
      .justifyContent(FlexAlign.Start)

      Row() {
        Button('重刷页面')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            const proxyConfig = new webview.ProxyConfig()
            const proxyURL = `${this.proxyInfo.proxyIp}:${this.proxyInfo.proxyPort}}`
            proxyConfig.insertProxyRule(proxyURL, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES)
            webview.ProxyController.applyProxyOverride(proxyConfig, () => {
              hilog.info(MODE, LOG_TAG, `代理设置成 ${proxyURL}`)
              this.controller.loadUrl(this.makeAuthUrl())
            })
          })
        Button('取消')
          .fontSize(14)
          .width(130)
          .height(40)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            this.getUIContext().getRouter().back()
          })
      }

      Row() {
        Web({
          src: "about:blank",
          controller: this.controller
        })
          .javaScriptAccess(true)
          .databaseAccess(false)
          .mixedMode(1)
          .onLoadStarted(evt => {
            hilog.info(MODE, LOG_TAG, `on load start: ${evt.url}`)
            if (evt.url.startsWith(REDIRECT_URI)) {
              this.handleOAuthCallback(evt.url)
            }
          })
          .onErrorReceive(evt => {
            hilog.error(MODE, LOG_TAG, `页面错误: ${JSON.stringify(evt)}`)
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)

    }
  }
}