import { StrUtil } from '@pura/harmony-utils'
import { FileUtil } from './FileUtil'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleCalendarRequests } from './GoogleCalendarRequests';
import { GoogleCalendarDataManager } from './GoogleCalendarDataManager';

/**
 * 代理信息结构
 */
export interface ProxyInfo {
  proxyIp: string;
  proxyPort: number;
  proxyUser: string;
  proxyPwd: string;
}

/**
 * Google客户端配置信息
 */
export interface GoogleClientInfo {
  name: string;
  clientId: string;
  clientSecret: string;
  clientRefreshToken: string;
  proxy: ProxyInfo
}

/**
 * Google客户端信息管理器
 */
export class GoogleClientInfoManager {
  private clientInfos: GoogleClientInfo[] = [];
  private readonly STORAGE_FILE_NAME: string = 'google_client_infos.json';
  public static GLOBAL_NAME: string = 'GoogleClientManager';
  private readonly DOMAIN = 0x0001;
  private readonly LOG_TAG = "CliInfoMgrTag"

  /**
   * 添加一个GoogleClientInfo
   * @param clientInfo
   */
  addClientInfo(clientInfo: GoogleClientInfo, context: UIContext) {
    const googleReq: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
    if (!googleReq) {
      hilog.error(this.DOMAIN, this.LOG_TAG, 'get global GoogleCalendarRequests failed!')
      try {
        context.getPromptAction().showToast({
          message: `访问Google失败！`,
          duration: 2000,
          textColor: Color.White,
          backgroundColor: Color.Black
        })
      } catch (e) {
        hilog.error(this.DOMAIN, this.LOG_TAG, `getPromptAction failed, errMsg: ${JSON.stringify(e)}`)
      }
      return
    }

    googleReq.getAccessToken(clientInfo).then(accessToken => {
      if (accessToken) {
        googleReq.getPrimaryCalendarInfo(clientInfo, accessToken).then(calendarInfo => {
          if (calendarInfo) {
            clientInfo.name = calendarInfo.summary;
            this.clientInfos.push(clientInfo);
            hilog.info(this.DOMAIN, this.LOG_TAG,
              `add client info ${clientInfo.name} length ${this.clientInfos.length}`)
            const ctx = context.getHostContext()
            if (ctx) {
              this.saveToFile(ctx.filesDir)
            }
            try {
              const dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
              if (dataMgr) {
                dataMgr.createGoogleCalendar(clientInfo).then(() => {
                  hilog.info(this.DOMAIN, this.LOG_TAG, `createGoogleCalendar for ${clientInfo.name} succeed.`)
                }).catch((err: Error) => {
                  hilog.error(this.DOMAIN, this.LOG_TAG, `createGoogleCalendar for ${clientInfo.name} failed. err: ${err.message}`)
                })
              }
              context.getPromptAction().showToast({
                message: `${clientInfo.name} 添加成功！`,
                duration: 2000,
                textColor: Color.White,
                backgroundColor: Color.Black
              })
              context.getRouter().back({ url: 'pages/IndexPage', params: { needReload: true } })
            } catch (e) {
              hilog.error(this.DOMAIN, this.LOG_TAG, `getPromptAction failed, errMsg: ${JSON.stringify(e)}`)
            }
          } else {
            try {
              context.getPromptAction().showToast({
                message: '根据Client信息获取Google日历信息失败！',
                duration: 2000,
                textColor: Color.White,
                backgroundColor: Color.Black
              })
            } catch (e) {
              hilog.error(this.DOMAIN, this.LOG_TAG, `getPromptAction failed, errMsg: ${JSON.stringify(e)}`)
            }
            hilog.error(this.DOMAIN, this.LOG_TAG,
              `get primary calendar info for ${clientInfo.clientId} failed. can't add it into clientInfos`)
          }
        }).catch((err: Error) => {
          hilog.error(this.DOMAIN, this.LOG_TAG,
            `get primary calendar info for ${clientInfo.clientId} failed, errMsg: ${JSON.stringify(err)}. can't add it into clientInfos`)
        })
      } else {
        try {
          context.getPromptAction().showToast({
            message: `根据Client信息获取访问令牌失败！`,
            duration: 2000,
            textColor: Color.White,
            backgroundColor: Color.Black
          })
        } catch (e) {
          hilog.error(this.DOMAIN, this.LOG_TAG, `getPromptAction failed, errMsg: ${JSON.stringify(e)}`)
        }
        hilog.error(this.DOMAIN, this.LOG_TAG,
          `getAccessToken for ${clientInfo.clientId} failed. can't add it into clientInfos`)
      }
    }).catch((err: Error) => {
      hilog.error(this.DOMAIN, this.LOG_TAG,
        `getAccessToken for ${clientInfo.clientId} failed, errMsg: ${JSON.stringify(err)}. can't add it into clientInfos`)
    })
  }

  /**
   * 删除一个GoogleClientInfo
   * @param clientId
   */
  removeClientInfo(clientId: string) {
    this.clientInfos = this.clientInfos.filter(info => info.clientId !== clientId);
  }

  /**
   * 获取所有GoogleClientInfo
   */
  getClientInfos(): GoogleClientInfo[] {
    return this.clientInfos;
  }

  /**
   * 获取一个GoogleClientInfo
   * @param clientId
   */
  getClientInfo(clientId: string): GoogleClientInfo | undefined {
    return this.clientInfos.find(info => info.clientId === clientId);
  }

  /**
   * 清空所有GoogleClientInfo
   */
  clearClientInfos() {
    this.clientInfos = [];
  }

  /**
   * 从文件中加载GoogleClientInfo
   * @param filesDir 文件所在目录
   */
  loadFromFile(filesDir: string) {
    try {
      const filePath = filesDir + '/' + this.STORAGE_FILE_NAME;
      if (FileUtil.fileExists(filePath)) {
        const readData = FileUtil.readTextFile(filePath)
        if (StrUtil.isNotBlank(readData)) {
          const parseData = JSON.parse(readData) as Array<GoogleClientInfo>;
          if (Array.isArray(parseData)) {
            this.clientInfos = parseData;
            hilog.info(this.DOMAIN, this.LOG_TAG, `loadFromFile(${filePath}) length ${parseData.length} succeed.`)
          } else {
            hilog.error(this.DOMAIN, this.LOG_TAG, `parse text data ${readData} to Array<GoogleClientInfo> failed!`)
          }
        }
      }
    } catch (error) {
      hilog.error(this.DOMAIN, this.LOG_TAG, `file to load data from file. errmsg: ${Error(error).message}`)
      this.clientInfos = [];
    }
  }

  /**
   * 将配置信息保存到本地文件
   * @param filesDir 保存文件目录
   */
  saveToFile(filesDir: string) {
    try {
      const filePath = filesDir + '/' + this.STORAGE_FILE_NAME;
      const jsonData = JSON.stringify(this.clientInfos);
      FileUtil.writeTextFile(filePath, jsonData);
      hilog.info(this.DOMAIN, this.LOG_TAG, `saveToFile(${filePath}) length ${this.clientInfos.length} succeed.`)
    } catch (e) {
      hilog.error(this.DOMAIN, this.LOG_TAG, `saveToFile() failed ${Error(e).message}`)
    }
  }
}
