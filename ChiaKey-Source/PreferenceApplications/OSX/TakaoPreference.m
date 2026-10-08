/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoPreference.h"

#import "TakaoForm.h"

#import "TakaoGeneric.h"
#import "TakaoGlobal.h"
#import "TakaoLoadedModule.h"
#import "TakaoSmartPhonetic.h"
#import "TakaoUpdate.h"
#import "TakaoWindow.h"

@interface TakaoPreference (Private)
- (void)_refreshInputMethodListFromStatus:(NSDictionary *)status;
- (void)_serviceStatusDidUpdate:(NSNotification *)notification;
- (void)_buildHeader;
- (void)_relayoutNibPane:(NSView *)pane;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (void)_showPaneWithIdentifier:(NSString *)identifier animate:(BOOL)flag;
@end

// The image each pane's tab shows, by pane identifier.
static NSString *TakaoPaneIconName(NSString *identifier) {
  NSDictionary *names = @{
    GeneralToolbarItemIdentifier : @"general",
    PhoneticToolbarItemIdentifier : @"phonetic",
    CangjieToolbarItemIdentifier : @"cangjie",
    SimplexToolbarItemIdentifier : @"simplex",
    GenericToolbarItemIdentifier : @"generic",
    PluginToolbarItemIdentifier : @"plugin",
    PhraseToolbarItemIdentifier : @"phrase",
    UpdateToolbarItemIdentifier : @"update",
  };
  return [names objectForKey:identifier];
}

// The value a slider is set to, shown beside it. The nib's labels for the
// slider's ends are dropped in the relayout, which left the slider with no
// number at all.
@interface TakaoSliderValueLabel : NSTextField {
  NSSlider *_slider;  // kept alive by the pane's view list
  id _forwardTarget;
  SEL _forwardAction;
}
+ (TakaoSliderValueLabel *)labelMirroring:(NSSlider *)slider;
+ (void)refreshAll;
- (void)refresh;
@end

@implementation TakaoSliderValueLabel

static NSMutableArray *TakaoSliderValueLabels = nil;

+ (TakaoSliderValueLabel *)labelMirroring:(NSSlider *)slider {
  TakaoSliderValueLabel *label =
      [[[TakaoSliderValueLabel alloc] initWithFrame:NSZeroRect] autorelease];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize]
                                                  weight:NSFontWeightRegular]];
  label->_slider = slider;
  label->_forwardTarget = [slider target];
  label->_forwardAction = [slider action];
  // Follow the knob while it moves; the preference is still written once,
  // when the knob is let go.
  [slider setContinuous:YES];
  [slider setTarget:label];
  [slider setAction:@selector(_sliderDidChange:)];
  [label refresh];
  if (!TakaoSliderValueLabels) TakaoSliderValueLabels = [[NSMutableArray alloc] init];
  [TakaoSliderValueLabels addObject:label];
  return label;
}

+ (void)refreshAll {
  for (TakaoSliderValueLabel *label in TakaoSliderValueLabels) [label refresh];
}

- (void)refresh {
  [self setStringValue:[NSString stringWithFormat:LFLSTR(@"%ld characters"),
                                                  (long)[_slider integerValue]]];
}

- (void)_sliderDidChange:(id)sender {
  [self refresh];
  NSEventType type = [[NSApp currentEvent] type];
  if (type == NSEventTypeLeftMouseDragged) return;
  [NSApp sendAction:_forwardAction to:_forwardTarget from:sender];
}

@end

@implementation TakaoPreference

- (void)awakeFromNib {
  [NSApp setDelegate:(id)self];

  _defaultApplicationImage = [[NSApp applicationIconImage] copy];

  // Module info comes from the status file the IME publishes on every
  // start/reload (see ChiaKeyServiceCoordination.h), not from XPC.
  NSDictionary *status = ChiaKeyReadServiceStatus();

  // The General pane lists whatever the engine actually loaded, so that
  // imported tables can be hidden from the input menu. The table pane
  // manages the files themselves and loads its own list.
  [self _refreshInputMethodListFromStatus:status];

  // Republished whenever the engine reloads, which is what happens right
  // after a table is imported or removed.
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(_serviceStatusDidUpdate:)
             name:ChiaKeyServiceStatusDidUpdateNotification
           object:nil];

  NSArray *loadedModules = [status objectForKey:ChiaKeyStatusPackagesKey];

  if ([loadedModules count]) {
    _hasLoadedModules = YES;
    [_takaoLoadedModuleController setModules:loadedModules];
  }

#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5)
  // cancel unified look and feel?
  int newHeight = [_generalView frame].size.height -
                  [_keyboardLayoutContentView frame].size.height + 10;
  [_generalView setFrame:NSMakeRect(0, 0, 480, newHeight)];
  [_keyboardLayoutContentView removeFromSuperview];
#else
  [_keyboardLayoutContentView addSubview:_keyboardLayoutView];
#endif
  [_takaoGlobalController layoutGeneralView:_generalView
                                keyboardView:_keyboardLayoutView];
  for (NSView *pane in @[
         _phoneticView, _cangjieView, _simpexView, _genericSettingView,
         _phraseView, _updateView, _pluginView
       ])
    [self _relayoutNibPane:pane];

  // No toolbar: the panes share a header of their own drawn under a clear
  // title bar.
  [window setStyleMask:[window styleMask] | NSWindowStyleMaskFullSizeContentView];
  [window setTitlebarAppearsTransparent:YES];
  [window setTitleVisibility:NSWindowTitleHidden];
  [window setBackgroundColor:TakaoFormBackgroundColor()];
  [window setDelegate:(id)self];
  [self _buildHeader];
  [window center];

  [self _showPaneWithIdentifier:GeneralToolbarItemIdentifier animate:NO];
  [window center];

  // Other controllers fill their check boxes in their own awakeFromNib, which
  // may come after this one, and the update pane changes them as checks run;
  // keep the switches standing in for them current.
  dispatch_async(dispatch_get_main_queue(), ^{
    [TakaoSwitch syncMirroredControls];
    [TakaoSliderValueLabel refreshAll];
  });
  [NSTimer scheduledTimerWithTimeInterval:0.5
                                  repeats:YES
                                    block:^(NSTimer *timer) {
                                      [TakaoSwitch syncMirroredControls];
                                      [TakaoSliderValueLabel refreshAll];
                                    }];

}

- (void)_refreshInputMethodListFromStatus:(NSDictionary *)status {
  NSMutableArray *genericModules = [NSMutableArray array];

  NSEnumerator *moduleEnumerator =
      [[status objectForKey:ChiaKeyStatusModulesKey] objectEnumerator];
  NSArray *itemArray = nil;
  while (itemArray = [moduleEnumerator nextObject]) {
    if (![itemArray isKindOfClass:[NSArray class]] || ![itemArray count])
      continue;
    NSString *name = [itemArray objectAtIndex:0];
    if ([name hasPrefix:@"Generic-"] &&
        ![name isEqualToString:@"Generic-cj-cin"] &&
        ![name isEqualToString:@"Generic-simplex-cin"])
      [genericModules addObject:itemArray];
  }

  [_takaoGlobalController
      setInputMethods:[genericModules count] ? genericModules : nil];
}

- (void)_serviceStatusDidUpdate:(NSNotification *)notification {
  [self _refreshInputMethodListFromStatus:ChiaKeyReadServiceStatus()];
}

- (void)setActiveView:(NSView *)view animate:(BOOL)flag {
  NSEvent *e = [NSApp currentEvent];
  if ([e modifierFlags] & NSEventModifierFlagShift) {
    [window useSlowMotion];
  } else {
    [window stopSlowMotion];
  }

  // The window is all content (full-size content view), so the header
  // and the pane between them make up its height.
  NSView *content = [window contentView];
  CGFloat chromeHeight = NSHeight([window frame]) - NSHeight([content frame]);
  if (chromeHeight < 0) chromeHeight = 0;
  CGFloat width = TakaoFormPaneWidth;
  CGFloat headerHeight = NSHeight([_headerView frame]);
  CGFloat paneHeight = NSHeight([view frame]);

  // A pane taller than the screen allows scrolls under the fixed header.
  NSScreen *screen = [window screen] ? [window screen] : [NSScreen mainScreen];
  CGFloat maxPaneHeight =
      MIN(720, NSHeight([screen visibleFrame]) - 40) - headerHeight - chromeHeight;
  NSView *shown = view;
  if (paneHeight > maxPaneHeight) {
    if (!_paneScrollViews)
      _paneScrollViews = [[NSMapTable strongToStrongObjectsMapTable] retain];
    NSScrollView *scrollView = [_paneScrollViews objectForKey:view];
    if (!scrollView) {
      scrollView = [[[NSScrollView alloc]
          initWithFrame:NSMakeRect(0, 0, width, maxPaneHeight)] autorelease];
      [scrollView setHasVerticalScroller:YES];
      [scrollView setAutohidesScrollers:YES];
      [scrollView setScrollerStyle:NSScrollerStyleOverlay];
      [scrollView setBorderType:NSNoBorder];
      [scrollView setDrawsBackground:NO];
      [view setFrameOrigin:NSZeroPoint];
      [scrollView setDocumentView:view];
      [_paneScrollViews setObject:scrollView forKey:view];
    }
    [scrollView setFrameSize:NSMakeSize(width, maxPaneHeight)];
    // The pane is not flipped: its top is its highest point.
    [[scrollView contentView]
        scrollToPoint:NSMakePoint(0, paneHeight - maxPaneHeight)];
    [scrollView reflectScrolledClipView:[scrollView contentView]];
    shown = scrollView;
    paneHeight = maxPaneHeight;
  }
  CGFloat contentHeight = headerHeight + paneHeight;

  if (_activePaneView != shown) [_activePaneView removeFromSuperview];
  _activePaneView = shown;
  view = shown;

  NSRect frame = [window frame];
  NSRect newFrame =
      NSMakeRect(NSMinX(frame), NSMaxY(frame) - contentHeight - chromeHeight,
                 width, contentHeight + chromeHeight);
  [window setFrame:newFrame display:YES animate:flag];

  [_headerView setFrame:NSMakeRect(0, contentHeight - headerHeight, width,
                                   headerHeight)];
  // Panes not yet redone in TakaoForm are narrower; centre them.
  [view setFrameOrigin:NSMakePoint(floor((width - NSWidth([view frame])) / 2),
                                   0)];
  [content addSubview:view];
}

#pragma mark Converting the nib panes

// What the nib's views are to the conversion, in the order lines are read.
typedef NS_ENUM(NSInteger, TakaoNibKind) {
  TakaoNibHeading,
  TakaoNibLabel,
  TakaoNibControl,
  TakaoNibValue,
  TakaoNibWide,
  TakaoNibNote,
  TakaoNibSeparator,
};

// Containers that their controllers fill at run time; moved whole.
static BOOL TakaoNibIsOpaqueContainer(NSView *view) {
  return [[view identifier] isEqualToString:@"TakaoGeneric._genericSettingView"] ||
         [[view identifier] isEqualToString:@"TakaoLoadedModule._contentView"];
}

static void TakaoCollectNibViews(NSView *container, NSView *pane,
                                 NSMutableArray *views) {
  for (NSView *view in [container subviews]) {
    BOOL leaf = [view isKindOfClass:[NSControl class]] ||
                [view isKindOfClass:[NSScrollView class]] ||
                [view isKindOfClass:[NSProgressIndicator class]] ||
                TakaoNibIsOpaqueContainer(view);
    if ([view isKindOfClass:[NSBox class]] &&
        [(NSBox *)view boxType] != NSBoxSeparator) {
      TakaoCollectNibViews([(NSBox *)view contentView], pane, views);
    } else if (leaf || [view isKindOfClass:[NSBox class]]) {
      [views addObject:view];
    } else {
      TakaoCollectNibViews(view, pane, views);
    }
  }
}

static NSRect TakaoNibRect(NSView *view, NSView *pane) {
  return [[view superview] convertRect:[view frame] toView:pane];
}

static BOOL TakaoNibIsCheckBox(NSView *view) {
  // The button itself reports no role until it is on screen; its cell does.
  return [view isKindOfClass:[NSButton class]] &&
         [[[(NSButton *)view cell] accessibilityRole]
             isEqualToString:NSAccessibilityCheckBoxRole];
}

// The wrapping label a form row made for its note.
static NSTextField *TakaoFormNoteLabel(NSView *row, NSString *note) {
  for (NSView *view in [row subviews]) {
    if ([view isKindOfClass:[NSTextField class]] &&
        [[(NSTextField *)view stringValue] isEqualToString:note])
      return (NSTextField *)view;
    NSTextField *found = TakaoFormNoteLabel(view, note);
    if (found) return found;
  }
  return nil;
}

// My descriptions for the settings, by the identifiers the nibs carry.
static NSString *TakaoNibDescription(NSString *identifier) {
  static NSDictionary *notes = nil;
  if (!notes)
    notes = [@{
      @"TakaoSmartPhonetic._keyboardLayoutPopUpButton" :
          @"How the Bopomofo symbols are laid out on the keyboard.",
      @"TakaoPhonetic._keyboardLayoutPopUpButton" :
          @"How the Bopomofo symbols are laid out on the keyboard.",
      @"TakaoSmartPhonetic._clearComposingTextWithEscCheckBox" :
          @"Esc clears all the text not yet sent, not just the symbols being "
          @"typed.",
      @"TakaoSmartPhonetic._showCandidateListWithSpaceCheckBox" :
          @"With text in the composing area, Space opens the candidate window.",
      @"TakaoSmartPhonetic._candidateCursorAtEndOfTargetBlockMatrix" :
          @"Whether the cursor sits before or after the characters you are "
          @"choosing for.",
      @"TakaoSmartPhonetic._selectionKeyComboBox" :
          @"The keys that pick candidates in the candidate window.",
      @"TakaoSmartPhonetic._composingTextBufferSizeSlider" :
          @"How many characters the composing area holds; beyond that the "
          @"first ones are sent.",
      @"TakaoSmartPhonetic._shiftKeyAlwaysCommitUppercaseCharactersCheckBox" :
          @"Letters typed with Shift come out in upper case; off, in lower case.",
      @"TakaoSmartPhonetic._mixedAlphanumericalCheckBox" :
          @"Type English words and numbers without switching input methods.",
      @"TakaoSmartPhonetic._showEmojiCandidatesCheckBox" :
          @"The candidate window also lists matching emoji.",
      @"TakaoSmartPhonetic._showRareCharactersCheckBox" :
          @"Rare characters the lexicon lacks follow its own candidates for "
          @"their reading; they need a font that has them, such as TW-Sung.",
      @"TakaoSmartPhonetic._useCharactersSupportedByEncodingCheckBox" :
          @"Also offer the rare characters in the CNS 11643 set.",
      @"TakaoPhonetic._useCharactersSupportedByEncodingCheckBox" :
          @"Also offer the rare characters in the CNS 11643 set.",
      @"TakaoCangjie._useCharactersSupportedByEncodingCheckBox" :
          @"Also offer the rare characters in the CNS 11643 set.",
      @"TakaoSimplex._useCharactersSupportedByEncodingCheckBox" :
          @"Also offer the rare characters in the CNS 11643 set.",
      @"TakaoCangjie._shouldCommitAtMaximumRadicalLengthCheckBox" :
          @"Sends the character once all its radicals are typed, without "
          @"Space.",
      @"TakaoCangjie._useDynamicFrequencyCheckBox" :
          @"Characters you use often move up the candidate list.",
      @"TakaoCangjie._clearReadingBufferAtCompositionErrorCheckBox" :
          @"Radicals that make no character are cleared away.",
      @"TakaoSimplex._clearReadingBufferAtCompositionErrorCheckBox" :
          @"Radicals that make no character are cleared away.",
      @"TakaoCangjie._composeWhenTypingCheckBox" :
          @"Candidates show up as you type each radical.",
      @"TakaoSimplex._composeWhenTypingCheckBox" :
          @"Candidates show up as you type each radical.",
      @"TakaoCangjie._useOverrideTablePopUpButton" :
          @"Full-width or half-width punctuation.",
      @"action.launchEditor" : @"Add and change the words you use.",
      @"action.importDatabase" :
          @"Back your own words up to a file, or bring a backup back.",
      @"action.importLegacyDatabase" :
          @"Brings over the words you added in Yahoo! KeyKey.",
      @"action.uninstallChiaKey" : @"Removes BearSpark from this Mac.",
    } retain];
  NSString *note = [notes objectForKey:identifier];
  return note ? LFLSTR(note) : nil;
}

static void TakaoNibSizeControl(NSView *control, NSRect nibRect) {
  if ([control isKindOfClass:[NSSlider class]])
    [(NSSlider *)control setTrackFillColor:TakaoFormAccentColor()];
  if ([control isKindOfClass:[NSPopUpButton class]] ||
      [control isKindOfClass:[NSSlider class]])
    [[[control widthAnchor] constraintEqualToConstant:180] setActive:YES];
  else if ([control isKindOfClass:[NSComboBox class]])
    [[[control widthAnchor] constraintEqualToConstant:150] setActive:YES];
  else if ([control isKindOfClass:[NSProgressIndicator class]])
    [NSLayoutConstraint activateConstraints:@[
      [[control widthAnchor] constraintEqualToConstant:NSWidth(nibRect)],
      [[control heightAnchor] constraintEqualToConstant:NSHeight(nibRect)],
    ]];
}

// A table or a controller-filled container, at its nib size; a table runs
// full width. Several on one line sit side by side.
static NSView *TakaoNibWideContent(NSArray *wides, NSView *pane) {
  NSMutableArray *views = [NSMutableArray array];
  wides = [wides sortedArrayUsingComparator:^NSComparisonResult(NSView *a,
                                                               NSView *b) {
    return NSMinX(TakaoNibRect(a, pane)) < NSMinX(TakaoNibRect(b, pane))
               ? NSOrderedAscending
               : NSOrderedDescending;
  }];
  for (NSView *wide in wides) {
    NSRect rect = TakaoNibRect(wide, pane);
    TakaoFormPrepare(wide);
    if ([wide isKindOfClass:[NSScrollView class]]) {
      // Plain lists on a faint ground instead of the old striped tables.
      NSScrollView *scrollView = (NSScrollView *)wide;
      [scrollView setBorderType:NSNoBorder];
      [scrollView setWantsLayer:YES];
      [[scrollView layer] setCornerRadius:8];
      [scrollView setBackgroundColor:TakaoFormColor(0x000000, 0.035, 0xFFFFFF, 0.045)];
      NSTableView *table = [scrollView documentView];
      if ([table isKindOfClass:[NSTableView class]]) {
        [table setUsesAlternatingRowBackgroundColors:NO];
        [table setBackgroundColor:[NSColor clearColor]];
        [table setGridStyleMask:NSTableViewGridNone];
      }
    }
    CGFloat height = MIN(NSHeight(rect), 300);
    [[[wide heightAnchor] constraintEqualToConstant:height] setActive:YES];
    if (TakaoNibIsOpaqueContainer(wide) || [wides count] > 1)
      [[[wide widthAnchor] constraintEqualToConstant:NSWidth(rect)] setActive:YES];
    [views addObject:wide];
  }
  if ([views count] == 1) return [views objectAtIndex:0];
  NSStackView *row =
      TakaoFormStack(views, NSUserInterfaceLayoutOrientationHorizontal, 12);
  [row setAlignment:NSLayoutAttributeTop];
  return row;
}

- (void)_relayoutNibPane:(NSView *)pane {
  if (!_nibPaneViews) _nibPaneViews = [[NSMutableArray alloc] init];
  NSMutableArray *views = [NSMutableArray array];
  TakaoCollectNibViews(pane, pane, views);
  // Moving a view out of its superview would free it; outlets do not retain.
  [_nibPaneViews addObjectsFromArray:views];

  // Sort out what each view is.
  NSMutableArray *items = [NSMutableArray array];
  NSMutableArray *separators = [NSMutableArray array];
  for (NSView *view in views)
    if ([view isKindOfClass:[NSBox class]])
      [separators addObject:[NSValue valueWithRect:TakaoNibRect(view, pane)]];
  for (NSView *view in views) {
    NSRect rect = TakaoNibRect(view, pane);
    TakaoNibKind kind = TakaoNibControl;
    if ([view isKindOfClass:[NSBox class]]) {
      kind = TakaoNibSeparator;
    } else if ([view isKindOfClass:[NSScrollView class]] ||
               TakaoNibIsOpaqueContainer(view)) {
      kind = TakaoNibWide;
    } else if ([view isKindOfClass:[NSTextField class]] &&
               ![(NSTextField *)view isEditable]) {
      NSString *text = [[(NSTextField *)view stringValue]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      // Slider ends and the like carry no meaning of their own.
      if (![text length] ||
          [text rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet]
                                            invertedSet]]
                  .location == NSNotFound)
        continue;
      BOOL onSeparator = NO;
      for (NSValue *separator in separators)
        if (fabs(NSMidY([separator rectValue]) - NSMidY(rect)) < 12 &&
            NSMinX(rect) < NSMinX([separator rectValue]))
          onSeparator = YES;
      if ([text hasSuffix:@"："] || [text hasSuffix:@":"])
        kind = TakaoNibLabel;
      else if (onSeparator || NSMinX(rect) < 60)
        kind = TakaoNibHeading;
      else
        kind = TakaoNibNote;  // or a value; settled below
    }
    [items addObject:@{
      @"view" : view,
      @"kind" : @(kind),
      @"rect" : [NSValue valueWithRect:rect],
    }];
  }
  // A "note" on a label's line is the label's value.
  NSMutableArray *settled = [NSMutableArray array];
  for (NSDictionary *item in items) {
    if ([[item objectForKey:@"kind"] integerValue] != TakaoNibNote) {
      [settled addObject:item];
      continue;
    }
    NSRect rect = [[item objectForKey:@"rect"] rectValue];
    BOOL value = NO;
    for (NSDictionary *other in items)
      if ([[other objectForKey:@"kind"] integerValue] == TakaoNibLabel) {
        NSRect labelRect = [[other objectForKey:@"rect"] rectValue];
        if (fabs(NSMidY(labelRect) - NSMidY(rect)) < 6 &&
            NSMaxX(labelRect) <= NSMinX(rect) + 4)
          value = YES;
      }
    NSMutableDictionary *copy = [[item mutableCopy] autorelease];
    [copy setObject:@(value ? TakaoNibValue : TakaoNibNote) forKey:@"kind"];
    [settled addObject:copy];
  }

  // Read top to bottom; on one line, labels before what they label.
  [settled sortUsingComparator:^NSComparisonResult(NSDictionary *a,
                                                   NSDictionary *b) {
    NSRect ra = [[a objectForKey:@"rect"] rectValue];
    NSRect rb = [[b objectForKey:@"rect"] rectValue];
    if (fabs(NSMidY(ra) - NSMidY(rb)) > 4)
      return NSMidY(ra) > NSMidY(rb) ? NSOrderedAscending : NSOrderedDescending;
    NSInteger ka = [[a objectForKey:@"kind"] integerValue];
    NSInteger kb = [[b objectForKey:@"kind"] integerValue];
    if (ka != kb) return ka < kb ? NSOrderedAscending : NSOrderedDescending;
    return NSMinX(ra) < NSMinX(rb) ? NSOrderedAscending : NSOrderedDescending;
  }];

  // Group everything under the label above it.
  NSMutableArray *groups = [NSMutableArray array];
  NSMutableDictionary *group = nil;
  for (NSDictionary *item in settled) {
    TakaoNibKind kind = [[item objectForKey:@"kind"] integerValue];
    NSView *view = [item objectForKey:@"view"];
    if (kind == TakaoNibSeparator) {
      group = nil;
      continue;
    }
    if (kind == TakaoNibHeading) {
      [groups addObject:@{
        @"heading" : TakaoFormStripColon([(NSTextField *)view stringValue])
      }];
      group = nil;
      continue;
    }
    // Uninstalling is a thing of its own, whatever the nib puts it near.
    if (kind == TakaoNibLabel || !group ||
        [[view identifier] isEqualToString:@"action.uninstallChiaKey"]) {
      group = [NSMutableDictionary dictionaryWithDictionary:@{
        @"controls" : [NSMutableArray array],
        @"checkBoxes" : [NSMutableArray array],
        @"wides" : [NSMutableArray array],
        @"notes" : [NSMutableArray array],
      }];
      [groups addObject:group];
      if (kind == TakaoNibLabel) {
        [group setObject:TakaoFormStripColon([(NSTextField *)view stringValue])
                  forKey:@"title"];
        continue;
      }
    }
    if (kind == TakaoNibNote)
      [[group objectForKey:@"notes"] addObject:[(NSTextField *)view stringValue]];
    else if (kind == TakaoNibWide)
      [[group objectForKey:@"wides"] addObject:view];
    else if (TakaoNibIsCheckBox(view))
      [[group objectForKey:@"checkBoxes"] addObject:view];
    else
      [[group objectForKey:@"controls"] addObject:item];
  }

  // Then each group into rows.
  NSMutableArray *rows = [NSMutableArray array];
  for (NSDictionary *each in groups) {
    if ([each objectForKey:@"heading"]) {
      [rows addObject:TakaoFormHeading([each objectForKey:@"heading"])];
      continue;
    }
    NSString *title = [each objectForKey:@"title"];
    NSArray *checkBoxes = [each objectForKey:@"checkBoxes"];
    NSArray *wides = [each objectForKey:@"wides"];
    NSString *nibNote = [[each objectForKey:@"notes"] componentsJoinedByString:@"\n"];

    NSMutableArray *controls = [NSMutableArray array];
    NSString *note = nil;
    for (NSDictionary *item in
         [[each objectForKey:@"controls"] sortedArrayUsingComparator:^NSComparisonResult(
                                              NSDictionary *a, NSDictionary *b) {
           return NSMinX([[a objectForKey:@"rect"] rectValue]) <
                          NSMinX([[b objectForKey:@"rect"] rectValue])
                      ? NSOrderedAscending
                      : NSOrderedDescending;
         }]) {
      NSView *control = [item objectForKey:@"view"];
      if (!note) note = TakaoNibDescription([control identifier]);
      if ([control isKindOfClass:[NSMatrix class]]) {
        NSView *popUp = [TakaoMatrixPopUpButton popUpMirroring:(NSMatrix *)control];
        [_nibPaneViews addObject:popUp];
        // Radio titles run long; give them room rather than the usual 180.
        [[[popUp widthAnchor] constraintEqualToConstant:250] setActive:YES];
        control = popUp;
        [controls addObject:control];
        continue;
      } else if ([control isKindOfClass:[NSTextField class]] &&
                 ![(NSTextField *)control isEditable]) {
        [(NSTextField *)control setTextColor:TakaoFormSecondaryTextColor()];
      }
      TakaoNibSizeControl(control, [[item objectForKey:@"rect"] rectValue]);
      [controls addObject:control];
      if ([control isKindOfClass:[NSSlider class]]) {
        NSView *value = [TakaoSliderValueLabel labelMirroring:(NSSlider *)control];
        [_nibPaneViews addObject:value];
        [controls addObject:value];
      }
    }

    BOOL lone = ![controls count] && ![wides count];
    if (![title length] && [wides count] && [controls count]) {
      // An untitled list with its buttons (+ and −): the buttons go under it,
      // where the nib had them.
      for (NSView *control in controls) TakaoFormPrepare(control);
      NSStackView *buttons = TakaoFormStack(
          controls, NSUserInterfaceLayoutOrientationHorizontal, 0);
      NSView *list = TakaoNibWideContent(wides, pane);
      NSStackView *block = TakaoFormStack(
          @[ list, buttons ], NSUserInterfaceLayoutOrientationVertical, 6);
      [rows addObject:TakaoFormRowWithContent(@"", nibNote, @[], block)];
      nibNote = nil;
    } else if ([controls count] || [wides count]) {
      NSView *below = [wides count] ? TakaoNibWideContent(wides, pane) : nil;
      NSString *rowTitle = title;
      // A lone button with no label names its own row.
      if (![rowTitle length] && [controls count] == 1 &&
          [[controls objectAtIndex:0] isKindOfClass:[NSButton class]])
        rowTitle = TakaoFormStripColon([[controls objectAtIndex:0] title]);
      if ([rowTitle length] || [controls count])
        [rows addObject:TakaoFormRowWithContent(
                            rowTitle ? rowTitle : @"", note ? note : nibNote,
                            controls, below)];
      else
        [rows addObject:TakaoFormRowWithContent(@"", nil, @[], below)];
      nibNote = nil;
    } else if (lone && [checkBoxes count] > 1 && [title length]) {
      [rows addObject:TakaoFormHeadingWithNote(title, nibNote)];
      nibNote = nil;
    }
    for (NSButton *checkBox in checkBoxes) {
      NSString *switchNote = TakaoNibDescription([checkBox identifier]);
      if (!switchNote && [checkBoxes count] == 1) switchNote = nibNote;
      [rows addObject:TakaoFormRow([checkBox title], switchNote,
                                   @[ [TakaoSwitch switchMirroring:checkBox] ])];
      // The rare characters need a font the system lacks: right under their
      // switch, whether one is installed and where to get one. Always shown,
      // so the pane keeps its height; only the note changes.
      id owner = [checkBox target];
      if ([[checkBox identifier]
              isEqualToString:@"TakaoSmartPhonetic._showRareCharactersCheckBox"] &&
          [owner isKindOfClass:[TakaoSmartPhonetic class]]) {
        NSString *fontNote = [owner rareCharacterFontNote];
        NSButton *kai = [NSButton buttonWithTitle:LFLSTR(@"Download TW-Kai")
                                           target:owner
                                           action:@selector(downloadRareCharacterFont:)];
        [kai setTag:0];
        NSButton *sung = [NSButton buttonWithTitle:LFLSTR(@"Download TW-Sung")
                                            target:owner
                                            action:@selector(downloadRareCharacterFont:)];
        [sung setTag:1];
        NSView *fontRow =
            TakaoFormRow(LFLSTR(@"CNS 11643 fonts"), fontNote, @[ kai, sung ]);
        [owner setRareCharacterFontNoteLabel:TakaoFormNoteLabel(fontRow, fontNote)];
        [rows addObject:fontRow];
      }
    }
  }

  TakaoFormInstall(pane, rows);
}

#pragma mark Header

- (void)_buildHeader {
  NSView *content = [window contentView];
  _tabButtons = [[NSMutableArray alloc] init];
  _tabUnderlines = [[NSMutableArray alloc] init];

  _headerTitle = [TakaoFormLabel(LFLSTR(GeneralToolbarItemIdentifier),
                                 TakaoFormTitleFont(28), TakaoFormTextColor())
      retain];
  NSTextField *subtitle = TakaoFormLabel(
      LFLSTR(@"BearSpark Preferences"), [NSFont systemFontOfSize:12],
      TakaoFormSecondaryTextColor());
  NSView *spacer = [[[NSView alloc] init] autorelease];
  [spacer setContentHuggingPriority:1
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
  NSStackView *titleRow = TakaoFormStack(
      @[ _headerTitle, spacer, subtitle ],
      NSUserInterfaceLayoutOrientationHorizontal, 8);
  [titleRow setAlignment:NSLayoutAttributeLastBaseline];

  NSMutableArray *tabs = [NSMutableArray array];
  for (NSString *identifier in [self toolbarDefaultItemIdentifiers:nil]) {
    NSImage *icon = [[[NSImage imageNamed:TakaoPaneIconName(identifier)] copy]
        autorelease];
    [icon setSize:NSMakeSize(16, 16)];
    NSButton *button = [NSButton buttonWithTitle:LFLSTR(identifier)
                                           image:icon
                                          target:self
                                          action:@selector(_tabClicked:)];
    [button setBordered:NO];
    [button setImagePosition:NSImageLeading];
    [button setImageHugsTitle:YES];
    [button setIdentifier:identifier];
    [button setFont:[NSFont systemFontOfSize:13]];
    [button setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSBox *underline = [[[NSBox alloc] init] autorelease];
    [underline setBoxType:NSBoxCustom];
    [underline setBorderWidth:0];
    [underline setTitlePosition:NSNoTitle];
    [underline setFillColor:TakaoFormAccentColor()];
    [underline setTranslatesAutoresizingMaskIntoConstraints:NO];
    [[[underline heightAnchor] constraintEqualToConstant:2] setActive:YES];

    NSStackView *tab = TakaoFormStack(
        @[ button, underline ], NSUserInterfaceLayoutOrientationVertical, 8);
    [[[underline widthAnchor] constraintEqualToAnchor:[tab widthAnchor]]
        setActive:YES];
    [tabs addObject:tab];
    [_tabButtons addObject:button];
    [_tabUnderlines addObject:underline];
  }
  NSStackView *tabRow =
      TakaoFormStack(tabs, NSUserInterfaceLayoutOrientationHorizontal, 12);
  [tabRow setAlignment:NSLayoutAttributeBottom];

  NSView *hairline = TakaoFormHairline();
  NSStackView *header = TakaoFormStack(
      @[ titleRow, tabRow, hairline ], NSUserInterfaceLayoutOrientationVertical,
      18);
  [header setSpacing:0];
  [header setCustomSpacing:18 afterView:titleRow];
  // Clears the traffic lights in the transparent title bar.
  [header setEdgeInsets:NSEdgeInsetsMake(48, TakaoFormMargin, 0,
                                         TakaoFormMargin)];

  _headerView = [[NSView alloc] init];
  [_headerView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [_headerView addSubview:header];
  CGFloat inner = TakaoFormPaneWidth - TakaoFormMargin * 2;
  [NSLayoutConstraint activateConstraints:@[
    [[header leadingAnchor] constraintEqualToAnchor:[_headerView leadingAnchor]],
    [[header topAnchor] constraintEqualToAnchor:[_headerView topAnchor]],
    [[header widthAnchor] constraintEqualToConstant:TakaoFormPaneWidth],
    [[titleRow widthAnchor] constraintEqualToConstant:inner],
    [[hairline widthAnchor] constraintEqualToConstant:inner],
  ]];
  [_headerView setFrame:NSMakeRect(0, 0, TakaoFormPaneWidth, 400)];
  [_headerView layoutSubtreeIfNeeded];
  [_headerView setFrame:NSMakeRect(0, 0, TakaoFormPaneWidth,
                                   ceil(NSHeight([header frame])))];
  [content addSubview:_headerView];
}

- (void)_selectTabWithIdentifier:(NSString *)identifier {
  [_headerTitle setStringValue:LFLSTR(identifier)];
  for (NSUInteger i = 0; i < [_tabButtons count]; i++) {
    NSButton *button = [_tabButtons objectAtIndex:i];
    BOOL selected = [[button identifier] isEqualToString:identifier];
    NSColor *color =
        selected ? TakaoFormTextColor() : TakaoFormSecondaryTextColor();
    [button setContentTintColor:color];
    [button setAttributedTitle:[[[NSAttributedString alloc]
                                   initWithString:[button title]
                                       attributes:@{
                                         NSForegroundColorAttributeName : color,
                                         NSFontAttributeName : [button font]
                                       }] autorelease]];
    [[_tabUnderlines objectAtIndex:i] setHidden:NO];
    [[_tabUnderlines objectAtIndex:i]
        setFillColor:selected ? TakaoFormAccentColor() : [NSColor clearColor]];
  }
}

- (void)_tabClicked:(NSButton *)sender {
  [self _showPaneWithIdentifier:[sender identifier] animate:YES];
}

- (void)setAppIcon:(NSImage *)image {
  NSImage *i =
      [[[NSImage alloc] initWithSize:NSMakeSize(512.0, 512.0)] autorelease];
  int height = [i size].height;
  int width = [i size].width;
  NSRect fullRect = NSMakeRect(0, 0, width, height);
  NSRect newRect = NSMakeRect(width / 2, 0, width / 2, height / 2);
  [i lockFocus];
  [_defaultApplicationImage drawInRect:fullRect
                             fromRect:NSZeroRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0];
  [image drawInRect:newRect
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:1.0];
  [i unlockFocus];
  [window setMiniwindowImage:i];
}

- (void)toggleActivePreferenceView:(id)sender {
  [self _showPaneWithIdentifier:[sender itemIdentifier] animate:YES];
}

- (void)_showPaneWithIdentifier:(NSString *)identifier animate:(BOOL)flag {
  NSView *view = nil;

  if ([identifier isEqualToString:GeneralToolbarItemIdentifier])
    view = _generalView;
  else if ([identifier
               isEqualToString:PhoneticToolbarItemIdentifier])
    view = _phoneticView;
  else if ([identifier
               isEqualToString:CangjieToolbarItemIdentifier])
    view = _cangjieView;
  else if ([identifier
               isEqualToString:SimplexToolbarItemIdentifier])
    view = _simpexView;
  else if ([identifier
               isEqualToString:PhraseToolbarItemIdentifier])
    view = _phraseView;
  else if ([identifier
               isEqualToString:UpdateToolbarItemIdentifier])
    view = _updateView;
  else if ([identifier
               isEqualToString:GenericToolbarItemIdentifier])
    view = _genericSettingView;
  else if ([identifier
               isEqualToString:PluginToolbarItemIdentifier])
    view = _pluginView;

  if (view != _generalView) {
    [[NSColorPanel sharedColorPanel] orderOut:self];
  }

  if (!view) return;
  [self _selectTabWithIdentifier:identifier];
  [self setActiveView:view animate:flag];
  [self setAppIcon:[NSImage imageNamed:TakaoPaneIconName(identifier)]];
  [TakaoSwitch syncMirroredControls];
  [window setTitle:LFLSTR(identifier)];

  if ([identifier isEqualToString:UpdateToolbarItemIdentifier] &&
      [_takaoUpdateController respondsToSelector:@selector(updatePaneDidBecomeActive)]) {
    [(TakaoUpdate *)_takaoUpdateController updatePaneDidBecomeActive];
  }
}

#pragma mark NSApplication delegate methods

// Clicking the Dock icon brings the window back, minimized or behind others.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)flag {
  [window makeKeyAndOrderFront:self];
  [NSApp activateIgnoringOtherApps:YES];
  return NO;
}

#pragma mark NSWindow delegate methods

- (void)windowWillClose:(NSNotification *)notification {
  [[NSApplication sharedApplication] terminate:self];
}

@end
