import { calendarManager } from '@kit.CalendarKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleCalendarDataManager } from './GoogleCalendarDataManager'
import { GoogleClientInfoManager } from './GoogleClientInfoManager'
import { FileUtil } from './FileUtil'
import { GoogleCalendarSyncAction } from './GoogleCalendarSyncAction'

const DOMAIN = 0x0001
const LOG_TAG = "LocalCalListener"

/**
 * 客户端最后同步时间戳信息
 */
interface ClientSyncTimestamp {
  clientId: string
  lastSyncTime: number  // 最后同步时间戳（毫秒）
}

/**
 * 事件最后修改信息
 */
interface EventLastModifiedInfo {
  eventId: number
  lastModified: number  // 事件最后修改时间戳（毫秒）
}

/**
 * 本地日历监听器
 */
export class LocalCalendarListener {
  public static GLOBAL_NAME: string = 'LocalCalendarListener'
  private ctx: Context
  private isListening: boolean = false
  private syncTimer: number = -1
  private syncInterval: number = 600000  // 同步间隔时间（毫秒），默认600秒

  constructor(ctx: Context) {
    this.ctx = ctx
    hilog.info(DOMAIN, LOG_TAG, 'LocalCalendarListener created')
  }

  /**
   * 开始定时同步
   * @param interval 同步间隔时间（毫秒），默认30秒
   */
  public startListening(interval?: number) {
    if (this.isListening) {
      hilog.warn(DOMAIN, LOG_TAG, 'Already listening, skip startListening')
      return
    }

    if (interval !== undefined) {
      this.syncInterval = interval
    }

    try {
      this.isListening = true
      this.scheduleNextSync()
      hilog.info(DOMAIN, LOG_TAG, `startListening succeed, interval: ${this.syncInterval}ms`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `startListening failed! ${Error(err).message}`)
    }
  }

  /**
   * 停止定时同步
   */
  public stopListening() {
    if (!this.isListening) {
      return
    }

    try {
      this.isListening = false
      if (this.syncTimer !== -1) {
        clearTimeout(this.syncTimer)
        this.syncTimer = -1
      }
      hilog.info(DOMAIN, LOG_TAG, 'stopListening succeed')
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `stopListening failed! ${Error(err).message}`)
    }
  }

  /**
   * 安排下一次同步
   */
  private scheduleNextSync() {
    if (!this.isListening) {
      return
    }

    this.syncTimer = setTimeout(async () => {
      await this.performIncrementalSync()
      this.scheduleNextSync()
    }, this.syncInterval)
  }

  /**
   * 查找本机日历的变化，同步到远端日历上
   * 逻辑是拉起本地存储的日历数据，然后与手机上的日历对比
   */
  private async performIncrementalSync() {
    hilog.info(DOMAIN, LOG_TAG, 'performIncrementalSync started')
    const cliMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
    if (cliMgr) {
      const action = new GoogleCalendarSyncAction()
      cliMgr.getClientInfos().forEach(async (clientInfo) => {
        await action.action(clientInfo)
      })
    }
    hilog.info(DOMAIN, LOG_TAG, 'performIncrementalSync completed')
  }

  /**
   * 获取监听状态
   */
  public isListenerActive(): boolean {
    return this.isListening
  }

  /**
   * 触发执行一次同步（供外部调用）
   * 这个方法允许ServiceAbility等外部组件触发同步
   */
  public async triggerSync(): Promise<void> {
    if (!this.isListening) {
      hilog.warn(DOMAIN, LOG_TAG, 'triggerSync: listener not active')
      return
    }
    
    hilog.info(DOMAIN, LOG_TAG, 'triggerSync: manual sync triggered')
    await this.performIncrementalSync()
  }
}
