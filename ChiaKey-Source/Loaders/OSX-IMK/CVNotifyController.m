// [AUTO_HEADER]

#import "CVNotifyController.h"

#import <QuartzCore/QuartzCore.h>

// Laid out after macOS's notification banners.
static const CGFloat kBannerWidth = 344.0;
static const CGFloat kBannerPadding = 14.0;
static const CGFloat kBannerRadius = 18.0;
static const CGFloat kTitleGap = 2.0;
static const CGFloat kScreenMargin = 12.0;  // from the menu bar and the edge
static const CGFloat kStackGap = 8.0;       // between stacked banners
static const CGFloat kSlideDistance = 24.0;
static const NSInteger kMaxBodyLines = 3;
static const NSTimeInterval kShowDuration = 0.35;
static const NSTimeInterval kFadeDuration = 0.3;
// How long a banner stays before fading: long enough to read it through.
static const NSTimeInterval kDisplayDuration = 3.0;
static const NSTimeInterval kStayDisplayDuration = 5.0;

@implementation CVNotifyController

int c_count;
NSPoint c_lastLocation;

#pragma mark Class methods

+ (void)notify:(NSString *)message {
  CVNotifyController *c = [[CVNotifyController alloc] init];
  [c setMessage:message];
  [c setShouldStay:NO];
  [c showNotifyWindow];
}
+ (void)notifyAndStay:(NSString *)message {
  CVNotifyController *c = [[CVNotifyController alloc] init];
  [c setMessage:message];
  [c setShouldStay:YES];
  [c showNotifyWindow];
}
+ (void)addInstanceCount {
  c_count++;
}
+ (void)removeInstanceCount {
  c_count--;
  if (c_count < 0) c_count = 0;
}
+ (void)resetCount {
  c_count = 0;
}
+ (int)countNotifyWindows {
  return c_count;
}
+ (void)setLastLocation:(NSPoint)location {
  c_lastLocation = location;
}
+ (NSPoint)lastLocation {
  return c_lastLocation;
}

#pragma mark Instance methods

- (void)dealloc {
  [_foregroundColor release];
  [_backgroundColor release];
  [super dealloc];
}
- (id)init {
  if (self = [super init]) {
    BOOL loaded = [[NSBundle mainBundle] loadNibNamed:@"NotifyWindow" owner:self topLevelObjects:nil];
    NSAssert((loaded == YES), @"NIB did not load");
  }
  return self;
}
+ (NSTextField *)labelWithFont:(NSFont *)font lines:(NSInteger)lines {
  NSTextField *label = [NSTextField labelWithString:@""];
  [label setFont:font];
  [label setTextColor:[NSColor labelColor]];
  [label setMaximumNumberOfLines:lines];
  [label setLineBreakMode:NSLineBreakByTruncatingTail];
  [[label cell] setWraps:lines != 1];
  return label;
}
- (void)awakeFromNib {
  NSWindow *window = [self window];
  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:YES];

  NSRect frame = NSMakeRect(0, 0, kBannerWidth, 64);
  NSView *container = [[[NSView alloc] initWithFrame:frame] autorelease];
  [container setWantsLayer:YES];
  [[container layer] setCornerRadius:kBannerRadius];
  [[container layer] setMasksToBounds:YES];

  // Clear Liquid Glass where the system has it, the closest vibrancy
  // otherwise.
  NSView *background = nil;
  Class glassClass = NSClassFromString(@"NSGlassEffectView");
  if (glassClass) {
    background = [[[glassClass alloc] initWithFrame:frame] autorelease];
    [background setValue:@(kBannerRadius) forKey:@"cornerRadius"];
    [background setValue:@1 forKey:@"style"];  // NSGlassEffectViewStyleClear
  } else {
    NSVisualEffectView *effectView =
        [[[NSVisualEffectView alloc] initWithFrame:frame] autorelease];
    [effectView setMaterial:NSVisualEffectMaterialPopover];
    [effectView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [effectView setState:NSVisualEffectStateActive];
    background = effectView;
  }
  [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [container addSubview:background];

  NSDictionary *info = [[NSBundle mainBundle] localizedInfoDictionary];
  NSString *appName = [info objectForKey:@"CFBundleDisplayName"];
  if (![appName length])
    appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
  _titleField = [CVNotifyController
      labelWithFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
              lines:1];
  [_titleField setStringValue:appName ? appName : @""];
  [container addSubview:_titleField];

  _bodyField = [CVNotifyController
      labelWithFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]
              lines:kMaxBodyLines];
  [container addSubview:_bodyField];

  // The nib's field and background go with its old content view.
  _messageTextField = _bodyField;
  [window setContentView:container];
}
- (void)layoutBanner {
  CGFloat textX = kBannerPadding;
  CGFloat textWidth = kBannerWidth - textX - kBannerPadding;
  CGFloat titleHeight = [[_titleField cell] cellSizeForBounds:NSMakeRect(0, 0, textWidth, 1000)].height;
  CGFloat bodyHeight = [[_bodyField cell] cellSizeForBounds:NSMakeRect(0, 0, textWidth, 1000)].height;
  CGFloat textHeight = titleHeight + kTitleGap + bodyHeight;
  CGFloat height = textHeight + kBannerPadding * 2;

  NSRect frame = [[self window] frame];
  frame.size = NSMakeSize(kBannerWidth, ceil(height));
  [[self window] setFrame:frame display:NO];

  // Bottom-up coordinates: the text block is centred vertically.
  CGFloat textTop = (height + textHeight) / 2;
  [_titleField setFrame:NSMakeRect(textX, textTop - titleHeight, textWidth,
                                   titleHeight)];
  [_bodyField setFrame:NSMakeRect(textX, textTop - titleHeight - kTitleGap -
                                             bodyHeight,
                                  textWidth, bodyHeight)];
}
- (NSString *)message {
  return [_bodyField stringValue];
}
- (void)setMessage:(NSString *)message {
  [_bodyField setStringValue:message ? message : @""];
  [self layoutBanner];
}
- (NSColor *)textColor {
  return [_bodyField textColor];
}
- (void)setTextColor:(NSColor *)aColor {
  [_bodyField setTextColor:aColor];
}
- (BOOL)shouldStay {
  return _shouldStay;
}
- (void)setShouldStay:(BOOL)shouldStay {
  _shouldStay = shouldStay;
}
// Top right under the menu bar, below any banner still showing.
- (NSRect)restingFrame {
  NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
  NSSize size = [[self window] frame].size;
  NSPoint origin =
      NSMakePoint(NSMaxX(screenRect) - size.width - kScreenMargin,
                  NSMaxY(screenRect) - size.height - kScreenMargin);
  if ([CVNotifyController countNotifyWindows] > 0) {
    CGFloat y = [CVNotifyController lastLocation].y - size.height - kStackGap;
    if (y >= NSMinY(screenRect)) origin.y = y;
  }
  return NSMakeRect(origin.x, origin.y, size.width, size.height);
}
- (void)showNotifyWindow {
  NSWindow *window = [self window];
  NSRect resting = [self restingFrame];
  [CVNotifyController setLastLocation:resting.origin];

  // Slides in from the right as it fades in, as system banners do.
  NSRect start = resting;
  start.origin.x += kSlideDistance;
  [window setFrame:start display:NO];
  [window setAlphaValue:0];
  [window orderFront:self];
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    [context setDuration:kShowDuration];
    [context setTimingFunction:
                 [CAMediaTimingFunction
                     functionWithName:kCAMediaTimingFunctionEaseOut]];
    [[window animator] setFrame:resting display:YES];
    [[window animator] setAlphaValue:1];
  }
                      completionHandler:^{
                        [window invalidateShadow];
                      }];

  [CVNotifyController addInstanceCount];
  _waitTimer =
      [NSTimer scheduledTimerWithTimeInterval:(_shouldStay ? kStayDisplayDuration
                                                             : kDisplayDuration)
                                       target:self
                                     selector:@selector(fadeNotifyWindow)
                                     userInfo:nil
                                      repeats:NO];
}
- (void)fadeNotifyWindow {
  [_waitTimer invalidate];
  _waitTimer = nil;
  // A click may have started the fade already, and close must run once.
  if (_fading) return;
  _fading = YES;
  [CVNotifyController removeInstanceCount];
  NSWindow *window = [self window];
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    [context setDuration:kFadeDuration];
    [[window animator] setAlphaValue:0];
  }
                      completionHandler:^{
                        [self close];
                      }];
}
- (void)close {
  // The controller owns itself (notify: never releases it); the autorelease
  // below is that release and must happen exactly once.
  if (_closed) return;
  _closed = YES;
  [_waitTimer invalidate];
  _waitTimer = nil;
  [_fadeTimer invalidate];
  _fadeTimer = nil;
  [[self window] orderOut:self];
  [self autorelease];
}
- (IBAction)fade {
  [self fadeNotifyWindow];
}
@end
