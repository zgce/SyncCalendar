import { GoogleCalendarEventObj, GoogleCalendarEventListObj, GoogleCalendarRequests,
  ReminderOverrideObj } from './GoogleCalendarRequests'
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
      const calendarEvent = this.convertGoogleEvent(evt)
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
      const calendarEvent = this.convertGoogleEvent(evt)
      if (calendarEvent.id) {
        await calendar?.deleteEvent(calendarEvent.id)
        localEvents.delete(evt.id)
        hilog.info(DOMAIN, LOG_TAG, `deleteEvent(${evt.id}:${calendarEvent.id}) succeed`)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `deleteEvent(${evt.id}) failed, calendarEvent.id is empty`)
      }
    }
    for (const evt of updatedEvents) {
      const calendarEvent = this.convertGoogleEvent(evt)
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

  public async createGoogleCalendar(cliInfo: GoogleClientInfo) {
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

  public async syncLocalEvents(cliId: string, accessToken: string) {
    const calendar = this.cliCals.get(cliId)?.calendar
    if (!calendar) {
      hilog.error(DOMAIN, LOG_TAG, `the client ${cliId} calendar is undefined`)
      return;
    }
    const clientInfo = this.cliCals.get(cliId)?.cliInfo
    if (!clientInfo) {
      hilog.error(DOMAIN, LOG_TAG, `the client ${cliId} clientInfo is undefined`)
      return;
    }
    const reqMgr: GoogleCalendarRequests | undefined = AppStorage.get(GoogleCalendarRequests.GLOBAL_NAME);
    if (!reqMgr) {
      hilog.error(DOMAIN, LOG_TAG, `for ${cliId} get GoogleCalendarRequests is undefined`)
      return;
    }
    // 从日历里获取前后90天的事件
    const now = new Date()
    const end = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000)
    const start = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000)
    const filter = calendarManager.EventFilter.filterByTime(start.getTime(), end.getTime())
    const calEvents = await calendar.getEvents(filter)
    hilog.info(DOMAIN, LOG_TAG, `getEvents from calendar(${clientInfo.name}) ${start.getTime()} - ${now.getTime()}, count: ${calEvents.length}`)
    // 读取本地的事件列表
    const filePath = this.makeFilePath(cliId)
    const localEvents = this.loadFromFile(filePath)
    // 构造日历事件ID为Key的Map，方便后续查找
    const calEvtMap = new Map<number, GoogleCalendarEventObj>()
    for (const localEvt of localEvents.values()) {
      if (localEvt.calEvtId) {
        calEvtMap.set(localEvt.calEvtId, localEvt)
      }
    }
    // 构建增、删、改列表，供后续比对时使用
    const addedEvents = new Array<calendarManager.Event>()
    const deletedEvents = new Array<GoogleCalendarEventObj>()
    const updatedEvents = new Array<calendarManager.Event>()
    const calIds = new Set<number>()
    for (const calEvt of calEvents) {
      if (calEvt.id) {
        const findEvt = calEvtMap.get(calEvt.id)
        if (!findEvt) {
          addedEvents.push(calEvt)
          hilog.debug(DOMAIN, LOG_TAG, `calendar ${clientInfo.name} find new event(${calEvt.id}), will add it.`)
        } else {
          if (this.isEventChanged(findEvt, calEvt)) {
            updatedEvents.push(calEvt)
            hilog.debug(DOMAIN, LOG_TAG, `calendar ${clientInfo.name} find update event(CalId: ${calEvt.id}, GoogleId: ${findEvt.id}), will update it.`)
          }
        }
        calIds.add(calEvt.id)
      }
    }

    for (const localEvt of calEvtMap.values()) {
      if (!calIds.has(localEvt.calEvtId)) {
        deletedEvents.push(localEvt)
        hilog.debug(DOMAIN, LOG_TAG, `calendar ${clientInfo.name} find delete event(CalId: ${localEvt.calEvtId}, GoogleId: ${localEvt.id}), will delete it.`)
      }
    }
    // 处理删除、添加、修改
    for (const evt of deletedEvents) {
      const ret = await reqMgr.deleteCalendarEvent(clientInfo, accessToken, evt.id)
      if (ret) {
        localEvents.delete(evt.id)
        hilog.info(DOMAIN, LOG_TAG, `delete google event ${evt.id}`)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `delete google event ${evt.id} failed!`)
      }
    }
    for (const calEvt of addedEvents) {
      const createEvt = this.convertLocalEvent(calEvt)
      const googleEvt = await reqMgr.createCalendarEvent(clientInfo, accessToken, createEvt)
      if (googleEvt && calEvt.id) {
        googleEvt.calEvtId = calEvt.id
        localEvents.set(googleEvt.id, googleEvt)
        hilog.info(DOMAIN, LOG_TAG, `add google event ${googleEvt.id} successed!`)
      } else {
        hilog.error(DOMAIN, LOG_TAG, `add google event ${calEvt.id} failed!`)
      }
    }
    for (const calEvt of updatedEvents) {
      if (calEvt.id) {
        const googleEvt = calEvtMap.get(calEvt.id)
        if(googleEvt) {
          const updateEvt = this.updateGoogleEvent(calEvt, googleEvt)
          const finalEvt = await reqMgr.updateCalendarEvent(clientInfo, accessToken, updateEvt.id, updateEvt)
          if (finalEvt) {
            finalEvt.calEvtId = calEvt.id
            localEvents.set(finalEvt.id, finalEvt)
            hilog.info(DOMAIN, LOG_TAG, `update google event ${googleEvt.id} successed!`)
          } else {
            hilog.error(DOMAIN, LOG_TAG, `update google event ${googleEvt.id} failed!`)
          }
        }
      }
    }
    // 更新完成后保存本地事件列表
    this.saveToFile(filePath, localEvents)
  }

  public removeClientData(cliId: string) {
    const filePath = this.makeFilePath(cliId)
    FileUtil.deleteFile(filePath)
    hilog.info(DOMAIN, LOG_TAG, `remove client ${cliId} data ${filePath} succeed`)
  }

  private isEventChanged(localEvt: GoogleCalendarEventObj, calEvt: calendarManager.Event): boolean {
    let isChanged = false;

    if (localEvt.summary !== calEvt.title) {
      isChanged = true;
    }

    if (!isChanged && (localEvt.description !== calEvt.description)) {
      isChanged = true;
    }

    if (!isChanged && (localEvt.location !== calEvt.location?.location)) {
      isChanged = true;
    }
    if (!isChanged && (calEvt.isAllDay)) {
      const startTime = new Date(calEvt.startTime)
      const endTime = new Date(calEvt.endTime)
      if(localEvt.start.date && localEvt.end.date) {
        const localStart = new Date(localEvt.start.date)
        const localEnd = new Date(localEvt.end.date)
        isChanged = localStart.getTime() !== startTime.getTime() || localEnd.getTime() !== endTime.getTime()
      } else {
        isChanged = false;
      }
    }
    if (!isChanged && (!calEvt.isAllDay)) {
      const startTime = new Date(calEvt.startTime)
      const endTime = new Date(calEvt.endTime)
      if(localEvt.start.dateTime && localEvt.end.dateTime) {
        const localStart = new Date(localEvt.start.dateTime)
        const localEnd = new Date(localEvt.end.dateTime)
        isChanged = localStart.getTime() !== startTime.getTime() || localEnd.getTime() !== endTime.getTime()
      } else {
        isChanged = false;
      }
    }

    if (!isChanged && (calEvt.reminderTime && calEvt.reminderTime.length > 0)) {
      if (localEvt.reminders.overrides) {
        for (const remind of localEvt.reminders.overrides) {
          if(!calEvt.reminderTime.find((minutes) => minutes === remind.minutes)) {
            isChanged = false;
          }
        }
      } else {
        isChanged = true;
      }
    }

    return isChanged;
  }

  private updateGoogleEvent(calEvent: calendarManager.Event, googleEvent: GoogleCalendarEventObj): GoogleCalendarEventObj {
    googleEvent.summary = calEvent.title ? calEvent.title : ''
    googleEvent.description = calEvent.description ? calEvent.description : ''
    if (calEvent.location && calEvent.location.location) {
      googleEvent.location = calEvent.location.location
    }
    if (calEvent.isAllDay) {
      googleEvent.start.date = (new Date(calEvent.startTime)).toISOString().substring(0, 10)
      googleEvent.end.date = (new Date(calEvent.endTime)).toISOString().substring(0, 10)
      googleEvent.start.dateTime = undefined
      googleEvent.end.dateTime = undefined
    } else {
      googleEvent.start.dateTime = (new Date(calEvent.startTime)).toISOString()
      googleEvent.end.dateTime = (new Date(calEvent.endTime)).toISOString()
      googleEvent.start.date = undefined
      googleEvent.end.date = undefined
    }
    if (calEvent.timeZone) {
      googleEvent.start.timeZone = calEvent.timeZone
      googleEvent.end.timeZone = calEvent.timeZone
    }
    if (calEvent.reminderTime && calEvent.reminderTime.length > 0) {
      googleEvent.reminders.overrides = new Array<ReminderOverrideObj>()
      for (const minutes of calEvent.reminderTime) {
        googleEvent.reminders.useDefault = false
        googleEvent.reminders.overrides.push({ method: 'popup', minutes: minutes })
      }
    }
    return googleEvent
  }

  private emptyGoogleEvent(): GoogleCalendarEventObj {
    return {
      kind: 'calendar#event',
      etag: '',
      id: '',
      status: 'confirmed',
      htmlLink: '',
      created: '',
      updated: '',
      summary: '',
      description: '',
      location: '',
      creator: { email: '', displayName: '' },
      organizer: { email: '', displayName: ''},
      start: { dateTime: '', timeZone: '' },
      end : { dateTime: '', timeZone: '' },
      iCalUID: '',
      sequence: 0,
      eventType: 'default',
      reminders: { useDefault: true, overrides: [] },
      calEvtId: -1
    }
  }

  /**
   * 将本地事件转换为Google事件创建格式
   */
  private convertLocalEvent(localEvent: calendarManager.Event): GoogleCalendarEventObj {
    const startDate = new Date(localEvent.startTime)
    const endDate = new Date(localEvent.endTime)

    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    const googleEvent = this.emptyGoogleEvent()
    googleEvent.summary = localEvent.title || ''
    googleEvent.description = localEvent.description || ''
    googleEvent.location = localEvent.location?.location || ''
    googleEvent.calEvtId = localEvent?.id || -1
    if (localEvent.isAllDay) {
      googleEvent.start = {
        date: startDate.toISOString().substring(0, 10),
        timeZone: tz
      }
      googleEvent.end = {
        date: endDate.toISOString().substring(0, 10),
        timeZone: tz
      }
    } else {
      googleEvent.start = {
        dateTime: startDate.toISOString(),
        timeZone: tz
      }
      googleEvent.end = {
        dateTime: endDate.toISOString(),
        timeZone: tz
      }
    }
    if (localEvent.reminderTime && localEvent.reminderTime.length > 0) {
      googleEvent.reminders.useDefault = false
      for (const reminderTime of localEvent.reminderTime) {
        googleEvent.reminders.overrides?.push({
          method: 'popup',
          minutes: reminderTime
        })
      }
    }
    return googleEvent
  }

  /**
   * 将Google事件转换为本地事件类型
   * @param evt 从Google获取到的事件
   * @returns 本地事件类型
   */
  private convertGoogleEvent(evt: GoogleCalendarEventObj): calendarManager.Event {
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

    const calendarEvent: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: evt.summary,
      startTime: startTime.getTime(),
      endTime: endTime.getTime(),
      timeZone: evt.start.timeZone,
      description: evt.description,
      isAllDay: allDayFlag,
      location: evt.location ? { location: evt.location } : undefined,
    }
    if (evt.calEvtId) {
      calendarEvent.id = evt.calEvtId
    }
    if (evt.reminders && evt.reminders.overrides && evt.reminders.overrides.length > 0 && evt.reminders.overrides[0].minutes) {
      const reminderMinutes = Array<number>()
      for (const item of evt.reminders.overrides) {
        if (item.minutes) {
          reminderMinutes.push(item.minutes)
        }
      }
      if (reminderMinutes.length > 0)
      calendarEvent.reminderTime = reminderMinutes
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