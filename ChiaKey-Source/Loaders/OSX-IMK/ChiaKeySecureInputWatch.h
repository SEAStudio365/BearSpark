//
//  ChiaKeySecureInputWatch.h
//
//  Spots loginwindow leaving Secure Event Input on after the user is already
//  in. While any process holds it, macOS greys every third-party input method
//  out of the input menu; loginwindow enables it once per lock-screen redraw
//  but disables it only once on unlock, so lock/unlock does not clear it and
//  only logging out does. Seen on macOS 26.7.1 right after an OS update.
//
//  Header-only and free of C++ and of the loader, so the policy can be tested
//  on its own (Scripts/test-secure-input-watch.sh).
//

#ifndef CHIAKEY_SECURE_INPUT_WATCH_H_
#define CHIAKEY_SECURE_INPUT_WATCH_H_

#import <Foundation/Foundation.h>
#include <sys/types.h>

// loginwindow drops its hold within milliseconds of a normal unlock, so a hold
// that survives the first delay is suspicious and one that survives both is
// treated as stuck. Two looks keep a slow unlock from ever raising a warning.
#define kChiaKeySecureInputFirstCheckDelay 10.0
#define kChiaKeySecureInputConfirmDelay 20.0

typedef struct {
  pid_t holderPID;  // 0 when nobody holds Secure Event Input
  BOOL screenLocked;
  BOOL onConsole;
} ChiaKeySecureInputSession;

static inline BOOL ChiaKeySecureInputBoolValue(id value) {
  return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// Reads the dictionary CGSessionCopyCurrentDictionary() answers.
static inline ChiaKeySecureInputSession ChiaKeySecureInputSessionFromDictionary(
    NSDictionary *session) {
  ChiaKeySecureInputSession result = {0, NO, NO};
  id pid = [session objectForKey:@"kCGSSessionSecureInputPID"];
  if ([pid isKindOfClass:[NSNumber class]]) result.holderPID = [pid intValue];
  // The lock key has shipped under both spellings.
  result.screenLocked =
      ChiaKeySecureInputBoolValue(
          [session objectForKey:@"CGSSessionScreenIsLocked"]) ||
      ChiaKeySecureInputBoolValue(
          [session objectForKey:@"kCGSSessionScreenIsLocked"]);
  result.onConsole = ChiaKeySecureInputBoolValue(
      [session objectForKey:@"kCGSSessionOnConsoleKey"]);
  return result;
}

static inline BOOL ChiaKeySecureInputPathIsLoginwindow(NSString *path) {
  return [[path lastPathComponent] isEqualToString:@"loginwindow"];
}

// loginwindow holding it is expected while the screen is locked or another
// user owns the console; only an unlocked session of ours counts as stuck.
static inline BOOL ChiaKeySecureInputIsStuck(ChiaKeySecureInputSession session,
                                             NSString *holderPath) {
  if (session.holderPID <= 0) return NO;
  if (session.screenLocked || !session.onConsole) return NO;
  return ChiaKeySecureInputPathIsLoginwindow(holderPath);
}

typedef enum {
  ChiaKeySecureInputWatchIdle = 0,
  ChiaKeySecureInputWatchSuspected,
  ChiaKeySecureInputWatchWarned,
} ChiaKeySecureInputWatchPhase;

typedef enum {
  ChiaKeySecureInputWatchNone = 0,
  ChiaKeySecureInputWatchScheduleConfirm,
  ChiaKeySecureInputWatchShowWarning,
  ChiaKeySecureInputWatchHideWarning,
} ChiaKeySecureInputWatchAction;

// One step per check. The warning shows once per stuck episode: dismissing it
// leaves the phase at Warned, so later unlocks do not nag again until a check
// sees the hold gone.
static inline ChiaKeySecureInputWatchAction ChiaKeySecureInputWatchAdvance(
    ChiaKeySecureInputWatchPhase *phase, BOOL stuck) {
  if (!stuck) {
    BOOL wasWarned = *phase == ChiaKeySecureInputWatchWarned;
    *phase = ChiaKeySecureInputWatchIdle;
    return wasWarned ? ChiaKeySecureInputWatchHideWarning
                     : ChiaKeySecureInputWatchNone;
  }

  switch (*phase) {
    case ChiaKeySecureInputWatchIdle:
      *phase = ChiaKeySecureInputWatchSuspected;
      return ChiaKeySecureInputWatchScheduleConfirm;
    case ChiaKeySecureInputWatchSuspected:
      *phase = ChiaKeySecureInputWatchWarned;
      return ChiaKeySecureInputWatchShowWarning;
    case ChiaKeySecureInputWatchWarned:
      return ChiaKeySecureInputWatchNone;
  }
  return ChiaKeySecureInputWatchNone;
}

// A lock (or a new unlock) restarts the look: a suspicion from before it says
// nothing about the session after it. A warning already shown stays shown.
static inline void ChiaKeySecureInputWatchRestart(
    ChiaKeySecureInputWatchPhase *phase) {
  if (*phase == ChiaKeySecureInputWatchSuspected)
    *phase = ChiaKeySecureInputWatchIdle;
}

// osascript's "User canceled." (-128) means the logout dialog came up and the
// user said no, which is not a failure to report.
static inline BOOL ChiaKeyLogoutRequestSucceeded(int status, NSString *output) {
  if (status == 0) return YES;
  return output && [output rangeOfString:@"(-128)"].location != NSNotFound;
}

#endif  // CHIAKEY_SECURE_INPUT_WATCH_H_
