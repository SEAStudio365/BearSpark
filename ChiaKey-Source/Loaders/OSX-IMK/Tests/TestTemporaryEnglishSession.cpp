#include "../OVCTemporaryEnglishSession.h"
#include <cassert>
#include <cstdio>

int main() {
  OVCTemporaryEnglishSession session;
  session.activateApplication(100);
  assert(!session.enabled());
  session.setEnabled(true);

  // Excel advancing cells / Spotlight replacing its text client must retain
  // English, including multiple new controllers in the same application.
  session.activateApplication(100);
  session.activateApplication(100);
  assert(session.enabled());
  session.setEnabled(!session.enabled());
  assert(!session.enabled());

  session.setEnabled(true);
  session.activateApplication(200);
  assert(!session.enabled());
  session.setEnabled(true);
  session.deactivateApplication(100);  // outgoing app's late notification
  assert(session.enabled());
  session.activateApplication(100);
  assert(!session.enabled());  // returning does not restore English

  session.setEnabled(true);
  session.deactivateApplication(100);
  // An intervening app without a text client never calls activateApplication.
  session.activateApplication(100);
  assert(!session.enabled());

  session.setEnabled(true);
  session.inputSourceChanged();  // switch to a system English input source
  assert(!session.enabled());
  session.inputSourceChanged();  // switch back to ChiaKey
  session.activateApplication(100);
  assert(!session.enabled());

  std::puts("Temporary English session tests passed.");
}
