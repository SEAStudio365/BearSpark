// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

// Non-modal: the IMK thread is this process's main thread, so a modal alert
// here would stall every client still talking to the input method.
@interface CVSecureInputWarningController : NSObject {
  NSPanel *_panel;
  NSTextField *_messageField;
  NSButton *_logoutButton;
  // Only one is active: beside the logout button, or alone at the edge once
  // the logout button is hidden.
  NSLayoutConstraint *_laterBesideLogout;
  NSLayoutConstraint *_laterAtTrailingEdge;
  // Bumped on every show and hide so a logout reply from an earlier warning
  // cannot rewrite the current one.
  NSUInteger _warningGeneration;
}
- (void)showWarning;
- (void)hideWarning;
@end
