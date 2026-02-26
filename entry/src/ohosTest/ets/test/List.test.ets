import abilityTest from './Ability.test';
import testGoogleCalendarRequests from './business/GoogleCalendarRequests.test'
import testLocalCalendarListener from './business/LocalCalendarListener.test'
import testServiceAbility from './business/ServiceAbility.test'

export default function testsuite() {
  abilityTest();
  testGoogleCalendarRequests();
  testLocalCalendarListener();
  testServiceAbility();
}