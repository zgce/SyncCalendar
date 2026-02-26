import { calendarManager } from '@kit.CalendarKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { GoogleCalendarDataManager } from './GoogleCalendarDataManager'
import { GoogleClientInfoManager } from './GoogleClientInfoManager'
import { FileUtil } from './FileUtil'

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
 * 基于定时查询日程最后修改时间实现增量同步
 */
export class LocalCalendarListener {
  public static GLOBAL_NAME: string = 'LocalCalendarListener'
  private ctx: Context
  private isListening: boolean = false
  private syncTimer: number = -1
  private syncInterval: number = 30000  // 同步间隔时间（毫秒），默认30秒
  private clientTimestamps: Map<string, number> = new Map()  // clientId -> lastSyncTime

  constructor(ctx: Context) {
    this.ctx = ctx
    this.loadSyncTimestamps()
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
      this.saveSyncTimestamps()
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
   * 查找
   * 只同步由GoogleCalendarDataManager管理的特定日历数据
   */
  private async performIncrementalSync() {
    hilog.info(DOMAIN, LOG_TAG, 'performIncrementalSync started')
    
    const dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
    const cliMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)

    if (!dataMgr || !cliMgr) {
      hilog.error(DOMAIN, LOG_TAG, 'performIncrementalSync: dataMgr or cliMgr is null')
      return
    }

    // 只获取由GoogleCalendarDataManager创建和管理的客户端日历
    // 这些日历是专门用于与Google日历同步的
    const managedClientCalendars = dataMgr.getClientCalendars()

    hilog.info(DOMAIN, LOG_TAG, `found ${managedClientCalendars.length} managed calendars for sync`)

    for (const clientCal of managedClientCalendars) {
      const calendar = clientCal.calendar
      const cliInfo = clientCal.cliInfo
      const clientId = cliInfo.clientId
      
      try {
        // 获取该客户端的最后同步时间
        const lastSyncTime = this.clientTimestamps.get(clientId) || 0
        hilog.info(DOMAIN, LOG_TAG, `sync client ${clientId}, lastSyncTime: ${new Date(lastSyncTime).toISOString()}`)
        
        // 获取自上次同步以来修改的事件
        const modifiedEvents = await this.getModifiedEvents(calendar, lastSyncTime)
        
        if (modifiedEvents.length > 0) {
          hilog.info(DOMAIN, LOG_TAG, `found ${modifiedEvents.length} modified events for client ${clientId}`)
          
          // 处理每个修改的事件
          for (const eventInfo of modifiedEvents) {
            // 通过获取所有事件然后过滤找到指定ID的事件
            const allEvents: calendarManager.Event[] = await calendar.getEvents()
            const event: calendarManager.Event | undefined = allEvents.find((e: calendarManager.Event) => e.id === eventInfo.eventId)
            if (event) {
              // 检查事件是否存在（通过映射关系判断是新增还是更新）
              const mapping = dataMgr.getLocalToGoogleMapping(clientId, eventInfo.eventId)
              
              if (mapping) {
                // 更新现有事件
                hilog.info(DOMAIN, LOG_TAG, `updating event ${event.title}`)
                await dataMgr.syncLocalEventToGoogle(clientId, event)
              } else {
                // 新增事件
                hilog.info(DOMAIN, LOG_TAG, `adding new event ${event.title}`)
                await dataMgr.syncLocalEventToGoogle(clientId, event)
              }
            }
          }
        }
        
        // 更新该客户端的最后同步时间
        const currentTime = Date.now()
        this.clientTimestamps.set(clientId, currentTime)
        hilog.info(DOMAIN, LOG_TAG, `updated lastSyncTime for ${clientId}: ${new Date(currentTime).toISOString()}`)
        
      } catch (err) {
        hilog.error(DOMAIN, LOG_TAG, `performIncrementalSync error for client ${clientId}: ${Error(err).message}`)
      }
    }
    
    // 保存时间戳到文件
    this.saveSyncTimestamps()
    hilog.info(DOMAIN, LOG_TAG, 'performIncrementalSync completed')
  }

  /**
   * 获取自指定时间以来修改的事件
   * @param calendar 日历对象
   * @param sinceTime 时间戳（毫秒）
   * @returns 修改的事件信息列表
   */
  private async getModifiedEvents(calendar: calendarManager.Calendar, sinceTime: number): Promise<EventLastModifiedInfo[]> {
    const modifiedEvents: EventLastModifiedInfo[] = []
    
    try {
      // 获取日历中的所有事件
      const events = await calendar.getEvents()
      
      for (const event of events) {
        // 使用事件的开始时间作为最后修改时间的近似值
        // 因为calendarManager.Event可能没有lastModified属性
        const lastModified: number = event.startTime
        
        if (lastModified > sinceTime) {
          modifiedEvents.push({
            eventId: event.id!,
            lastModified: lastModified
          })
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `getModifiedEvents failed: ${Error(err).message}`)
    }
    
    return modifiedEvents
  }

  /**
   * 手动触发同步指定事件
   * @param clientId 客户端ID
   * @param eventId 事件ID
   */
  public async syncEventToGoogle(clientId: string, eventId: number) {
    const dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
    if (!dataMgr) {
      hilog.error(DOMAIN, LOG_TAG, 'syncEventToGoogle: dataMgr is null')
      return
    }

    const calendar = dataMgr.getCalendar(clientId)
    if (!calendar) {
      hilog.error(DOMAIN, LOG_TAG, `syncEventToGoogle: calendar not found for ${clientId}`)
      return
    }

    try {
      // 通过获取所有事件然后过滤找到指定ID的事件
      const allEvents: calendarManager.Event[] = await calendar.getEvents()
      const event: calendarManager.Event | undefined = allEvents.find((e: calendarManager.Event) => e.id === eventId)
      if (event) {
        await dataMgr.syncLocalEventToGoogle(clientId, event)
        // 更新该事件的最后同步时间
        this.clientTimestamps.set(clientId, Date.now())
        this.saveSyncTimestamps()
      }
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `syncEventToGoogle error: ${Error(err).message}`)
    }
  }

  /**
   * 强制同步所有事件（全量同步）
   * @param clientId 客户端ID
   */
  public async forceSyncAllEvents(clientId: string) {
    const dataMgr: GoogleCalendarDataManager | undefined = AppStorage.get(GoogleCalendarDataManager.GLOBAL_NAME)
    if (!dataMgr) {
      hilog.error(DOMAIN, LOG_TAG, 'forceSyncAllEvents: dataMgr is null')
      return
    }

    const calendar = dataMgr.getCalendar(clientId)
    if (!calendar) {
      hilog.error(DOMAIN, LOG_TAG, `forceSyncAllEvents: calendar not found for ${clientId}`)
      return
    }

    try {
      // 清除该客户端的最后同步时间，强制下次进行全量同步
      this.clientTimestamps.set(clientId, 0)
      hilog.info(DOMAIN, LOG_TAG, `forceSyncAllEvents: cleared sync timestamp for ${clientId}`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `forceSyncAllEvents error: ${Error(err).message}`)
    }
  }

  /**
   * 获取客户端的最后同步时间
   * @param clientId 客户端ID
   * @returns 最后同步时间戳（毫秒）
   */
  public getLastSyncTime(clientId: string): number {
    return this.clientTimestamps.get(clientId) || 0
  }

  /**
   * 设置同步间隔时间
   * @param interval 同步间隔（毫秒）
   */
  public setSyncInterval(interval: number) {
    this.syncInterval = interval
    hilog.info(DOMAIN, LOG_TAG, `setSyncInterval: ${interval}ms`)
    
    // 如果正在监听，重新安排同步
    if (this.isListening && this.syncTimer !== -1) {
      clearTimeout(this.syncTimer)
      this.scheduleNextSync()
    }
  }

  /**
   * 保存同步时间戳到文件
   */
  private saveSyncTimestamps() {
    if (!this.ctx) return
    
    try {
      const filePath = this.ctx.filesDir + '/sync_timestamps.json'
      const timestamps: ClientSyncTimestamp[] = []
      
      this.clientTimestamps.forEach((timestamp, clientId) => {
        timestamps.push({
          clientId: clientId,
          lastSyncTime: timestamp
        })
      })
      
      FileUtil.writeTextFile(filePath, JSON.stringify(timestamps))
      hilog.info(DOMAIN, LOG_TAG, `saveSyncTimestamps succeed, count: ${timestamps.length}`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `saveSyncTimestamps failed: ${Error(err).message}`)
    }
  }

  /**
   * 从文件加载同步时间戳
   */
  private loadSyncTimestamps() {
    if (!this.ctx) return
    
    try {
      const filePath = this.ctx.filesDir + '/sync_timestamps.json'
      if (FileUtil.fileExists(filePath)) {
        const txtData = FileUtil.readTextFile(filePath)
        const timestamps: ClientSyncTimestamp[] = JSON.parse(txtData)
        
        timestamps.forEach(ts => {
          this.clientTimestamps.set(ts.clientId, ts.lastSyncTime)
        })
        
        hilog.info(DOMAIN, LOG_TAG, `loadSyncTimestamps succeed, count: ${timestamps.length}`)
      }
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `loadSyncTimestamps failed: ${Error(err).message}`)
    }
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
