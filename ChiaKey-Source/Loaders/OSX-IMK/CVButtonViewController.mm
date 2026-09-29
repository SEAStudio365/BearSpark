// [AUTO_HEADER]

#import "CVButtonViewController.h"

#import "OpenVanillaController.h"

#if CHIAKEY_DEV_LOGGING
// Independent tracking probes: keep AppKit's native tooltip mechanism intact.
@interface CVSymbolHoverProbeButton : NSButton {
  NSTrackingArea *_hoverProbe;
}
@end

@implementation CVSymbolHoverProbeButton
- (void)logHoverState:(const char *)phase {
  NSWindow *window = [self window];
  CHIAKEY_DEV_LOG("[symbol-hover] %{public}s button=%ld tooltipLength=%lu "
                 "appActive=%d window=%ld visible=%d key=%d inactiveTips=%d "
                 "ignoresMouse=%d hidden=%d trackingAreas=%lu",
                 phase, (long)[self tag], (unsigned long)[[self toolTip] length],
                 (int)[NSApp isActive], (long)[window windowNumber],
                 (int)[window isVisible], (int)[window isKeyWindow],
                 (int)[window allowsToolTipsWhenApplicationIsInactive],
                 (int)[window ignoresMouseEvents], (int)[self isHiddenOrHasHiddenAncestor],
                 (unsigned long)[[self trackingAreas] count]);
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_hoverProbe) {
    [self removeTrackingArea:_hoverProbe];
    [_hoverProbe release];
  }
  _hoverProbe = [[NSTrackingArea alloc]
      initWithRect:NSZeroRect
           options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                   NSTrackingInVisibleRect
             owner:self userInfo:nil];
  [self addTrackingArea:_hoverProbe];
  if ([self tag] == 0) [self logHoverState:"tracking-ready"];
}
- (void)mouseEntered:(NSEvent *)event {
  if ([event trackingArea] != _hoverProbe) { [super mouseEntered:event]; return; }
  [self logHoverState:"enter"];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(logDwell) object:nil];
  [self performSelector:@selector(logDwell) withObject:nil afterDelay:2.0];
}
- (void)logDwell { [self logHoverState:"dwell-2s"]; }
- (void)mouseExited:(NSEvent *)event {
  if ([event trackingArea] != _hoverProbe) { [super mouseExited:event]; return; }
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(logDwell) object:nil];
  [self logHoverState:"exit"];
}
- (void)viewWillMoveToWindow:(NSWindow *)window {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(logDwell) object:nil];
  [super viewWillMoveToWindow:window];
}
- (void)dealloc {
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if (_hoverProbe) [self removeTrackingArea:_hoverProbe];
  [_hoverProbe release];
  [super dealloc];
}
@end
#endif

static NSArray *CVSymbolScalars(NSString *symbol) {
  NSMutableArray *scalars = [NSMutableArray array];
  for (NSUInteger i = 0; i < [symbol length]; i++) {
    NSUInteger length = 1;
    if (CFStringIsSurrogateHighCharacter([symbol characterAtIndex:i]) &&
        i + 1 < [symbol length] &&
        CFStringIsSurrogateLowCharacter([symbol characterAtIndex:i + 1]))
      length = 2;
    [scalars addObject:[symbol substringWithRange:NSMakeRange(i, length)]];
    i += length - 1;
  }
  return scalars;
}

static NSString *CVSymbolName(NSString *symbol, NSDictionary *metadata) {
  NSString *name = [metadata objectForKey:@"Name"];
  if ([name isKindOfClass:[NSString class]] && [name length]) return name;

  // Per scalar: the transform leaves printable ASCII as-is, so "a" stays "a".
  NSMutableArray *names = [NSMutableArray array];
  for (NSString *scalar in CVSymbolScalars(symbol)) {
    NSMutableString *unicodeName = [[scalar mutableCopy] autorelease];
    CFStringTransform((CFMutableStringRef)unicodeName, NULL,
                      kCFStringTransformToUnicodeName, false);
    if ([unicodeName hasPrefix:@"\\N{"] && [unicodeName hasSuffix:@"}"])
      [names addObject:[unicodeName substringWithRange:
                            NSMakeRange(3, [unicodeName length] - 4)]];
    else
      [names addObject:scalar];
  }
  return [names componentsJoinedByString:@", "];
}

static NSString *CVSymbolDescription(NSString *symbol, NSString *name,
                                     NSDictionary *metadata) {
  NSMutableArray *codePoints = [NSMutableArray array];
  for (NSString *scalar in CVSymbolScalars(symbol)) {
    UTF32Char value = [scalar characterAtIndex:0];
    if ([scalar length] == 2)
      value = CFStringGetLongCharacterForSurrogatePair(
          (UniChar)value, [scalar characterAtIndex:1]);
    [codePoints addObject:[NSString stringWithFormat:@"U+%04X", (unsigned int)value]];
  }
  NSString *detail = [metadata objectForKey:@"Description"];
  NSString *heading = [NSString stringWithFormat:@"%@\n%@", name,
                                [codePoints componentsJoinedByString:@" "]];
  if ([detail isKindOfClass:[NSString class]] && [detail length])
    return [heading stringByAppendingFormat:@"\n%@", detail];
  return heading;
}

@implementation CVButtonViewController

- (void)dealloc {
  [_view release];
  [_buttonArray release];
  [super dealloc];
}
- (id)initWithDictionary:(NSDictionary *)d {
  self = [super init];
  if (self != nil) {
    _buttonArray = [[NSMutableArray alloc] init];
    NSArray *buttons = [d valueForKey:@"Buttons"];
    id metadataTable = [d objectForKey:@"SymbolMetadata"];
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 0)];
    NSEnumerator *enumerator = [buttons objectEnumerator];
    NSString *symbol;
    NSInteger row = 0;
    NSInteger column = 0;
    while (symbol = [enumerator nextObject]) {
#if CHIAKEY_DEV_LOGGING
      NSButton *button = [[CVSymbolHoverProbeButton alloc] initWithFrame:NSZeroRect];
#else
      NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
#endif
      [button setTag:[_buttonArray count]];
      [button autorelease];
      [button setTarget:self];
      [button setAction:@selector(sendString:)];
      [button setButtonType:NSButtonTypeMomentaryLight];
      [button setBezelStyle:NSBezelStyleTexturedSquare];
      [button setStringValue:symbol];
      [button setTitle:symbol];
      // Keep the inserted text separate from the visible whitespace marker.
      [[button cell] setRepresentedObject:symbol];
      id metadata = [metadataTable isKindOfClass:[NSDictionary class]]
                        ? [metadataTable objectForKey:symbol] : nil;
      if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
      NSString *label = [metadata objectForKey:@"DisplayLabel"];
      if ([label isKindOfClass:[NSString class]] && [label length])
        [button setTitle:label];
      NSString *name = CVSymbolName(symbol, metadata);
      [button setToolTip:CVSymbolDescription(symbol, name, metadata)];
      // VoiceOver reads the tooltip as help; the label stays just the name.
      [button setAccessibilityLabel:name];
      // A metadata label may need several grid cells (e.g. 全形空白).
      NSInteger span = 1;
      if (![[button title] isEqualToString:symbol])
        span = MIN(10, MAX(1, (NSInteger)ceil(([[button cell] cellSize].width + 2) / 25)));
      if (column + span > 10) { row++; column = 0; }
      [button setFrame:NSMakeRect(column * 25, row * 25, span * 25 - 2, 23)];
      column += span;
      [_buttonArray addObject:button];
      [_view addSubview:button];
    }
    CGFloat height = [_buttonArray count] ? (row + 1) * 25 : 0;
    [_view setFrameSize:NSMakeSize(250, height)];
    for (NSButton *button in _buttonArray) {
      NSRect frame = [button frame];
      frame.origin.y = height - frame.origin.y - 25;
      [button setFrame:frame];
    }
  }
  return self;
}
- (NSView *)view {
  return _view;
}
- (IBAction)sendString:(id)sender {
  NSButton *button = (NSButton *)sender;
  NSString *text = [[button cell] representedObject];
  [OpenVanillaController sendComposedStringToCurrentlyActiveContext:text];
}

@end
