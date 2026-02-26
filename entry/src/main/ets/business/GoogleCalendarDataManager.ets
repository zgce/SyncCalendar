import { GoogleCalendarEventObj, GoogleCalendarEventListObj, GoogleCalendarEventCreateObj, GoogleCalendarRequests } from './GoogleCalendarRequests'
import { FileUtil } from './FileUtil'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { calendarManager } from '@kit.CalendarKit'
import { GoogleClientInfo, GoogleClientInfoManager } from './GoogleClientInfoManager'

const DOMAIN = 0x0001;
const LOG_TAG = "CalDataMgrTag"

/**
 * 每一个Google配置对应一个日历
 */
interface ClientCalendar {
  cliInfo: GoogleClientInfo
  calendar: calendarManager.Calendar
}

/**
 * 本地事件与Google事件的映射关系
 */
interface LocalToGoogleEventMap {
  calEvtId: number        // 本地日历事件ID
  googleEventId: string   // Google事件ID
  lastSyncTime: number    // 最后同步时间戳
}

/**
 * 管理从Google获取到的日历数据
 */
export class GoogleCalendarDataManager {
  public static GLOBAL_NAME: string = 'GoogleCalendarDataManager'
  private ctx: Context | undefined = undefined
  private cliCals = new Map<string, ClientCalendar>() // 每一个ClientID对应一个日历
  private localToGoogleMap = new Map<string, Map<number, LocalToGoogleEventMap>>() // clientId -> (calEvtId -> mapping)

  constructor(ctx: Context) {
    this.ctx = ctx
    const calMgr = calendarManager.getCalendarManager(this.ctx)
    hilog.info(DOMAIN, LOG_TAG, 'getCalendarManager() succeed')
    this.getOrCreateGoogleCalendar(calMgr).catch(() => {
      hilog.error(DOMAIN, LOG_TAG, 'getOrCreateGoogleCalendar() failed!')
    })
  }

  /**
   * 合并事件
   * @param cliId 需要合并的客户端ID
   * @param googleEventList 需要合并的事件列表
   */
  public async mergeEvents(cliId: string, googleEventList: GoogleCalendarEventListObj) {
    // 读取本地的事件列表
    const filePath = this.makeFilePath(cliId)
    const localEvents = this.loadFromFile(filePath)
    hilog.info(DOMAIN, LOG_TAG, `mergeEvents(${cliId}) start remote events: ${googleEventList.items.length}, local events: ${localEvents.size}`)
    // 构建增、删、改列表，供后续比对时使用
    const addedEvents = new Array<GoogleCalendarEventObj>()
    const deletedEvents = new Array<GoogleCalendarEventObj>()
    const updatedEvents = new Array<GoogleCalendarEventObj>()
    // 传入事件与本地事件比对
    googleEventList.items.forEach(evt => {
      const findEvt = localEvents.get(evt.id)
      if (findEvt) {
        const localUpdateTime = new Date(findEvt.updated)
        const googleUpdateTime = new Date(evt.updated)
        if (localUpdateTime < googleUpdateTime) {
          evt.calEvtId = findEvt.calEvtId
          updatedEvents.push(evt)
        }
      } else {
        addedEvents.push(evt)
      }
    })
    // 删除本地事件列表中不存在的事件
    localEvents.forEach((evt, id) => {
      const findEvt = googleEventList.items.find(item => item.id === id)
      if (!findEvt) {
        deletedEvents.push(evt)
      }
    })
    // 处理增、删、改事件到日历中，本地数据也需要更新
    const calendar = this.cliCals.get(cliId)?.calendar
    for (const evt of addedEvents) {
      const calendarEvent = this.convertEvent(evt)
      const id = await calendar?.addEvent(calendarEvent)
      if (id) {
        hilog.info(DOMAIN, LOG_TAG, `addEvent(${evt.id}: ${evt.summary}) succeed, id: ${id}`)
        evt.calEvtId = id // 日历事件ID更新到本地事件中
        localEvents.set(evt.id, evt)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `addEvent(${JSON.stringify(evt)}) failed!`)
      }
    }
    for (const evt of deletedEvents) {
      const calendarEvent = this.convertEvent(evt)
      if (calendarEvent.id) {
        await calendar?.deleteEvent(calendarEvent.id)
        localEvents.delete(evt.id)
        hilog.info(DOMAIN, LOG_TAG, `deleteEvent(${evt.id}:${calendarEvent.id}) succeed`)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `deleteEvent(${evt.id}) failed, calendarEvent.id is empty`)
      }
    }
    for (const evt of updatedEvents) {
      const calendarEvent = this.convertEvent(evt)
      if (calendarEvent.id) {
        await calendar?.updateEvent(calendarEvent)
        localEvents.set(evt.id, evt)
        hilog.info(DOMAIN, LOG_TAG, `updateEvent(${evt.id}:${calendarEvent.id}) succeed`)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `updateEvent(${evt.id}) failed, calendarEvent.id is empty`)
      }
    }
    this.saveToFile(filePath, localEvents)
  }

  async createGoogleCalendar(cliInfo: GoogleClientInfo) {
    const account: calendarManager.CalendarAccount = {
      name: cliInfo.clientId,
      type: calendarManager.CalendarType.LOCAL,
      displayName: cliInfo.name
    }
    const calMgr = calendarManager.getCalendarManager(this.ctx)
    if (calMgr) {
      hilog.info(DOMAIN, LOG_TAG, 'in createGoogleCalendar getCalendarManager() succeed')
      try {
        const calendar = await calMgr.createCalendar(account)
        if (calendar) {
          this.cliCals.set(cliInfo.clientId, { cliInfo: cliInfo, calendar: calendar })
          hilog.info(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) succeed`)
        }
      } catch (err) {
        hilog.error(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) failed! errmsg: ${Error(err).message}`)
      }
    }
  }

  /**
   * 初始化日历或创建日历，初始化完成后，cliCals中会包含所有日历
   */
  private async getOrCreateGoogleCalendar(calMgr: calendarManager.CalendarManager) {
    const cliMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
    if (cliMgr) {
      cliMgr.getClientInfos().forEach(async (cliInfo) => {
        const account: calendarManager.CalendarAccount = {
          name: cliInfo.clientId,
          type: calendarManager.CalendarType.LOCAL,
          displayName: cliInfo.name
        }
        try {
          let existCalendar: calendarManager.Calendar | undefined
          try {
            existCalendar = await calMgr.getCalendar(account)
          } catch (err) {
            hilog.error(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) failed! errmsg: ${Error(err).message}`)
          }

          if (!existCalendar) {
            hilog.info(DOMAIN, LOG_TAG, `can't find existCalendar by ${cliInfo.clientId}:${cliInfo.name}, try to create it...`)
            const newCalendar = await calMgr.createCalendar(account)
            if (newCalendar) {
              hilog.info(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) succeed`)
              this.cliCals.set(cliInfo.clientId, { cliInfo: cliInfo, calendar: newCalendar })
            } else {
              hilog.error(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) failed!`)
            }
          } else {
            this.cliCals.set(cliInfo.clientId, { cliInfo: cliInfo, calendar: existCalendar })
            hilog.info(DOMAIN, LOG_TAG, `get existCalendar by ${cliInfo.clientId}:${cliInfo.name} succeed`)
          }
        } catch (err) {
          hilog.error(DOMAIN, LOG_TAG, `createCalendar(${cliInfo.clientId}:${cliInfo.name}) failed! errmsg: ${Error(err).message}`)
        }
      })
    }
  }

  /**
   * 获取指定客户端ID的日历对象
   * @param clientId 客户端ID
   * @returns 日历对象
   */
  public getCalendar(clientId: string): calendarManager.Calendar | undefined {
    return this.cliCals.get(clientId)?.calendar
  }

  /**
   * 获取所有客户端日历配置
   * @returns 客户端日历配置列表
   */
  public getClientCalendars(): ClientCalendar[] {
    return Array.from(this.cliCals.values())
  }

  /**
   * 将本地新建的事件同步到Google日历
   * @param clientId 客户端ID
   * @param localEvent 本地事件
   * @returns Google事件ID，失败返回undefined
   */
  public async syncLocalEventToGoogle(clientId: string, localEvent: calendarManager.Event): Promise<string | undefined> {
    const clientCalendar = this.cliCals.get(clientId)
    if (!clientCalendar) {
      hilog.error(DOMAIN, LOG_TAG, `syncLocalEventToGoogle: client ${clientId} not found`)
      return undefined
    }

    const localEventId = localEvent.id
    if (localEventId === undefined) {
      hilog.error(DOMAIN, LOG_TAG, `syncLocalEventToGoogle: localEvent.id is undefined`)
      return undefined
    }

    const cliInfo = clientCalendar.cliInfo
    const reqMgr = new GoogleCalendarRequests()
    const accessToken = await reqMgr.getAccessToken(cliInfo)
    if (!accessToken) {
      hilog.error(DOMAIN, LOG_TAG, `syncLocalEventToGoogle: getAccessToken failed for ${clientId}`)
      return undefined
    }

    // 检查是否已存在映射
    const mapping = this.getLocalToGoogleMapping(clientId, localEventId)
    if (mapping) {
      // 已存在映射，执行更新
      const eventData = this.convertLocalEventToGoogle(localEvent)
      const updatedEvent = await reqMgr.updateCalendarEvent(cliInfo, accessToken, mapping.googleEventId, eventData)
      if (updatedEvent) {
        this.updateLocalToGoogleMapping(clientId, localEventId, mapping.googleEventId)
        await this.saveLocalToGoogleMapping(clientId)
        hilog.info(DOMAIN, LOG_TAG, `syncLocalEventToGoogle: update event ${localEventId} succeed`)
        return mapping.googleEventId
      }
      return undefined
    }

    // 新建事件
    const eventData = this.convertLocalEventToGoogle(localEvent)
    const createdEvent = await reqMgr.createCalendarEvent(cliInfo, accessToken, eventData)
    if (createdEvent) {
      // 保存映射关系
      this.addLocalToGoogleMapping(clientId, localEventId, createdEvent.id)
      await this.saveLocalToGoogleMapping(clientId)

      // 更新本地事件文件
      const filePath = this.makeFilePath(clientId)
      const localEvents = this.loadFromFile(filePath)
      const newEvent: GoogleCalendarEventObj = {
        kind: 'calendar#event',
        etag: createdEvent.etag,
        id: createdEvent.id,
        status: 'confirmed',
        htmlLink: createdEvent.htmlLink,
        created: createdEvent.created,
        updated: createdEvent.updated,
        summary: localEvent.title || '',
        description: localEvent.description || '',
        location: localEvent.location?.location || '',
        creator: createdEvent.creator,
        organizer: createdEvent.organizer,
        start: createdEvent.start,
        end: createdEvent.end,
        iCalUID: createdEvent.iCalUID,
        sequence: createdEvent.sequence,
        eventType: createdEvent.eventType,
        calEvtId: localEventId
      }
      localEvents.set(createdEvent.id, newEvent)
      this.saveToFile(filePath, localEvents)

      hilog.info(DOMAIN, LOG_TAG, `syncLocalEventToGoogle: create event ${localEventId} -> ${createdEvent.id} succeed`)
      return createdEvent.id
    }
    return undefined
  }

  /**
   * 从Google日历删除事件
   * @param clientId 客户端ID
   * @param localEventId 本地事件ID
   * @returns 是否删除成功
   */
  public async deleteEventFromGoogle(clientId: string, localEventId: number): Promise<boolean> {
    const mapping = this.getLocalToGoogleMapping(clientId, localEventId)
    if (!mapping) {
      hilog.warn(DOMAIN, LOG_TAG, `deleteEventFromGoogle: no mapping found for localEvent ${localEventId}`)
      return true // 没有映射说明不需要删除
    }

    const clientCalendar = this.cliCals.get(clientId)
    if (!clientCalendar) {
      hilog.error(DOMAIN, LOG_TAG, `deleteEventFromGoogle: client ${clientId} not found`)
      return false
    }

    const cliInfo = clientCalendar.cliInfo
    const reqMgr = new GoogleCalendarRequests()
    const accessToken = await reqMgr.getAccessToken(cliInfo)
    if (!accessToken) {
      hilog.error(DOMAIN, LOG_TAG, `deleteEventFromGoogle: getAccessToken failed for ${clientId}`)
      return false
    }

    const success = await reqMgr.deleteCalendarEvent(cliInfo, accessToken, mapping.googleEventId)
    if (success) {
      this.removeLocalToGoogleMapping(clientId, localEventId)
      await this.saveLocalToGoogleMapping(clientId)

      // 更新本地事件文件
      const filePath = this.makeFilePath(clientId)
      const localEvents = this.loadFromFile(filePath)
      localEvents.forEach((evt, id) => {
        if (evt.calEvtId === localEventId) {
          localEvents.delete(id)
        }
      })
      this.saveToFile(filePath, localEvents)

      hilog.info(DOMAIN, LOG_TAG, `deleteEventFromGoogle: delete event ${localEventId} succeed`)
    }
    return success
  }

  /**
   * 将本地事件转换为Google事件创建格式
   */
  private convertLocalEventToGoogle(localEvent: calendarManager.Event): GoogleCalendarEventCreateObj {
    const startDate = new Date(localEvent.startTime)
    const endDate = new Date(localEvent.endTime)

    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (localEvent.isAllDay) {
      const startDate = new Date(localEvent.startTime)
      return {
        summary: localEvent.title || '',
        description: localEvent.description || '',
        location: localEvent.location?.location || '',
        start: {
          date: startDate.toLocaleDateString(),
          timeZone: tz
        },
        end: {
          date: startDate.toLocaleDateString(),
          timeZone: tz
        }
      }
    } else {
      return {
        summary: localEvent.title || '',
        description: localEvent.description || '',
        location: localEvent.location?.location || '',
        start: {
          dateTime: startDate.toISOString(),
          timeZone: tz
        },
        end: {
          dateTime: endDate.toISOString(),
          timeZone: tz
        }
      }
    }
  }

  /**
   * 获取本地事件到Google事件的映射
   */
  public getLocalToGoogleMapping(clientId: string, localEventId: number): LocalToGoogleEventMap | undefined {
    const clientMap = this.localToGoogleMap.get(clientId)
    if (!clientMap) {
      return undefined
    }
    return clientMap.get(localEventId)
  }

  /**
   * 添加本地事件到Google事件的映射
   */
  private addLocalToGoogleMapping(clientId: string, localEventId: number, googleEventId: string) {
    let clientMap = this.localToGoogleMap.get(clientId)
    if (!clientMap) {
      clientMap = new Map<number, LocalToGoogleEventMap>()
      this.localToGoogleMap.set(clientId, clientMap)
    }
    clientMap.set(localEventId, {
      calEvtId: localEventId,
      googleEventId: googleEventId,
      lastSyncTime: Date.now()
    })
  }

  /**
   * 更新本地事件到Google事件的映射
   */
  private updateLocalToGoogleMapping(clientId: string, localEventId: number, googleEventId: string) {
    this.addLocalToGoogleMapping(clientId, localEventId, googleEventId)
  }

  /**
   * 移除本地事件到Google事件的映射
   */
  private removeLocalToGoogleMapping(clientId: string, localEventId: number) {
    const clientMap = this.localToGoogleMap.get(clientId)
    if (clientMap) {
      clientMap.delete(localEventId)
    }
  }

  /**
   * 保存本地到Google的事件映射到文件
   */
  private async saveLocalToGoogleMapping(clientId: string) {
    if (!this.ctx) {
      return
    }
    const clientMap = this.localToGoogleMap.get(clientId)
    if (!clientMap) {
      return
    }
    const filePath = this.ctx.filesDir + '/' + clientId + '_mapping.json'
    try {
      const data: Record<string, LocalToGoogleEventMap> = {}
      clientMap.forEach((value, key) => {
        data[key.toString()] = value
      })
      FileUtil.writeTextFile(filePath, JSON.stringify(data))
      hilog.info(DOMAIN, LOG_TAG, `saveLocalToGoogleMapping(${filePath}) succeed`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `saveLocalToGoogleMapping failed! ${Error(err).message}`)
    }
  }

  /**
   * 从文件加载本地到Google的事件映射
   */
  public loadLocalToGoogleMapping(clientId: string) {
    if (!this.ctx) {
      return
    }
    const filePath = this.ctx.filesDir + '/' + clientId + '_mapping.json'
    try {
      if (FileUtil.fileExists(filePath)) {
        const txtData = FileUtil.readTextFile(filePath)
        const data = JSON.parse(txtData) as Record<string, LocalToGoogleEventMap>
        const clientMap = new Map<number, LocalToGoogleEventMap>()
        Object.keys(data).forEach((key: string) => {
          clientMap.set(parseInt(key), data[key])
        })
        this.localToGoogleMap.set(clientId, clientMap)
        hilog.info(DOMAIN, LOG_TAG, `loadLocalToGoogleMapping(${filePath}) succeed, count: ${clientMap.size}`)
      }
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `loadLocalToGoogleMapping failed! ${Error(err).message}`)
    }
  }

  /**
   * 将Google事件转换为本地事件类型
   * @param evt 从Google获取到的事件
   * @returns 本地事件类型
   */
  private convertEvent(evt: GoogleCalendarEventObj): calendarManager.Event {
    let startTime = new Date();
    let endTime = new Date();
    let allDayFlag: boolean = false
    if (evt.end.date && evt.start.date) {
      allDayFlag = true
      startTime = new Date(evt.start.date)
      endTime = new Date(evt.end.date)
    }
    if (evt.start.dateTime && evt.end.dateTime) {
      startTime = new Date(evt.start.dateTime)
      endTime = new Date(evt.end.dateTime)
    }
    hilog.debug(DOMAIN, LOG_TAG, `convertEvent: all day event, start: ${startTime}, end: ${endTime} milliseconds ${startTime.getTime()} ${endTime.getTime()}`)

    const calendarEvent: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: evt.summary,
      startTime: startTime.getTime(),
      endTime: endTime.getTime(),
      description: evt.description,
      isAllDay: allDayFlag,
      location: evt.location ? { location: evt.location } : undefined,
    }
    if (evt.calEvtId) {
      calendarEvent.id = evt.calEvtId
    }
    return calendarEvent
  }

  /**
   * 从本地文件里加载事件列表
   * @param filePath 路径
   * @returns 事件列表 Map<id, event>，注意这个ID为Google事件ID非日历事件ID
   */
  private loadFromFile(filePath: string): Map<string, GoogleCalendarEventObj> {
    let result = new Map<string, GoogleCalendarEventObj>()
    try {
      if (FileUtil.fileExists(filePath)) {
        const txtData = FileUtil.readTextFile(filePath)
        const arrayData = JSON.parse(txtData) as Array<GoogleCalendarEventObj>
        if (arrayData.length && arrayData.length > 0) {
          for (const item of arrayData) {
            result.set(item.id, item)
          }
        }
        hilog.info(DOMAIN, LOG_TAG, `loadFromFile(${filePath}) succeed, eventCount: ${result.size}`)
      }
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `loadFromFile(${filePath}) failed! errmsg: ${Error(err).message}`)
    }
    return result
  }

  private saveToFile(filePath: string, data: Map<string, GoogleCalendarEventObj>) {
    try {
      const arrayData: Array<GoogleCalendarEventObj> = Array.from(data.values())
      FileUtil.writeTextFile(filePath, JSON.stringify(arrayData))
      hilog.info(DOMAIN, LOG_TAG, `saveToFile(${filePath}) length ${data.size} succeed`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `saveToFile(${filePath}) length ${data.size} failed! errmsg: ${Error(err).message}`)
    }
  }

  private makeFilePath(cliId: string): string {
    return this.ctx?.filesDir + '/' + cliId + '.json'
  }

}