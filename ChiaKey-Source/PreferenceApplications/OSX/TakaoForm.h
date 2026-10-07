// [AUTO_HEADER]

// Building blocks for the preference panes: rows of a title with a grey note
// under it on the left and the control on the right, hairlines between them,
// on a plain ground with generous margins.
//
// The panes still come from the nibs, whose controls keep their outlets and
// actions; a pane's layout method only moves those controls into these
// views. Header-only so any pane controller can import it; TakaoSwitch is
// implemented in TakaoGlobal.m.

#import <Cocoa/Cocoa.h>

static const CGFloat TakaoFormPaneWidth = 560.0;
static const CGFloat TakaoFormMargin = 40.0;
static const CGFloat TakaoFormHeadingTopInset = 16.0;

// An on/off switch drawn in the brand color; NSSwitch only takes the system
// accent. One made with switchMirroring: stands in for a nib check box: a flip
// sets the check box and sends its action, and syncMirroredControls copies
// the check boxes' state back after their controllers change them.
@interface TakaoSwitch : NSControl {
  NSControlStateValue _state;
  NSButton *_mirroredButton;
}
+ (TakaoSwitch *)switchMirroring:(NSButton *)button;
// Refreshes every mirroring switch and pop-up from its nib control.
+ (void)syncMirroredControls;
- (NSControlStateValue)state;
- (void)setState:(NSControlStateValue)state;
@end

// A pop-up standing in for a nib radio matrix, the same way.
@interface TakaoMatrixPopUpButton : NSPopUpButton {
  NSMatrix *_matrix;
}
+ (TakaoMatrixPopUpButton *)popUpMirroring:(NSMatrix *)matrix;
@end

static inline NSColor *TakaoFormDynamicColor(NSColor *light, NSColor *dark) {
  return [NSColor colorWithName:nil
                  dynamicProvider:^NSColor *(NSAppearance *appearance) {
                    NSAppearanceName name = [appearance
                        bestMatchFromAppearancesWithNames:@[
                          NSAppearanceNameAqua, NSAppearanceNameDarkAqua
                        ]];
                    return [name isEqualToString:NSAppearanceNameDarkAqua]
                               ? dark
                               : light;
                  }];
}

static inline NSColor *TakaoFormRGB(unsigned rgb, CGFloat alpha) {
  return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                             green:((rgb >> 8) & 0xff) / 255.0
                              blue:(rgb & 0xff) / 255.0
                             alpha:alpha];
}

static inline NSColor *TakaoFormColor(unsigned light, CGFloat lightAlpha,
                                      unsigned dark, CGFloat darkAlpha) {
  return TakaoFormDynamicColor(TakaoFormRGB(light, lightAlpha),
                               TakaoFormRGB(dark, darkAlpha));
}

// The vermilion of the 注 icon.
static inline NSColor *TakaoFormAccentColor(void) {
  return TakaoFormColor(0xC8452E, 1, 0xD0533A, 1);
}
static inline NSColor *TakaoFormBackgroundColor(void) {
  return TakaoFormColor(0xFBFAF8, 1, 0x1F1E1D, 1);
}
static inline NSColor *TakaoFormTextColor(void) {
  return TakaoFormColor(0x1F1D1B, 1, 0xF3F1EE, 1);
}
static inline NSColor *TakaoFormSecondaryTextColor(void) {
  return TakaoFormColor(0x6F6A64, 1, 0xA39E98, 1);
}
static inline NSColor *TakaoFormHairlineColor(void) {
  return TakaoFormColor(0x000000, 0.08, 0xFFFFFF, 0.09);
}

static inline NSString *TakaoFormStripColon(NSString *text) {
  NSCharacterSet *trim = [NSCharacterSet
      characterSetWithCharactersInString:@"：: …"];
  return [text stringByTrimmingCharactersInSet:trim];
}

static inline NSTextField *TakaoFormLabel(NSString *text, NSFont *font,
                                          NSColor *color) {
  NSTextField *label = [NSTextField labelWithString:text ? text : @""];
  [label setFont:font];
  [label setTextColor:color];
  [label setTranslatesAutoresizingMaskIntoConstraints:NO];
  return label;
}

// A Song face for page titles; the system font where it is missing.
static inline NSFont *TakaoFormTitleFont(CGFloat size) {
  NSFont *font = [NSFont fontWithName:@"STSongti-TC-Bold" size:size];
  return font ? font : [NSFont systemFontOfSize:size weight:NSFontWeightSemibold];
}

static inline NSView *TakaoFormHairline(void) {
  NSBox *line = [[[NSBox alloc] init] autorelease];
  [line setBoxType:NSBoxCustom];
  [line setBorderWidth:0];
  [line setTitlePosition:NSNoTitle];
  [line setFillColor:TakaoFormHairlineColor()];
  [line setTranslatesAutoresizingMaskIntoConstraints:NO];
  [[[line heightAnchor] constraintEqualToConstant:1] setActive:YES];
  return line;
}

static inline void TakaoFormPrepare(NSView *view) {
  [view removeFromSuperview];
  [view setTranslatesAutoresizingMaskIntoConstraints:NO];
}

static inline NSStackView *TakaoFormStack(
    NSArray *views, NSUserInterfaceLayoutOrientation orientation,
    CGFloat spacing) {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  [stack setOrientation:orientation];
  [stack setAlignment:orientation == NSUserInterfaceLayoutOrientationVertical
                          ? NSLayoutAttributeLeading
                          : NSLayoutAttributeCenterY];
  [stack setSpacing:spacing];
  [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
  return stack;
}

// Title and note on the left, the controls on the right; `below`, if any,
// runs full width under them (a table, say).
static inline NSView *TakaoFormRowWithContent(NSString *title, NSString *note,
                                              NSArray *controls,
                                              NSView *below) {
  NSMutableArray *texts = [NSMutableArray array];
  NSTextField *titleLabel = TakaoFormLabel(
      title, [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
      TakaoFormTextColor());
  [texts addObject:titleLabel];
  NSTextField *noteLabel = nil;
  if ([note length]) {
    noteLabel = [NSTextField wrappingLabelWithString:note];
    [noteLabel setFont:[NSFont systemFontOfSize:12]];
    [noteLabel setTextColor:TakaoFormSecondaryTextColor()];
    [noteLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [noteLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:
                                            NSLayoutConstraintOrientationHorizontal];
    [texts addObject:noteLabel];
  }
  NSStackView *textStack =
      TakaoFormStack(texts, NSUserInterfaceLayoutOrientationVertical, 3);
  [textStack setContentHuggingPriority:1
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
  [textStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                      forOrientation:
                                          NSLayoutConstraintOrientationHorizontal];

  // The text takes whatever width the controls leave; the controls sit
  // against the right edge, centred on the text.
  NSView *top = [[[NSView alloc] init] autorelease];
  [top setTranslatesAutoresizingMaskIntoConstraints:NO];
  [top addSubview:textStack];
  NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
    [[textStack leadingAnchor] constraintEqualToAnchor:[top leadingAnchor]],
    [[textStack topAnchor] constraintGreaterThanOrEqualToAnchor:[top topAnchor]],
    [[textStack bottomAnchor] constraintLessThanOrEqualToAnchor:[top bottomAnchor]],
    [[textStack centerYAnchor] constraintEqualToAnchor:[top centerYAnchor]],
  ]];
  // In a stack so that hidden controls (an install button with nothing to
  // install) give their room back.
  NSLayoutXAxisAnchor *trailing = [top trailingAnchor];
  if ([controls count]) {
    for (NSView *control in controls) TakaoFormPrepare(control);
    NSStackView *controlStack =
        TakaoFormStack(controls, NSUserInterfaceLayoutOrientationHorizontal, 10);
    [top addSubview:controlStack];
    [constraints addObjectsFromArray:@[
      [[controlStack trailingAnchor] constraintEqualToAnchor:[top trailingAnchor]],
      [[controlStack centerYAnchor] constraintEqualToAnchor:[top centerYAnchor]],
      [[controlStack topAnchor] constraintGreaterThanOrEqualToAnchor:[top topAnchor]],
      [[controlStack bottomAnchor]
          constraintLessThanOrEqualToAnchor:[top bottomAnchor]],
    ]];
    [controlStack setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                           forOrientation:
                                               NSLayoutConstraintOrientationHorizontal];
    // Hug the controls so the text, not the stack, takes the spare width.
    [controlStack setHuggingPriority:999
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    trailing = [controlStack leadingAnchor];
  }
  CGFloat gap = [controls count] ? -24 : 0;
  [constraints addObject:[[textStack trailingAnchor]
                             constraintLessThanOrEqualToAnchor:trailing
                                                      constant:gap]];
  // Without this the wrapping note would stay one long line.
  NSLayoutConstraint *fill =
      [[textStack trailingAnchor] constraintEqualToAnchor:trailing constant:gap];
  [fill setPriority:NSLayoutPriorityDefaultHigh];
  [constraints addObject:fill];
  [NSLayoutConstraint activateConstraints:constraints];

  NSMutableArray *parts = [NSMutableArray arrayWithObject:top];
  if (below) {
    TakaoFormPrepare(below);
    [parts addObject:below];
  }
  NSStackView *row =
      TakaoFormStack(parts, NSUserInterfaceLayoutOrientationVertical, 12);
  [row setEdgeInsets:NSEdgeInsetsMake(11, 0, 11, 0)];
  for (NSView *part in parts)
    [[[part widthAnchor] constraintEqualToAnchor:[row widthAnchor]] setActive:YES];
  return row;
}

static inline NSView *TakaoFormRow(NSString *title, NSString *note,
                                   NSArray *controls) {
  return TakaoFormRowWithContent(title, note, controls, nil);
}

// A small grey heading over a group of rows, with an optional note under
// it; no hairline goes under it.
static inline NSView *TakaoFormHeadingWithNote(NSString *title, NSString *note) {
  NSMutableArray *views = [NSMutableArray arrayWithObject:TakaoFormLabel(
      title, [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
      TakaoFormSecondaryTextColor())];
  if ([note length]) {
    NSTextField *noteLabel = [NSTextField wrappingLabelWithString:note];
    [noteLabel setFont:[NSFont systemFontOfSize:12]];
    [noteLabel setTextColor:TakaoFormSecondaryTextColor()];
    [noteLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [views addObject:noteLabel];
  }
  NSStackView *box =
      TakaoFormStack(views, NSUserInterfaceLayoutOrientationVertical, 4);
  [box setEdgeInsets:NSEdgeInsetsMake(TakaoFormHeadingTopInset, 0, 2, 0)];
  [box setIdentifier:@"TakaoFormHeading"];
  for (NSView *view in views)
    [[[view widthAnchor] constraintLessThanOrEqualToAnchor:[box widthAnchor]]
        setActive:YES];
  return box;
}

static inline NSView *TakaoFormHeading(NSString *title) {
  return TakaoFormHeadingWithNote(title, nil);
}

// Replaces the pane's content with the rows, a hairline under each, and sizes
// the pane to fit them.
static inline void TakaoFormInstall(NSView *pane, NSArray *rows) {
  for (NSView *view in [[[pane subviews] copy] autorelease])
    [view removeFromSuperview];

  NSMutableArray *views = [NSMutableArray array];
  for (NSView *row in rows) {
    [views addObject:row];
    if (![[row identifier] isEqualToString:@"TakaoFormHeading"])
      [views addObject:TakaoFormHairline()];
  }
  NSStackView *stack =
      TakaoFormStack(views, NSUserInterfaceLayoutOrientationVertical, 0);
  [stack setEdgeInsets:NSEdgeInsetsMake(4, TakaoFormMargin, 28,
                                        TakaoFormMargin)];
  [pane addSubview:stack];
  NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
    [[stack leadingAnchor] constraintEqualToAnchor:[pane leadingAnchor]],
    [[stack topAnchor] constraintEqualToAnchor:[pane topAnchor]],
    [[stack widthAnchor] constraintEqualToConstant:TakaoFormPaneWidth],
  ]];
  for (NSView *view in views)
    [constraints addObject:[[view widthAnchor]
                               constraintEqualToConstant:TakaoFormPaneWidth -
                                                         TakaoFormMargin * 2]];
  [NSLayoutConstraint activateConstraints:constraints];

  // Wrapped notes only know their height after a layout pass.
  [pane setFrameSize:NSMakeSize(TakaoFormPaneWidth, 2000)];
  [pane layoutSubtreeIfNeeded];
  [pane setFrameSize:NSMakeSize(TakaoFormPaneWidth,
                                ceil(NSHeight([stack frame])))];
}

#pragma mark Finding the nib's labels

// The nib's static text fields: labels, titles and notes.
static inline NSArray *TakaoFormTextFields(NSView *container) {
  NSMutableArray *fields = [NSMutableArray array];
  for (NSView *view in [container subviews])
    if ([view isKindOfClass:[NSTextField class]] && ![(NSTextField *)view isEditable])
      [fields addObject:view];
  return fields;
}

// The label just left of a control, on its line.
static inline NSString *TakaoFormLabelLeftOf(NSView *control, NSArray *fields) {
  NSRect target = [control frame];
  NSTextField *best = nil;
  for (NSTextField *field in fields) {
    NSRect frame = [field frame];
    if (NSMaxX(frame) > NSMinX(target) + 4) continue;
    if (fabs(NSMidY(frame) - NSMidY(target)) > 8 &&
        fabs(NSMaxY(frame) - NSMaxY(target)) > 6)
      continue;
    if (!best || NSMaxX(frame) > NSMaxX([best frame])) best = field;
  }
  return best ? TakaoFormStripColon([best stringValue]) : nil;
}

// The text right above a control, starting where it does.
static inline NSString *TakaoFormLabelAbove(NSView *control, NSArray *fields) {
  NSRect target = [control frame];
  for (NSTextField *field in fields) {
    NSRect frame = [field frame];
    if (fabs(NSMinX(frame) - NSMinX(target)) <= 6 &&
        NSMinY(frame) >= NSMaxY(target) - 2 &&
        NSMinY(frame) - NSMaxY(target) < 16)
      return TakaoFormStripColon([field stringValue]);
  }
  return nil;
}
