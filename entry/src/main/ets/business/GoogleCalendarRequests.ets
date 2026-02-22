import { StrUtil } from '@pura/harmony-utils'
import { rcp } from '@kit.RemoteCommunicationKit'
import { http } from '@kit.NetworkKit'
import { GoogleClientInfo, ProxyInfo } from './GoogleClientInfoManager';


/**
 * 向Google请求AccessToken后的回应消息结构
 */
interface AccessTokenRespType {
  access_token: string,
  expires_in: number,
  scope: string,
  token_type: string,
  refresh_token_expires_in: number
}

/**
 * 定义通用的回应结构，使得发送HTTPS请求函数获得统一的回应结构
 */
interface FetchResponse {
  retCode: number;
  data?: string | ArrayBuffer | object;
}

interface UserObj {
  email: string;
  displayName: string;
}

interface timeObj {
  dateTime: string;
  timeZone: string;
}

/**
 * Google日历对象结构
 */
export interface GoogleCalendarObj {
  kind: string;
  etag: string;
  id: string;
  summary: string;
  timeZone: string;
  autoAcceptInvitations: boolean;
}

/**
 * Google日历事件对象结构
 */
export interface GoogleCalendarEventObj {
  kind: string;
  etag: string;
  id: string;
  status: string;
  htmlLink: string;
  created: string;
  updated: string;
  summary: string;
  description: string;
  creator: UserObj;
  organizer: UserObj;
  start: timeObj;
  end: timeObj;
  iCalUID: string;
  sequence: number;
  eventType: string;
}

/**
 * Google日历事件列表对象结构
 */
export interface GoogleCalendarEventListObj {
  kind: string;
  etag: string;
  summary: string;
  description: string;
  updated: string;
  timeZone: string;
  accessRole: string;
  nextPageToken: string;
  nextSyncToken: string;
  items: Array<GoogleCalendarEventObj>;
}


/**
 * 封装Google日历API请求
 */
export class GoogleCalendarRequests {
  public static GLOBAL_NAME: string = 'GoogleCalendarReqManager';

  /**
   * 获取AccessToken，后续所有请求必须有AccessToken
   * @param info Google客户端配置信息
   * @returns AccessToken字串
   */
  async getAccessToken(info: GoogleClientInfo): Promise<string | undefined> {
    const proxyInfo = info.proxy
    let result: string | undefined = undefined
    try {
      const content =
        `grant_type=refresh_token&client_id=${info.clientId}&client_secret=${info.clientSecret}&refresh_token=${info.clientRefreshToken}`
      let rsp: FetchResponse = {retCode: 0}
      const url = 'https://oauth2.googleapis.com/token'
      if (proxyInfo && StrUtil.isNotBlank(proxyInfo.proxyIp)) {
        rsp = await this.fetchUrlWithProxy(proxyInfo, url, http.RequestMethod.POST, content)
      } else {
        rsp = await this.fetchUrl(url, http.RequestMethod.POST, content)
      }
      if (rsp.data && rsp.retCode > 0) {
        const text = StrUtil.unit8ArrayToStr(StrUtil.bufferToUint8Array(rsp.data as ArrayBuffer))
        console.log(`get accessToken response status code: ${rsp.retCode}, response: ${text}`)
        if (rsp.retCode == 200) {
          const pjs = JSON.parse(text) as AccessTokenRespType
          console.log(`parse access_token: ${pjs.access_token}`)
          result = pjs.access_token;
        }
      }
    } catch (err) {
      console.error('request access token failed! error: ', err.message)
    }
    return result;
  }

  /**
   * 获取Google主日历信息
   * @param info Google客户端配置信息
   * @param accessToken 认证用的AccessToken
   * @returns 日历信息
   */
  async getPrimaryCalendarInfo(info: GoogleClientInfo, accessToken: string): Promise<GoogleCalendarObj | undefined>  {
    const proxyInfo = info.proxy
    let primaryCalendar : GoogleCalendarObj | undefined = undefined
    try {
      const url = 'https://www.googleapis.com/calendar/v3/calendars/primary'
      let rsp: FetchResponse = {retCode: 0}
      if (proxyInfo && StrUtil.isNotBlank(proxyInfo.proxyIp)) {
        rsp = await this.fetchUrlWithProxy(proxyInfo, url, http.RequestMethod.GET, undefined, accessToken)
      } else {
        rsp = await this.fetchUrl(url, http.RequestMethod.GET, undefined, accessToken)
      }
      if (rsp.data && rsp.retCode === 200) {
        const text = StrUtil.unit8ArrayToStr(StrUtil.bufferToUint8Array(rsp.data as ArrayBuffer))
        primaryCalendar = JSON.parse(text) as GoogleCalendarObj
      }
    } catch (err) {
      console.error('getPrimaryCalendar failed! error: ', err.message)
    }
    return primaryCalendar
  }

  /**
   * 获取Google主日历事件列表
   * @param info Google客户端配置信息
   * @param accessToken 认证用的AccessToken
   * @param nextSyncToken 查询同步标记
   * @returns 日历事件列表
   */
  async getPrimaryCalendarEvents(info: GoogleClientInfo, accessToken: string, nextSyncToken?: string): Promise<GoogleCalendarEventListObj | undefined> {
    const proxyInfo = info.proxy
    let calendarEvents: GoogleCalendarEventListObj | undefined = undefined
    try {
      let url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events'
      if (StrUtil.isNotEmpty(nextSyncToken)) {
        url += `?syncToken=${nextSyncToken}`
      }
      let rsp: FetchResponse = {retCode: 0}
      if (proxyInfo && StrUtil.isNotBlank(proxyInfo.proxyIp)) {
        rsp = await this.fetchUrlWithProxy(proxyInfo, url, http.RequestMethod.GET, undefined, accessToken)
      } else {
        rsp = await this.fetchUrl(url, http.RequestMethod.GET, undefined, accessToken)
      }
      if (rsp.retCode === 410) { // 410 Gone
        calendarEvents = await this.getPrimaryCalendarEvents(info, accessToken)
      }
      if (rsp.data && rsp.retCode === 200) {
        const text = StrUtil.unit8ArrayToStr(StrUtil.bufferToUint8Array(rsp.data as ArrayBuffer))
        calendarEvents = JSON.parse(text) as GoogleCalendarEventListObj
      }
    } catch ( err) {
      console.error('getPrimaryCalendarEvents failed! error: ', err.message)
    }
    return calendarEvents
  }

  /**
   * 使用代理发送请求URL
   * @param proxyInfo 代理信息
   * @param url 发送请求的URL
   * @param method 请求方法 GET/POST/PUT/DELETE
   * @param content 请求内容
   * @param accessToken 认证用的AccessToken
   * @returns 请求回应结构
   */
  private async fetchUrlWithProxy(proxyInfo: ProxyInfo, url: string, method: string,
    content?: string, accessToken?: string): Promise<FetchResponse> {
    let ret: FetchResponse = { retCode: 0 }
    try {
      const session = rcp.createSession()
      const request = new rcp.Request(url, method)
      request.configuration = {
        proxy: {
          url: `https://${proxyInfo.proxyUser}:${proxyInfo.proxyPwd}@${proxyInfo.proxyIp}:${proxyInfo.proxyPort}`,
          createTunnel: 'always',
          security: {
            remoteValidation: 'skip',
          },
          exclusions: []
        }
      }
      if (StrUtil.isEmpty(accessToken)) { // 似乎、可能、好象只有在首次获取AccessToken时才会发送表单
        request.headers = {
          'content-type': 'application/x-www-form-urlencoded',
          'accept': 'application/json'
        }
      } else {
        request.headers = {
          'content-type': 'application/json',
          'accept': 'application/json',
          'Authorization': `Bearer ${accessToken}`
        }
      }
      if (StrUtil.isNotBlank(content)) {
        request.content = content as string;
      }
      try {
        const rsp = await session.fetch(request)
        ret.retCode = rsp.statusCode
        if (rsp.body) {
          ret.data = rsp.body
        }
      } catch (err) {
        console.error(`request ${method} for ${url} with proxy failed! error:`, err.message)
      } finally {
        session.close()
      }
    } catch (err) {
      console.error('create rcp session failed! error: ', err.message)
    }
    return ret
  }

  private async fetchUrl(url: string, action: http.RequestMethod, content?: string,
    accessToken?: string): Promise<FetchResponse> {
    const request = http.createHttp()
    let ret: FetchResponse = { retCode: 0 }
    const httpOptions: http.HttpRequestOptions = { method: action }
    if (StrUtil.isEmpty(accessToken)) {
      httpOptions.header = {
        'content-type': 'application/x-www-form-urlencoded',
        'accept': 'application/json',
      }
    } else {
      httpOptions.header = {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'accept': 'application/json',
      }
    }
    if (content) {
      httpOptions.extraData = content;
    }
    try {
      const rsp = await request.request(url, httpOptions);
      ret.retCode = rsp.responseCode
      if (rsp.result) {
        switch (rsp.resultType) {
          case http.HttpDataType.STRING:
            ret.data = rsp.result as string
            break
          case http.HttpDataType.ARRAY_BUFFER:
            ret.data = rsp.result as ArrayBuffer
            break;
          default:
            ret.data = rsp.result as object
        }
      }
    } catch (err) {
      console.error(`fetch url: ${url} failed!`, err.message)
    } finally {
      request.destroy()
    }
    return ret;
  }
}