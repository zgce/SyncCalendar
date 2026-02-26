import {
  abilityAccessCtrl,
  AbilityConstant, ConfigurationConstant, Permissions, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, window } from '@kit.ArkUI';
import { url } from '@kit.ArkTS'
import { GoogleClientInfoManager } from '../business/GoogleClientInfoManager';
import { GoogleCalendarRequests } from '../business/GoogleCalendarRequests';
import { GoogleCalendarDataManager } from '../business/GoogleCalendarDataManager'
import { LocalCalendarListener } from '../business/LocalCalendarListener'

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private hasHandledIntent: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    const infosMgr = new GoogleClientInfoManager()
    infosMgr.loadFromFile(this.context.filesDir);
    AppStorage.setOrCreate(GoogleClientInfoManager.GLOBAL_NAME, infosMgr);

    const reqMgr = new GoogleCalendarRequests()
    AppStorage.setOrCreate(GoogleCalendarRequests.GLOBAL_NAME, reqMgr);

  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    const infosMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME);
    if (infosMgr) {
      infosMgr.saveToFile(this.context.filesDir);
    }
    // 停止本地日历监听
    const localListener: LocalCalendarListener | undefined = AppStorage.get(LocalCalendarListener.GLOBAL_NAME);
    if (localListener) {
      localListener.stopListening();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/IndexPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
    const permissions: Permissions[] = [
      'ohos.permission.INTERNET',
      'ohos.permission.GET_NETWORK_INFO',
      'ohos.permission.SET_NETWORK_INFO',
      'ohos.permission.READ_CALENDAR',
      'ohos.permission.WRITE_CALENDAR',
      'ohos.permission.KEEP_BACKGROUND_RUNNING',  // 保持后台运行权限
    ];
    let atMgr = abilityAccessCtrl.createAtManager()
    atMgr.requestPermissionsFromUser(this.context, permissions).then((result) => {
      hilog.info(DOMAIN, 'testTag', `requestPermissionsFromUser: ${JSON.stringify(result)}`)
      const dataMgr = new GoogleCalendarDataManager(this.context)
      AppStorage.setOrCreate(GoogleCalendarDataManager.GLOBAL_NAME, dataMgr)

      // 初始化本地日历监听器
      const localListener = new LocalCalendarListener(this.context)
      AppStorage.setOrCreate(LocalCalendarListener.GLOBAL_NAME, localListener)

      // 加载本地到Google的事件映射
      const cliMgr: GoogleClientInfoManager | undefined = AppStorage.get(GoogleClientInfoManager.GLOBAL_NAME)
      if (cliMgr) {
        cliMgr.getClientInfos().forEach((cliInfo) => {
          dataMgr.loadLocalToGoogleMapping(cliInfo.clientId)
        })
      }

      // 开始定时同步，设置同步间隔为600秒/10分钟
      const syncInterval = 30000
      localListener.startListening(syncInterval)
      hilog.info(DOMAIN, 'testTag', `LocalCalendarListener started with interval: ${syncInterval}ms`)
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', `requestPermissionsFromUser failed! ${err.code} : ${err.message}`)
    })
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    if (want.uri && want.uri.startsWith('com.fam.sync.calendar:/oauth2callback')) {
      hilog.info(DOMAIN, 'testTag', `收到授权回调 want: ${want.uri}`)
      // 1. 解析URL获取Code
      const callback = url.URL.parseURL(want.uri)
      const code = callback.params.get('code');
      const state = callback.params.get('state')
      if (code) {
        hilog.info(DOMAIN, 'testTag', '成功获取授权码:%{public}s state: %{public}s', code, state)

        // 2. 将 code 保存或发送给你的后台服务器
        // 注意：出于安全考虑，不应该在前端直接用 code 换 token，
        // 应该将 code 发送到你自己的服务器，由服务器去 Google 换 token。
        // 如果是测试，也可以在前端通过 HTTPS 请求直接换（不推荐用于生产环境）。

        // 3. 跳转回主页面
        router.replaceUrl({ url: 'pages/IndexPage', params: { needReload: true} })
      } else {
        hilog.error(DOMAIN, 'testTag', '授权失败，未获取到Code');
      }
    }
  }
}