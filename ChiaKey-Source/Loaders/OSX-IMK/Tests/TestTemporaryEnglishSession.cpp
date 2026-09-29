#include "../OVCTemporaryEnglishSession.h"
#include <cassert>
#include <cstdio>

int main() {
  OVCTemporaryEnglishSession session;
  const char *chiaKey = "com.chiakey.inputmethod.ChiaKeyDev.Hant";
  session.updateInputSource(chiaKey);
  session.activateApplication(100);
  assert(!session.enabled());
  session.setEnabled(true);

  // Excel advancing cells / Spotlight replacing its text client must retain
  // English, including multiple new controllers in the same application.
  session.activateApplication(100);
  session.activateApplication(100);
  assert(session.enabled());
  // Recorded Excel sequence: activate the next client, then receive two
  // selected-source notifications with the very same input-source ID.
  assert(!session.updateInputSource(chiaKey));
  assert(session.enabled());
  assert(!session.updateInputSource(chiaKey));
  assert(session.enabled());
  assert(!session.updateInputSource(nullptr));
  assert(!session.updateInputSource(""));
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
  assert(session.updateInputSource("com.apple.keylayout.ABC"));
  assert(!session.enabled());
  assert(session.updateInputSource(chiaKey));  // switch back to ChiaKey
  session.activateApplication(100);
  assert(!session.enabled());

  session.setEnabled(true);
  // A delayed duplicate after activation must not undo a fresh Shift toggle.
  assert(!session.updateInputSource(chiaKey));
  assert(session.enabled());

  // Recorded overlay sequence: the frontmost PID remains Excel throughout.
  session.activateApplication(100, "com.microsoft.Excel");
  session.setEnabled(true);
  session.activateApplication(100, "com.microsoft.Excel");
  assert(session.enabled());
  session.activateApplication(100, "com.apple.Spotlight");
  assert(!session.enabled());
  session.setEnabled(true);
  session.activateApplication(100, "com.apple.Spotlight");
  session.updateInputSource(chiaKey);
  assert(session.enabled());  // Spotlight's own client replacement
  session.activateApplication(100, nullptr);
  assert(session.enabled());  // unavailable identity is not an app switch
  session.activateApplication(100, "com.microsoft.Excel");
  assert(!session.enabled());  // closing Spotlight also starts in Chinese

  std::puts("Temporary English session tests passed.");
}
