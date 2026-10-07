// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

#import "CVFloatingBackground.h"
#import "CVFloatingWindow.h"
#import "CVNotifyWindow.h"

// A notification banner in the style of macOS's own: a clear glass card at
// the top right with the app's name and the message.
@interface CVNotifyController : NSWindowController {
  IBOutlet NSTextField *_messageTextField;  // the nib's; replaced at load

  BOOL _shouldStay;
  NSColor *_backgroundColor;
  NSColor *_foregroundColor;
  NSTimer *_waitTimer;
  NSTimer *_fadeTimer;
  BOOL _fading;
  BOOL _closed;

  NSTextField *_titleField;
  NSTextField *_bodyField;
}

#pragma mark Class Methods
+ (void)notify:(NSString *)message;
+ (void)notifyAndStay:(NSString *)message;
+ (void)addInstanceCount;
+ (void)removeInstanceCount;
+ (void)resetCount;
+ (int)countNotifyWindows;
+ (void)setLastLocation:(NSPoint)location;
+ (NSPoint)lastLocation;

#pragma mark Instance Methods
//- (CVFloatingWindow *)window;
- (NSString *)message;
- (void)setMessage:(NSString *)message;
- (NSColor *)textColor;
- (void)setTextColor:(NSColor *)aColor;
- (BOOL)shouldStay;
- (void)setShouldStay:(BOOL)flag;
- (void)showNotifyWindow;
- (void)fadeNotifyWindow;
- (void)close;
- (IBAction)fade;
@end
