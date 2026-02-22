import workScheduler from '@ohos.resourceschedule.workScheduler';
import { Ability } from '@kit.AbilityKit';

export default class ServiceAbility extends Ability {
  onStart() {
    this.registerSyncTask();
  }

  private registerSyncTask() {
    //TODO 注册定时任务
  }
}