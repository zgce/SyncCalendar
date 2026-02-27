import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleClientInfo, ProxyInfo, GoogleClientInfoManager} from '../business/GoogleClientInfoManager';
import { StrUtil } from '@pura/harmony-utils'
import webview from '@ohos.web.webview';
import {url} from '@kit.ArkTS'
import { GoogleCalendarRequests, FetchResponse} from '../business/GoogleCalendarRequests';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0003
const LOG_TAG = 'LoginPage'

interface RouterParams {
  action?: string;
  proxy?: ProxyInfo;
}

interface GoogleRefreshTokenResponse {
  access_token: string
  expires_in: number
  refresh_token: string
  scope: string
  token_type: string
}

// 注意：Client ID 需要在 Google Cloud Console 创建 "Web application" 类型
const GOOGLE_AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const CLIENT_ID = '124011874816-l2c48v1b3bocp385bc4v1q4dhbkdjraf.apps.googleusercontent.com'
const REDIRECT_URI = 'com.fam.sync.calendar:/oauth2callback'; // 自定义协议
const SCOPE = 'https://www.googleapis.com/auth/calendar'; // 请求日历权限

@Entry
@Component
struct LoginPage {
  @State controller: webview.WebviewController = new webview.WebviewController()
  @State cliMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
  @State reqMgr: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
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
    hilog.info(DOMAIN, LOG_TAG, `生成授权URL: ${result}`)
    return result;
  }

  private onRefreshTokenCallback(rsp: FetchResponse) {
    if (rsp.data && rsp.retCode > 0) {
      const text = StrUtil.unit8ArrayToStr(StrUtil.bufferToUint8Array(rsp.data as ArrayBuffer))
      if (rsp.retCode == 200) {
        const refreshTokenRsp =  JSON.parse(text) as GoogleRefreshTokenResponse
        if (refreshTokenRsp) {
          hilog.info(DOMAIN, LOG_TAG, `获取Refresh成功: ${JSON.stringify(refreshTokenRsp)}`)
          const cliInfo: GoogleClientInfo = {
            name: 'GoogleCalendar',
            clientId: CLIENT_ID,
            clientSecret: '',
            clientRefreshToken: refreshTokenRsp.refresh_token,
            proxy: this.proxyInfo
          }
          this.cliMgr?.addClientInfo(cliInfo, this.getUIContext())
          console.info(`add clientInfo ${cliInfo.name}`)
          promptAction.openToast({
            message: '正在添加配置中，请稍等...',
            duration: 2000,
            textColor: Color.White,
            backgroundColor: Color.Black
          }).catch((err: Error) => {
            console.error(`显示提示失败 ${err.name}, ${err.message}`)
          })
        }
      } else {
        hilog.error(DOMAIN, LOG_TAG, `获取Refresh失败: retCode: ${rsp.retCode}, msg: ${text}`)
      }
    } else {
      hilog.error(DOMAIN, LOG_TAG, `获取Refresh失败: ${rsp.retCode}`)
    }
  }

  private handleOAuthCallback(callbackstr: string) {
    try {
      const callbackurl = url.URL.parseURL(callbackstr)
      const authCode = callbackurl.params.get('code')
      const error = callbackurl.params.get('error')
      if (authCode) {
        hilog.info(DOMAIN, LOG_TAG, `获得授权码: ${authCode}`)
        const refreshTokenURL = `https://oauth2.googleapis.com/token?`
        const content = `code=${authCode}&client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&grant_type=authorization_code&access_type=offline&prompt=consent`
        if (this.reqMgr) {
          if (StrUtil.isNotBlank(this.proxyInfo.proxyIp)) {
            this.reqMgr.fetchUrlWithProxy(this.proxyInfo, refreshTokenURL, http.RequestMethod.POST, content).then((rsp) => {
              this.onRefreshTokenCallback(rsp)
            }).catch((err: Error) => {
              hilog.error(DOMAIN, LOG_TAG, `获取Refresh失败: ${err.message}`)
            })
          } else {
            this.reqMgr.fetchUrl(refreshTokenURL, http.RequestMethod.POST, content).then((rsp) => {
              this.onRefreshTokenCallback(rsp)
            }).catch((err: Error) => {
              hilog.error(DOMAIN, LOG_TAG, `获取Refresh失败: ${err.message}`)
            })
          }
        }
      } else if (error) {
        hilog.error(DOMAIN, LOG_TAG, `获取授权失败: ${error}`)
      }
    } catch(err) {
      hilog.error(DOMAIN, LOG_TAG, `解析回调URL错误: ${Error(err).message}`)
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
      proxyConfig.insertProxyRule(proxyURL, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES)
      try {
        webview.ProxyController.applyProxyOverride(proxyConfig, () => {
          hilog.info(DOMAIN, LOG_TAG, `代理设置成 ${proxyURL}`)
          this.controller.loadUrl(this.makeAuthUrl())
        })
      } catch (err) {
        hilog.error(DOMAIN, LOG_TAG, `代理设置失败: ${JSON.stringify(err)}`)
      }
    } else {
      try {
          const url = this.makeAuthUrl()
          hilog.info(DOMAIN, LOG_TAG, ` 直接加载URL ${url}`)
          this.controller.loadUrl(url)
      } catch (err) {
        hilog.error(DOMAIN, LOG_TAG, `加载URL失败: ${JSON.stringify(err)}`)
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
            if (this.proxyInfo.proxyPort != 0) {
              const proxyConfig = new webview.ProxyConfig()
              const proxyURL = `${this.proxyInfo.proxyIp}:${this.proxyInfo.proxyPort}}`
              proxyConfig.insertProxyRule(proxyURL, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES)
              webview.ProxyController.applyProxyOverride(proxyConfig, () => {
                hilog.info(DOMAIN, LOG_TAG, `代理设置成 ${proxyURL}`)
                const url = this.makeAuthUrl()
                try {
                  this.controller.loadUrl(url)
                } catch (err) {
                  hilog.error(DOMAIN, LOG_TAG, `打开网页 ${url} 失败: ${JSON.stringify(err)}`)
                }
              })
            } else {
              const url = this.makeAuthUrl()
              try {
                this.controller.loadUrl(url)
              } catch (err) {
                hilog.error(DOMAIN, LOG_TAG, `打开网页 ${url} 失败: ${JSON.stringify(err)}`)
              }
            }
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
            hilog.info(DOMAIN, LOG_TAG, `on load start: ${evt.url}`)
            if (evt.url.startsWith(REDIRECT_URI)) {
              this.handleOAuthCallback(evt.url)
            }
          })
          .onErrorReceive(evt => {
            hilog.error(DOMAIN, LOG_TAG, `页面错误: ${JSON.stringify(evt)}`)
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)

    }
  }
}