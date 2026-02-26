import { describe, it, expect } from '@ohos/hypium'
import { StrUtil } from '@pura/harmony-utils'
import { GoogleClientInfo} from '../../../../main/ets/business/GoogleClientInfoManager'
import { GoogleCalendarRequests, GoogleCalendarObj } from '../../../../main/ets/business/GoogleCalendarRequests'
import testData  from './GoogleClient.json'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const LOG_TAG = 'JustTestTag'

export default function testGoogleCalendarRequests() {
  describe('GoogleCalendarRequests', () => {
    it('GoogleCalendarRequests_success', 0, async () => {
      let reqManager = new GoogleCalendarRequests();
      const clientInfo: GoogleClientInfo = testData as GoogleClientInfo;
      const accessToken = await reqManager.getAccessToken(clientInfo)
      expect(StrUtil.isNotBlank(accessToken)).assertTrue()
      hilog.info(DOMAIN, LOG_TAG, `accessToken: ${accessToken}`)
      const calendar = await reqManager.getPrimaryCalendarInfo(clientInfo, accessToken as string)
      expect(typeof calendar !== 'undefined').assertTrue()
      hilog.info(DOMAIN, LOG_TAG, `calendar: ${JSON.stringify(calendar as GoogleCalendarObj)}`)
      const events = await reqManager.getPrimaryCalendarEvents(clientInfo, accessToken as string)
      expect(typeof events !== 'undefined').assertTrue()
    })
  })
}
