// [AUTO_HEADER]

#import "CVHorizontalCandidateController.h"

#import "OpenVanillaController.h"

#import <QuartzCore/QuartzCore.h>

// Timings of the built-in Zhuyin window, measured from a screen recording:
// the frame glides from one size and place to the other, growing a little
// slower than it shrinks.
static const NSTimeInterval kExpandAnimationDuration = 0.25;
static const NSTimeInterval kCollapseAnimationDuration = 0.18;

const char CVAssociationSelectionKeys[] = "!@#$%^&*(";

// A panel shown but not in control is the associated-phrase filter's.
static BOOL CVIsAssociationPanel(PVOneDimensionalCandidatePanel *panel) {
  return !panel->isInControl();
}

@implementation CVHorizontalCandidateController

- (void)dealloc {
  [_candidateView release];
  [_gridKeys release];
  [_backgroundColor release];
  [_foregroundColor release];
  [_highlightTextColor release];
  [super dealloc];
}
- (id)init {
  self = [super init];
  if (self != nil) {
    BOOL loaded = [[NSBundle mainBundle] loadNibNamed:[self nibName]
                                                owner:self
                                      topLevelObjects:nil];
    NSAssert((loaded == YES), @"NIB did not load");
  }
  return self;
}
- (NSString *)nibName {
  return @"HorizontalCandidateWindow";
}
- (BOOL)isVertical {
  return NO;
}
- (void)awakeFromNib {
  // The nib's controls are superseded by CVTDKCandidateView; the outlets stay
  // so the nib still loads, but the views are no longer in the window.
  _candidateView = [[CVTDKCandidateView alloc] initWithVertical:[self isVertical]];
  [_candidateView installInWindow:[self window]];
  [_candidateView setTarget:self];
  [_candidateView setAction:@selector(sendKey:)];
  [_candidateView setChevronAction:@selector(toggleExpanded:)];
  _sending = NO;
}
- (void)setFontHeight:(float)newHeight {
  _fontHeight = newHeight;
  if (_fontHeight < 20) _fontHeight = 20;
}
- (void)updateDisplay:(PVOneDimensionalCandidatePanel *)panel
              atPoint:(NSPoint)position {
  // hide if it's invisible--before update
  if (!panel->isVisible()) {
    _expanded = NO;
    [[self window] orderOut:self];
    return;
  }

  _sending = NO;

  NSPoint newPosition = position;

  // update the content
  size_t fromIndex = panel->currentPage() * panel->candidatesPerPage();
  size_t index;
  size_t count = panel->currentPageCandidateCount();
  size_t highlightedIndex = panel->currentHightlightIndex();
  NSString *prompt = [NSString stringWithUTF8String:panel->prompt().c_str()];

  OVCandidateList *list = panel->candidateList();

  NSMutableArray *candidates = [NSMutableArray array];
  NSMutableArray *keys = [NSMutableArray array];
  for (index = 0; index < count; index++) {
    string candidate = list->candidateAtIndex(fromIndex + index);
    string keyString = panel->candidateKeyAtIndex(index).receivedString();
    [candidates addObject:[NSString stringWithUTF8String:candidate.c_str()]];
    [keys addObject:[NSString stringWithUTF8String:keyString.c_str()]];
  }

  // The accessories close the list, apart from the pages; one highlighted
  // takes the highlight off the candidates.
  size_t accessoryCount = panel->accessoryCount();
  size_t mainCount = list->size() - accessoryCount;
  NSMutableArray *accessories = [NSMutableArray array];
  for (size_t at = mainCount; at < list->size(); at++)
    [accessories addObject:[NSString stringWithUTF8String:list->candidateAtIndex(at)
                                                              .c_str()]];
  size_t accessoryHighlight = panel->accessoryHighlightIndex();
  BOOL accessoryHighlighted = accessoryHighlight < accessoryCount;
  // The grid has room enough as it is; the accessories wait for it to fold.
  [_candidateView setAccessories:_expanded ? @[] : accessories
                highlightedIndex:accessoryHighlighted ? (NSInteger)accessoryHighlight
                                                      : -1];

  NSInteger highlight = panel->isInControl() && !accessoryHighlighted
                            ? (NSInteger)highlightedIndex
                            : -1;
  // Associated phrases are offered, not in control, but clicking still picks.
  [_candidateView setClickable:YES];
  if (_expanded) {
    NSMutableArray *all = [NSMutableArray array];
    for (size_t at = 0; at < mainCount; at++)
      [all addObject:[NSString stringWithUTF8String:list->candidateAtIndex(at)
                                                        .c_str()]];
    [_candidateView
        setGridCandidates:all
                     keys:_gridKeys
         highlightedIndex:accessoryHighlighted ? -1 : (NSInteger)panel->currentPage()
                    width:_gridWidth
                   prompt:prompt];
  } else {
    [_candidateView setShowsChevron:[self canExpandPanel:panel]];
    [_candidateView setCandidates:candidates
                             keys:keys
                 highlightedIndex:highlight
                           prompt:prompt];
  }

  NSRect windowFrame = [[self window] frame];
  windowFrame.size = [_candidateView contentSize];

  NSRect frame = [[NSScreen mainScreen] visibleFrame];
  NSArray *screens = [NSScreen screens];
  NSUInteger i, c = [screens count];
  if ([screens count] > 1) {
    for (i = 0; i < c; i++) {
      NSScreen *screen = [screens objectAtIndex:i];
      NSRect screenFrame = [screen frame];

      if (newPosition.x >= NSMinX(screenFrame) &&
          newPosition.x <= NSMaxX(screenFrame)) {
        frame = [screen visibleFrame];
        break;
      }
    }
  }

  if (newPosition.y < NSMinY(frame))
    newPosition.y = NSMinY(frame);
  else if (newPosition.y - windowFrame.size.height < NSMinY(frame))
    newPosition.y = newPosition.y + _fontHeight;
  //	else if (newPosition.y + windowFrame.size.height > NSMaxY(frame))
  else if (newPosition.y > NSMaxY(frame))
    newPosition.y = NSMaxY(frame) - windowFrame.size.height;
  else
    newPosition.y = newPosition.y - windowFrame.size.height;

  if (newPosition.x < NSMinX(frame))
    newPosition.x = NSMinX(frame);
  else if (newPosition.x + windowFrame.size.width > NSMaxX(frame))
    newPosition.x = NSMaxX(frame) - windowFrame.size.width;

  windowFrame.origin = newPosition;

  NSTimeInterval animation = [[self window] isVisible] ? _pendingFrameAnimation : 0;
  _pendingFrameAnimation = 0;
  if (animation > 0) {
    // Through the animator so typing is not held up while it plays.
    NSWindow *window = [self window];
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext *context) {
          [context setDuration:animation];
          [context setTimingFunction:
                       [CAMediaTimingFunction
                           functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
          [[window animator] setFrame:windowFrame display:YES];
        }
        completionHandler:^{
          [window invalidateShadow];
        }];
  } else {
    [[self window] setFrame:windowFrame display:YES];
    [[self window] invalidateShadow];
  }

  if (panel->isVisible()) [[self window] makeKeyAndOrderFront:self];
}
- (void)updateContent:(PVOneDimensionalCandidatePanel *)panel
              atPoint:(NSPoint)position;
{
  [self updateDisplay:panel atPoint:position];
  _panel = panel;
}
- (void)hide {
  [[self window] orderOut:self];
}
- (IBAction)sendKey:(id)sender {
  if (_sending) return;
  NSInteger accessory = [_candidateView clickedAccessoryIndex];
  if (accessory >= 0) {
    _panel->setAccessoryHighlightIndex((size_t)accessory);
    [OpenVanillaController handleCandidateWindowKey:OVKeyCode::Return modifiers:0];
    return;
  }
  NSInteger selectedItem = [_candidateView clickedIndex];
  if (selectedItem < 0) return;
  BOOL associating = CVIsAssociationPanel(_panel);
  if (_expanded && associating) {
    // One candidate per page: the first selection key picks the current one.
    _panel->goToPage((size_t)selectedItem);
    [OpenVanillaController handleCandidateWindowKey:CVAssociationSelectionKeys[0]
                                          modifiers:OVKeyMask::Shift];
    return;
  }
  if (associating) {
    if (selectedItem >= (NSInteger)strlen(CVAssociationSelectionKeys)) return;
    [OpenVanillaController
        handleCandidateWindowKey:CVAssociationSelectionKeys[selectedItem]
                       modifiers:OVKeyMask::Shift];
    return;
  }
  NSString *key = nil;
  if (_expanded) {
    // Make the clicked candidate current and type its key within its row,
    // which handleGridKey:panel: turns back into that candidate.
    _panel->goToPage((size_t)selectedItem);
    NSInteger position = [_candidateView gridPositionInRowOfIndex:selectedItem];
    if (position < 0 || position >= (NSInteger)[_gridKeys count]) return;
    key = [_gridKeys objectAtIndex:position];
  } else {
    key = [NSString
        stringWithUTF8String:_panel->candidateKeyAtIndex(selectedItem)
                                 .receivedString()
                                 .c_str()];
  }
  if (![key length]) return;
  [OpenVanillaController handleCandidateWindowKey:[key characterAtIndex:0]
                                        modifiers:0];
}
- (IBAction)gotoNextPage:(id)sender {
  _panel->goToNextPage();
  NSPoint p = [[self window] frame].origin;
  p.y = NSMaxY([[self window] frame]);
  [self updateDisplay:_panel atPoint:p];
}
- (IBAction)gotoPreviousPage:(id)sender {
  _panel->goToPreviousPage();
  NSPoint p = [[self window] frame].origin;
  p.y = NSMaxY([[self window] frame]);
  [self updateDisplay:_panel atPoint:p];
}

- (void)setCandidateTextHeight:(float)inTextHeight {
  [_candidateView setCandidateTextHeight:inTextHeight];
}

- (BOOL)isExpanded {
  return _expanded;
}
- (BOOL)canExpandPanel:(PVOneDimensionalCandidatePanel *)panel {
  return panel->candidateList()->size() - panel->accessoryCount() >
         panel->candidatesPerPage();
}
- (void)expandPanel:(PVOneDimensionalCandidatePanel *)panel {
  if (_expanded || ![self canExpandPanel:panel]) return;
  size_t perPage = panel->candidatesPerPage();
  NSMutableArray *keys = [NSMutableArray array];
  for (size_t i = 0; i < perPage; i++)
    [keys addObject:[NSString stringWithUTF8String:panel->candidateKeyAtIndex(i)
                                                        .receivedString()
                                                        .c_str()]];
  [_gridKeys release];
  _gridKeys = [keys copy];
  _gridWidth = [_candidateView contentSize].width;
  // Not shown in the grid, so not to be chosen there unseen.
  panel->setAccessoryHighlightIndex(string::npos);

  // One candidate per page makes the page number the grid position, and the
  // panel's own "choose highlighted" then picks whichever is current.
  // Associated phrases have no highlight yet; start from the page's first.
  size_t index = panel->currentPage() * perPage +
                 (CVIsAssociationPanel(panel) ? 0 : panel->currentHightlightIndex());
  _collapsedCandidatesPerPage = perPage;
  panel->setCandidatesPerPage(1);
  panel->goToPage(index);
  panel->setHighlightIndex(0);
  _expanded = YES;
  _pendingFrameAnimation = kExpandAnimationDuration;
}
- (void)collapsePanel:(PVOneDimensionalCandidatePanel *)panel {
  if (!_expanded) return;
  size_t index = panel->currentPage();
  panel->setCandidatesPerPage(_collapsedCandidatesPerPage);
  panel->goToPage(index / _collapsedCandidatesPerPage);
  panel->setHighlightIndex(index % _collapsedCandidatesPerPage);
  _expanded = NO;
  _pendingFrameAnimation = kCollapseAnimationDuration;
}
- (CVGridKeyResult)handleGridKey:(const OVKey *)key
                           panel:(PVOneDimensionalCandidatePanel *)panel {
  // The grid shows no accessories, so Tab has nothing to reach there.
  if (key->keyCode() == OVKeyCode::Tab) return CVGridKeyMoved;
  // Keys the grid takes (moving, choosing by key) leave the accessories; the
  // ones it passes on, Return among them, are the panel's to handle.
  CVGridKeyResult result = [self moveInGridWithKey:key panel:panel];
  if (result != CVGridKeyIgnored) panel->setAccessoryHighlightIndex(string::npos);
  return result;
}
- (CVGridKeyResult)moveInGridWithKey:(const OVKey *)key
                               panel:(PVOneDimensionalCandidatePanel *)panel {
  NSInteger index = (NSInteger)panel->currentPage();
  NSInteger target = -1;
  unsigned int keyCode = key->keyCode();
  if ([self isVertical]) {
    // The vertical grid's columns are what the horizontal grid's rows are:
    // Up and Down stay in the column, Left and Right change column.
    NSInteger position = [_candidateView gridPositionInRowOfIndex:index];
    switch (keyCode) {
      case OVKeyCode::Up:
        target = [_candidateView gridIndexForKeyAtPosition:position - 1
                                                 fromIndex:index];
        if (target < 0) return CVGridKeyRejected;
        panel->goToPage((size_t)target);
        return CVGridKeyMoved;
      case OVKeyCode::Down:
        target = [_candidateView gridIndexForKeyAtPosition:position + 1
                                                 fromIndex:index];
        if (target < 0) return CVGridKeyRejected;
        panel->goToPage((size_t)target);
        return CVGridKeyMoved;
      case OVKeyCode::Left:
        keyCode = OVKeyCode::Up;  // folds back from the first column
        break;
      case OVKeyCode::Right:
        keyCode = OVKeyCode::PageDown;
        break;
    }
  }
  switch (keyCode) {
    case OVKeyCode::Left:
      target = index - 1;
      break;
    case OVKeyCode::Right:
      target = index + 1 < (NSInteger)panel->candidateList()->size() ? index + 1 : -1;
      break;
    case OVKeyCode::Down:
    case OVKeyCode::Space:
    case OVKeyCode::PageDown:
      target = [_candidateView gridIndexMovingRows:1 fromIndex:index];
      break;
    case OVKeyCode::Up:
      target = [_candidateView gridIndexMovingRows:-1 fromIndex:index];
      // Up from the first row (Left from the first column, when vertical)
      // folds the grid back into the single row, on the same candidate.
      if (target < 0) {
        [self collapsePanel:panel];
        return CVGridKeyMoved;
      }
      break;
    case OVKeyCode::PageUp:
      target = [_candidateView gridIndexMovingRows:-1 fromIndex:index];
      break;
    case OVKeyCode::Return:
      // The associated-phrase filter only drops its list on Return; in the
      // grid it picks the highlighted phrase. (A panel in control picks on
      // Return by itself.)
      if (!CVIsAssociationPanel(panel)) return CVGridKeyIgnored;
      return CVGridKeyChoose;
    default: {
      if (CVIsAssociationPanel(panel)) {
        const char *found = key->isShiftPressed() && key->keyCode() < 128
                                ? strchr(CVAssociationSelectionKeys,
                                         (int)key->keyCode())
                                : NULL;
        if (!found || !key->keyCode()) return CVGridKeyIgnored;
        target = [_candidateView
            gridIndexForKeyAtPosition:found - CVAssociationSelectionKeys
                            fromIndex:index];
        if (target < 0) return CVGridKeyRejected;
        panel->goToPage((size_t)target);
        return CVGridKeyChoose;
      }
      NSString *received =
          [NSString stringWithUTF8String:key->receivedString().c_str()];
      NSUInteger position = [_gridKeys indexOfObject:received];
      if (position == NSNotFound) return CVGridKeyIgnored;
      target = [_candidateView gridIndexForKeyAtPosition:position
                                               fromIndex:index];
      if (target < 0) return CVGridKeyRejected;
      panel->goToPage((size_t)target);
      return CVGridKeyChoose;
    }
  }
  if (target < 0) return CVGridKeyRejected;
  panel->goToPage((size_t)target);
  return CVGridKeyMoved;
}
- (IBAction)toggleExpanded:(id)sender {
  if (_expanded)
    [self collapsePanel:_panel];
  else
    [self expandPanel:_panel];
  NSPoint p = [[self window] frame].origin;
  p.y = NSMaxY([[self window] frame]);
  [self updateDisplay:_panel atPoint:p];
}

@end
