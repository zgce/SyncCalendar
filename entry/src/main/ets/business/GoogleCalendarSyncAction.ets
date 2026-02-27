import { GoogleClientInfoManager, GoogleClientInfo } from './GoogleClientInfoManager'
import { GoogleCalendarDataManager } from './GoogleCalendarDataManager'
import { GoogleCalendarEventListObj, GoogleCalendarRequests } from './GoogleCalendarRequests'
import { hilog } from '@kit.PerformanceAnalysisKit'


export class GoogleCalendarSyncAction {

  private readonly DOMAIN = 0x0001
  private readonly LOG_TAG = "SyncActionTag"

  async action(cliInfo: GoogleClientInfo) {
    const dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
    const reqMgr: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME)
    if (!dataMgr) {
      hilog.error(this.DOMAIN, this.LOG_TAG, "global dataMgr is null")
      return;
    }

    if (!reqMgr) {
      hilog.error(this.DOMAIN, this.LOG_TAG, "global reqMgr is null")
      return;
    }

    const accessToken = await reqMgr.getAccessToken(cliInfo)
    if (accessToken) {
      // 获取Google日历数据与本地数据进行合并
      const calendarData = await reqMgr.getPrimaryCalendarEvents(cliInfo, accessToken)
      if (calendarData && calendarData.items && calendarData.items.length > 0) {
        hilog.debug(this.DOMAIN, this.LOG_TAG, `get google calendarData item count ${calendarData.items.length}`)
        await dataMgr.mergeEvents(cliInfo.clientId, calendarData as GoogleCalendarEventListObj)
      } else {
        hilog.debug(this.DOMAIN, this.LOG_TAG, `get google calendarData by cli ${cliInfo.name} item count 0`)
      }
      // 同步本地数据到Google日历
      await dataMgr.syncLocalEvents(cliInfo.clientId, accessToken)
    } else {
      hilog.error(this.DOMAIN, this.LOG_TAG, `get google accessToken failed for cli ${cliInfo.name}`)
    }
  }

}