// [AUTO_HEADER]

#import "CVSecureInputWarningController.h"

#import "ChiaKeySecureInputWatch.h"
#import "LFUtilities.h"

static const CGFloat kCVSecureInputWarningWidth = 420.0;
static const CGFloat kCVSecureInputWarningMargin = 20.0;

// Run through osascript rather than sent in-process: the hardened runtime
// this process is signed with blocks Apple Events without an entitlement.
// "logo" brings up the standard confirm-and-log-out dialog.
static NSString *const kCVLogoutScript =
    @"tell application \"loginwindow\" to «event aevtlogo»";

@implementation CVSecureInputWarningController

- (void)dealloc {
  [_panel close];
  [_panel release];
  [_laterBesideLogout release];
  [_laterAtTrailingEdge release];
  [super dealloc];
}

- (void)_buildPanel {
  _panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect(0, 0, kCVSecureInputWarningWidth, 10)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskNonactivatingPanel
                  backing:NSBackingStoreBuffered
                    defer:YES];
  [_panel setTitle:LFLSTR(@"ChiaKey")];
  [_panel setReleasedWhenClosed:NO];
  // This process is never the active app, so a panel that hides on
  // deactivation would vanish the moment it appeared.
  [_panel setHidesOnDeactivate:NO];
  [_panel setLevel:NSFloatingWindowLevel];
  [_panel setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorFullScreenAuxiliary];
  [[_panel standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
  [[_panel standardWindowButton:NSWindowZoomButton] setHidden:YES];

  NSTextField *titleField = [NSTextField
      labelWithString:LFLSTR(@"ChiaKey is unavailable until you log out")];
  [titleField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];

  _messageField = [NSTextField wrappingLabelWithString:@""];
  [_messageField setPreferredMaxLayoutWidth:kCVSecureInputWarningWidth -
                                            2 * kCVSecureInputWarningMargin];

  _logoutButton = [NSButton buttonWithTitle:LFLSTR(@"Log Out…")
                                     target:self
                                     action:@selector(_logOut:)];
  [_logoutButton setKeyEquivalent:@"\r"];
  NSButton *laterButton = [NSButton buttonWithTitle:LFLSTR(@"Later")
                                             target:self
                                             action:@selector(_dismiss:)];

  NSView *contentView = [_panel contentView];
  NSArray *views = [NSArray arrayWithObjects:titleField, _messageField,
                                             _logoutButton, laterButton, nil];
  for (NSView *view in views) {
    [view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contentView addSubview:view];
  }

  CGFloat margin = kCVSecureInputWarningMargin;
  _laterBesideLogout = [[[laterButton trailingAnchor]
      constraintEqualToAnchor:[_logoutButton leadingAnchor]
                     constant:-12] retain];
  _laterAtTrailingEdge = [[[laterButton trailingAnchor]
      constraintEqualToAnchor:[contentView trailingAnchor]
                     constant:-margin] retain];
  [NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
      [[contentView widthAnchor]
          constraintEqualToConstant:kCVSecureInputWarningWidth],
      [[titleField topAnchor] constraintEqualToAnchor:[contentView topAnchor]
                                             constant:margin],
      [[titleField leadingAnchor]
          constraintEqualToAnchor:[contentView leadingAnchor]
                         constant:margin],
      [[titleField trailingAnchor]
          constraintLessThanOrEqualToAnchor:[contentView trailingAnchor]
                                   constant:-margin],
      [[_messageField topAnchor] constraintEqualToAnchor:[titleField bottomAnchor]
                                                constant:8],
      [[_messageField leadingAnchor]
          constraintEqualToAnchor:[contentView leadingAnchor]
                         constant:margin],
      [[_messageField trailingAnchor]
          constraintEqualToAnchor:[contentView trailingAnchor]
                         constant:-margin],
      [[_logoutButton topAnchor] constraintEqualToAnchor:[_messageField bottomAnchor]
                                                constant:16],
      [[_logoutButton trailingAnchor]
          constraintEqualToAnchor:[contentView trailingAnchor]
                         constant:-margin],
      [[_logoutButton bottomAnchor]
          constraintEqualToAnchor:[contentView bottomAnchor]
                         constant:-margin],
      [[laterButton centerYAnchor]
          constraintEqualToAnchor:[_logoutButton centerYAnchor]],
      _laterBesideLogout,
      nil]];
}

- (void)_setLogoutOffered:(BOOL)offered {
  [_logoutButton setHidden:!offered];
  // Deactivate before activating so the two never conflict.
  [(offered ? _laterAtTrailingEdge : _laterBesideLogout) setActive:NO];
  [(offered ? _laterBesideLogout : _laterAtTrailingEdge) setActive:YES];
}

- (void)_resetContents {
  [_messageField
      setStringValue:LFLSTR(@"macOS's login window did not turn Secure "
                            @"Input off after you signed in, so the system "
                            @"has disabled every third-party input method. "
                            @"Logging out and back in usually clears "
                            @"this.")];
  [self _setLogoutOffered:YES];
  [_logoutButton setEnabled:YES];
  [_panel setContentSize:[[_panel contentView] fittingSize]];
}

- (void)showWarning {
  if (!_panel) [self _buildPanel];
  _warningGeneration++;
  [self _resetContents];
  [_panel center];
  [_panel orderFrontRegardless];
}

- (void)hideWarning {
  _warningGeneration++;
  [_panel orderOut:nil];
}

- (void)_dismiss:(id)sender {
  [self hideWarning];
}

- (void)_logOut:(id)sender {
  [_logoutButton setEnabled:NO];
  NSUInteger generation = _warningGeneration;

  // The reply only comes once the user answers the dialog, so wait off the
  // main thread.
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];
        [task setLaunchPath:@"/usr/bin/osascript"];
        [task setArguments:[NSArray arrayWithObjects:@"-e", kCVLogoutScript,
                                                     nil]];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        BOOL succeeded = NO;
        @try {
          [task launch];
          [task waitUntilExit];
          NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
          NSString *output = [[[NSString alloc]
              initWithData:data
                  encoding:NSUTF8StringEncoding] autorelease];
          succeeded =
              ChiaKeyLogoutRequestSucceeded([task terminationStatus], output);
          if (!succeeded) {
            NSLog(@"ChiaKey: logout request failed (status=%d): %@",
                  [task terminationStatus], output);
          }
        } @catch (NSException *exception) {
          NSLog(@"ChiaKey: logout request failed to launch: %@", exception);
        }

        [task release];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (generation != _warningGeneration) return;
          [self _logoutRequestDidFinish:succeeded];
        });
        [pool drain];
      });
}

- (void)_logoutRequestDidFinish:(BOOL)succeeded {
  if (succeeded) {
    // The user cancelled the system dialog; leave the offer standing.
    [_logoutButton setEnabled:YES];
    return;
  }

  [_messageField
      setStringValue:LFLSTR(@"ChiaKey could not start the logout. Choose "
                            @"Log Out from the Apple menu, then log back in.")];
  [self _setLogoutOffered:NO];
  [_panel setContentSize:[[_panel contentView] fittingSize]];
}

@end
