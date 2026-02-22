import abilityTest from './Ability.test';
import testGoogleCalendarRequests from './business/GoogleCalendarRequests.test'

export default function testsuite() {
  abilityTest();
  testGoogleCalendarRequests()
}