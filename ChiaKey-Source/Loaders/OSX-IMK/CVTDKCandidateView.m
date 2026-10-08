// [AUTO_HEADER]

#import "CVTDKCandidateView.h"

// Metrics are measured from the macOS 27 built-in Zhuyin candidate window at
// its 16pt candidate size, and scale with the configured candidate size.
static const CGFloat kReferenceFontSize = 16.0;
static const CGFloat kCellHeight = 24.0;     // highlight capsule height
static const CGFloat kInset = 2.0;           // panel edge to highlight
static const CGFloat kCellGap = 4.5;         // between adjacent cells
static const CGFloat kNumberX = 4.0;         // cell edge to selection number
static const CGFloat kPhraseX = 14.0;        // cell edge to candidate text
static const CGFloat kPhraseTrailing = 6.0;  // candidate text to cell edge
static const CGFloat kNumberFontSize = 9.0;
static const CGFloat kNumberDrop = 1.0;      // numbers sit slightly low
static const CGFloat kSeparatorGap = 20.0;   // last cell to separator
static const CGFloat kChevronArea = 40.0;    // separator to panel edge
static const CGFloat kChevronWidth = 8.0;
static const CGFloat kChevronHeight = 4.5;
static const CGFloat kSeparatorLength = 20.0;
static const CGFloat kPanelRadius = kCellHeight / 2 + kInset;
static const CGFloat kGridColumn = 61.0;           // expanded column pitch
static const NSUInteger kGridColumns = 6;
static const NSInteger kGridVisibleRows = 5;
static const CGFloat kAccessoryPadding = 10.0;      // accessory edge to text
static const CGFloat kAccessoryGap = 4.5;           // between accessories
static const CGFloat kAccessorySeparatorGap = 10.0; // hairline to either side
static const CGFloat kTabHintPadding = 3.0;         // "tab" to its outline

@implementation CVTDKCandidateView

- (id)initWithVertical:(BOOL)vertical {
  self = [super initWithFrame:NSMakeRect(0, 0, 100, 40)];
  if (self != nil) {
    _vertical = vertical;
    _fontSize = kReferenceFontSize;
    _showsChevron = YES;
    _highlightedIndex = -1;
    _clickedIndex = -1;
    _candidates = [[NSArray alloc] init];
    _keys = [[NSArray alloc] init];
    _prompt = [@"" retain];
    _gridRows = [[NSMutableArray alloc] init];
    _gridColumns = [[NSMutableArray alloc] init];
    _gridSpans = [[NSMutableArray alloc] init];
    _gridRowStarts = [[NSMutableArray alloc] init];
    _cellRects = [[NSMutableArray alloc] init];
    _cellIndexes = [[NSMutableArray alloc] init];
    _accessories = [[NSArray alloc] init];
    _accessoryRects = [[NSMutableArray alloc] init];
    _accessoryHighlight = -1;
    _clickedAccessory = -1;
  }
  return self;
}
- (void)dealloc {
  [_candidates release];
  [_keys release];
  [_prompt release];
  [_gridRows release];
  [_gridColumns release];
  [_gridSpans release];
  [_gridRowStarts release];
  [_cellRects release];
  [_cellIndexes release];
  [_accessories release];
  [_accessoryRects release];
  [super dealloc];
}
- (BOOL)isFlipped {
  return YES;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
  return YES;
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  [self setNeedsDisplay:YES];
}

#pragma mark Window

- (void)installInWindow:(NSWindow *)window {
  NSRect frame = NSMakeRect(0, 0, 100, 40);
  NSView *container = [[[NSView alloc] initWithFrame:frame] autorelease];
  [container setWantsLayer:YES];
  [[container layer] setMasksToBounds:YES];

  // The built-in panel is Liquid Glass; older systems get the closest
  // vibrancy material instead.
  NSView *background = nil;
  Class glassClass = NSClassFromString(@"NSGlassEffectView");
  if (glassClass) {
    background = [[[glassClass alloc] initWithFrame:frame] autorelease];
  } else {
    NSVisualEffectView *effectView =
        [[[NSVisualEffectView alloc] initWithFrame:frame] autorelease];
    [effectView setMaterial:NSVisualEffectMaterialMenu];
    [effectView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [effectView setState:NSVisualEffectStateActive];
    [effectView setWantsLayer:YES];
    [[effectView layer] setMasksToBounds:YES];
    background = effectView;
  }
  [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [container addSubview:background];

  [self setFrame:frame];
  [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [container addSubview:self];

  _containerView = container;
  _backgroundView = background;
  [self updateCornerRadius];

  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:YES];
  [window setContentView:container];
}
- (void)updateCornerRadius {
  CGFloat radius = kPanelRadius * [self scale];
  [[_containerView layer] setCornerRadius:radius];
  if ([_backgroundView isKindOfClass:[NSVisualEffectView class]])
    [[_backgroundView layer] setCornerRadius:radius];
  else
    [_backgroundView setValue:@(radius) forKey:@"cornerRadius"];
}

#pragma mark Colors and fonts

- (CGFloat)scale {
  return _fontSize / kReferenceFontSize;
}
- (NSColor *)highlightColor {
  return [NSColor controlAccentColor];
}
// White on the accent color, except black on a yellow accent.
- (NSColor *)highlightedTextColor {
  NSColor *accent =
      [[NSColor controlAccentColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  NSColor *yellow =
      [[NSColor systemYellowColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  if (accent && yellow) {
    CGFloat hue = [accent hueComponent];
    if (hue == [yellow hueComponent] || (hue >= 0.12 && hue <= 0.182))
      return [NSColor blackColor];
  }
  return [NSColor whiteColor];
}
- (NSFont *)phraseFont {
  return [NSFont systemFontOfSize:_fontSize];
}
- (NSFont *)numberFont {
  return [NSFont systemFontOfSize:round(kNumberFontSize * [self scale])];
}
- (NSFont *)promptFont {
  return [NSFont systemFontOfSize:MAX(round(11 * [self scale]), 11)];
}
- (NSDictionary *)phraseAttributesHighlighted:(BOOL)highlighted {
  return @{
    NSFontAttributeName : [self phraseFont],
    NSForegroundColorAttributeName :
        (highlighted ? [self highlightedTextColor] : [NSColor labelColor])
  };
}
// Characters from CJK Extension B on fall outside the system's fallback fonts
// (even where PingFang SC has them), so they would draw as boxes. One found in
// whichever installed font has it (TW-Sung and the like) is drawn in that font.
// The answer per character is kept; only those characters are looked up.
static NSString *CVFontNameForRareCharacter(UTF32Char character) {
  static NSMutableDictionary *found = nil;
  if (!found) found = [[NSMutableDictionary alloc] init];
  NSNumber *key = @(character);
  id known = [found objectForKey:key];
  if (known) return known == [NSNull null] ? nil : known;

  NSCharacterSet *set =
      [NSCharacterSet characterSetWithRange:NSMakeRange(character, 1)];
  NSFontDescriptor *wanted = [NSFontDescriptor
      fontDescriptorWithFontAttributes:@{NSFontCharacterSetAttribute : set}];
  NSString *name = nil;
  for (NSFontDescriptor *candidate in [wanted
           matchingFontDescriptorsWithMandatoryKeys:
               [NSSet setWithObject:NSFontCharacterSetAttribute]]) {
    NSString *each = [candidate objectForKey:NSFontNameAttribute];
    if ([each length] && ![each isEqualToString:@"LastResort"]) {
      name = each;
      break;
    }
  }
  [found setObject:(name ? (id)name : (id)[NSNull null]) forKey:key];
  return name;
}
// The phrase attributes, in a font that has the text's rare characters.
- (NSDictionary *)phraseAttributesForText:(NSString *)text
                              highlighted:(BOOL)highlighted {
  NSDictionary *attributes = [self phraseAttributesHighlighted:highlighted];
  __block NSString *fontName = nil;
  [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                           options:NSStringEnumerationByComposedCharacterSequences
                        usingBlock:^(NSString *piece, NSRange range, NSRange enclosing,
                                     BOOL *stop) {
                          UTF32Char character = 0;
                          if (![piece getBytes:&character
                                     maxLength:sizeof(character)
                                    usedLength:NULL
                                      encoding:NSUTF32LittleEndianStringEncoding
                                       options:0
                                         range:NSMakeRange(0, [piece length])
                                remainingRange:NULL])
                            return;
                          if (character < 0x20000) return;
                          fontName = CVFontNameForRareCharacter(character);
                          if (fontName) *stop = YES;
                        }];
  NSFont *font = fontName ? [NSFont fontWithName:fontName size:_fontSize] : nil;
  if (!font) return attributes;
  NSMutableDictionary *withFont = [[attributes mutableCopy] autorelease];
  [withFont setObject:font forKey:NSFontAttributeName];
  return withFont;
}
- (NSDictionary *)numberAttributesHighlighted:(BOOL)highlighted {
  return @{
    NSFontAttributeName : [self numberFont],
    NSForegroundColorAttributeName :
        (highlighted ? [self highlightedTextColor]
                     : [NSColor secondaryLabelColor])
  };
}
- (NSDictionary *)promptAttributes {
  return @{
    NSFontAttributeName : [self promptFont],
    NSForegroundColorAttributeName : [NSColor secondaryLabelColor]
  };
}

#pragma mark Layout

- (CGFloat)cellWidthFor:(NSString *)candidate {
  CGFloat k = [self scale];
  CGFloat phraseWidth =
      [candidate sizeWithAttributes:[self phraseAttributesForText:candidate
                                                    highlighted:NO]].width;
  return ceil((kPhraseX + kPhraseTrailing) * k + phraseWidth);
}
- (void)addCell:(NSRect)rect index:(NSUInteger)index {
  [_cellRects addObject:[NSValue valueWithRect:rect]];
  [_cellIndexes addObject:@(index)];
}
// Flows every candidate onto the grid: each takes as many whole columns as its
// text needs and wraps to the next row when the row has no room left.
- (void)layoutGrid {
  [_gridRows removeAllObjects];
  [_gridColumns removeAllObjects];
  [_gridSpans removeAllObjects];
  [_gridRowStarts removeAllObjects];

  // Vertical: each column holds one page, so it lines up with the single
  // column it opened from. The "rows" below are then these columns.
  if (_vertical) {
    // Every column is as wide as the widest candidate, so they stay even.
    NSUInteger capacity = MAX([_keys count], (NSUInteger)1);
    _gridColumnPitch = 0;
    for (NSUInteger i = 0; i < [_candidates count]; i++) {
      _gridColumnPitch = MAX(_gridColumnPitch,
                             [self cellWidthFor:[_candidates objectAtIndex:i]]);
      if (i % capacity == 0) [_gridRowStarts addObject:@(i)];
      [_gridRows addObject:@(i / capacity)];
      [_gridColumns addObject:@(i % capacity)];
      [_gridSpans addObject:@1];
    }
    return;
  }

  CGFloat k = [self scale];
  CGFloat cellGap = kCellGap * k;
  CGFloat inset = kInset * k;
  CGFloat column = MAX(kGridColumn * k,
                       (_gridWidth - inset * 2 + cellGap) / kGridColumns);
  _gridColumnPitch = column;
  NSUInteger row = 0, used = 0;
  for (NSUInteger i = 0; i < [_candidates count]; i++) {
    CGFloat width = [self cellWidthFor:[_candidates objectAtIndex:i]];
    NSUInteger span = (NSUInteger)ceil((width + cellGap) / column);
    span = MIN(MAX(span, (NSUInteger)1), kGridColumns);
    if (used + span > kGridColumns) {
      row++;
      used = 0;
    }
    if (used == 0) [_gridRowStarts addObject:@(i)];
    [_gridRows addObject:@(row)];
    [_gridColumns addObject:@(used)];
    [_gridSpans addObject:@(span)];
    used += span;
  }
}
- (NSInteger)gridRowOfIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)[_gridRows count]) return -1;
  return [[_gridRows objectAtIndex:index] integerValue];
}
- (NSInteger)gridRowStart:(NSInteger)row {
  return [[_gridRowStarts objectAtIndex:row] integerValue];
}
- (NSInteger)gridRowEnd:(NSInteger)row {
  return row + 1 < (NSInteger)[_gridRowStarts count]
             ? [self gridRowStart:row + 1]
             : (NSInteger)[_candidates count];
}
- (NSDictionary *)tabHintAttributes {
  return [self numberAttributesHighlighted:NO];
}
- (NSSize)tabHintSize {
  CGFloat k = [self scale];
  NSSize size = [@"tab" sizeWithAttributes:[self tabHintAttributes]];
  return NSMakeSize(ceil(size.width + kTabHintPadding * 2 * k), ceil(size.height));
}
- (CGFloat)accessoryWidthFor:(NSString *)accessory {
  CGFloat k = [self scale];
  CGFloat textWidth =
      [accessory sizeWithAttributes:[self phraseAttributesHighlighted:NO]].width;
  return ceil(kAccessoryPadding * 2 * k + textWidth);
}
// Lays out the "tab" hint and the accessories from origin, along a row or,
// with the hint on a line of its own, down a column. Returns the far corner.
- (NSPoint)layoutAccessoriesFrom:(NSPoint)origin column:(BOOL)column {
  CGFloat k = [self scale];
  CGFloat cellHeight = kCellHeight * k;
  CGFloat gap = kAccessoryGap * k;
  NSSize hint = [self tabHintSize];
  _tabHintRect = NSMakeRect(origin.x, origin.y + (cellHeight - hint.height) / 2,
                            hint.width, hint.height);
  CGFloat x = column ? origin.x : NSMaxX(_tabHintRect) + gap;
  CGFloat y = column ? origin.y + cellHeight : origin.y;
  CGFloat farX = NSMaxX(_tabHintRect);
  for (NSString *accessory in _accessories) {
    NSRect rect = NSMakeRect(x, y, [self accessoryWidthFor:accessory], cellHeight);
    [_accessoryRects addObject:[NSValue valueWithRect:rect]];
    farX = MAX(farX, NSMaxX(rect));
    if (column)
      y += cellHeight + gap;
    else
      x = NSMaxX(rect) + gap;
  }
  return NSMakePoint(farX, column ? y - gap : y + cellHeight);
}
// The vertical panels keep them at the foot, past a hairline across.
- (void)layoutAccessoriesBelow {
  CGFloat k = [self scale];
  CGFloat inset = kInset * k;
  CGFloat top = _contentSize.height;
  _accessorySeparatorRect = NSMakeRect(inset, top, 0, 1);
  NSPoint end = [self layoutAccessoriesFrom:NSMakePoint(inset + kAccessoryPadding * k,
                                                        top + 1 + inset)
                                     column:NO];
  _contentSize.width = MAX(_contentSize.width, end.x + inset);
  _contentSize.height = end.y + inset;
  _accessorySeparatorRect.size.width = _contentSize.width - inset * 2;
}
- (void)layoutCells {
  [_cellRects removeAllObjects];
  [_cellIndexes removeAllObjects];
  [_accessoryRects removeAllObjects];
  _accessorySeparatorRect = NSZeroRect;
  _tabHintRect = NSZeroRect;
  _accessoryRowExtent = 0;
  BOOL hasAccessories = [_accessories count] > 0;

  CGFloat k = [self scale];
  CGFloat inset = kInset * k;
  CGFloat cellHeight = kCellHeight * k;
  CGFloat cellGap = kCellGap * k;
  CGFloat rowPitch = cellHeight + inset * 2;

  _rowsTop = 0;
  _promptRect = NSZeroRect;
  if ([_prompt length]) {
    NSSize promptSize = [_prompt sizeWithAttributes:[self promptAttributes]];
    _promptRect = NSMakeRect(kPanelRadius * k, inset, ceil(promptSize.width),
                             ceil(promptSize.height));
    _rowsTop = NSHeight(_promptRect) + inset;
  }
  NSPoint origin = NSMakePoint(inset, _rowsTop + inset);
  NSUInteger count = [_candidates count];

  if (_expanded && _vertical) {
    // Opening leaves the current column where it was, as the first one;
    // after that, scroll just enough to keep the highlighted column on screen.
    NSInteger lineCount = [_gridRowStarts count];
    NSInteger highlightedLine = [self gridRowOfIndex:_highlightedIndex];
    if (_firstVisibleRow < 0) _firstVisibleRow = MAX(highlightedLine, 0);
    if (highlightedLine >= 0) {
      if (highlightedLine < _firstVisibleRow) _firstVisibleRow = highlightedLine;
      if (highlightedLine >= _firstVisibleRow + kGridVisibleRows)
        _firstVisibleRow = highlightedLine - kGridVisibleRows + 1;
    }
    _firstVisibleRow = MAX(0, MIN(_firstVisibleRow, lineCount - 1));
    _visibleRowCount = MIN(kGridVisibleRows, lineCount - _firstVisibleRow);

    CGFloat x = origin.x;
    CGFloat width = _gridColumnPitch;
    for (NSInteger line = _firstVisibleRow;
         line < _firstVisibleRow + _visibleRowCount; line++) {
      if (line > _firstVisibleRow) x += cellGap;
      NSInteger end = [self gridRowEnd:line];
      for (NSInteger i = [self gridRowStart:line]; i < end; i++) {
        NSUInteger slot = [[_gridColumns objectAtIndex:i] unsignedIntegerValue];
        [self addCell:NSMakeRect(x, origin.y + slot * cellHeight, width, cellHeight)
                index:i];
      }
      x += width;
    }
    // Left on the first column collapses the grid, so it needs no chevron.
    _separatorRect = NSZeroRect;
    _chevronRect = NSZeroRect;
    _contentSize = NSMakeSize(x + inset,
                              origin.y + [_keys count] * cellHeight + inset);
    if (hasAccessories) [self layoutAccessoriesBelow];
  } else if (_expanded) {
    // Scroll just enough to keep the highlighted row on screen.
    NSInteger rowCount = [_gridRowStarts count];
    _visibleRowCount = MIN(rowCount, kGridVisibleRows);
    NSInteger highlightedRow = [self gridRowOfIndex:_highlightedIndex];
    if (highlightedRow >= 0) {
      if (highlightedRow < _firstVisibleRow) _firstVisibleRow = highlightedRow;
      if (highlightedRow >= _firstVisibleRow + _visibleRowCount)
        _firstVisibleRow = highlightedRow - _visibleRowCount + 1;
    }
    _firstVisibleRow =
        MAX(0, MIN(_firstVisibleRow, rowCount - _visibleRowCount));

    CGFloat column = _gridColumnPitch;
    for (NSUInteger i = 0; i < count; i++) {
      NSInteger row = [self gridRowOfIndex:i] - _firstVisibleRow;
      if (row < 0 || row >= _visibleRowCount) continue;
      NSUInteger firstColumn = [[_gridColumns objectAtIndex:i] unsignedIntegerValue];
      NSUInteger span = [[_gridSpans objectAtIndex:i] unsignedIntegerValue];
      [self addCell:NSMakeRect(origin.x + firstColumn * column,
                               origin.y + row * rowPitch,
                               span * column - cellGap, cellHeight)
              index:i];
    }
    // Up on the first row collapses the grid, so it needs no chevron.
    _separatorRect = NSZeroRect;
    _chevronRect = NSZeroRect;
    _contentSize = NSMakeSize(origin.x + kGridColumns * column - cellGap + inset,
                              _rowsTop + MAX(_visibleRowCount, 1) * rowPitch);
    // The grid's side, past a hairline down its height.
    if (hasAccessories) {
      CGFloat separatorX = _contentSize.width + kAccessorySeparatorGap * k;
      _accessorySeparatorRect =
          NSMakeRect(separatorX, _rowsTop + inset, 1,
                     _contentSize.height - _rowsTop - inset * 2);
      NSPoint end = [self
          layoutAccessoriesFrom:NSMakePoint(separatorX + 1 + kAccessorySeparatorGap * k,
                                            _rowsTop + inset)
                         column:YES];
      _contentSize.width = end.x + inset;
      _contentSize.height = MAX(_contentSize.height, end.y + inset);
    }
  } else if (_vertical) {
    CGFloat maxWidth = 0;
    for (NSString *candidate in _candidates)
      maxWidth = MAX(maxWidth, [self cellWidthFor:candidate]);
    for (NSUInteger i = 0; i < count; i++)
      [self addCell:NSMakeRect(origin.x, origin.y + i * cellHeight, maxWidth,
                               cellHeight)
              index:i];

    // No chevron: Right opens the grid, and Space turns the page.
    _separatorRect = NSZeroRect;
    _chevronRect = NSZeroRect;
    _contentSize = NSMakeSize(maxWidth + inset * 2,
                              origin.y + count * cellHeight + inset);
    if (hasAccessories) [self layoutAccessoriesBelow];
  } else {
    CGFloat x = origin.x;
    for (NSUInteger i = 0; i < count; i++) {
      if (i) x += cellGap;
      CGFloat width = [self cellWidthFor:[_candidates objectAtIndex:i]];
      [self addCell:NSMakeRect(x, origin.y, width, cellHeight) index:i];
      x += width;
    }
    // At the row's end, past a hairline like the chevron's.
    if (hasAccessories) {
      CGFloat start = x;
      CGFloat separatorLength = kSeparatorLength * k;
      CGFloat separatorX = x + kAccessorySeparatorGap * k;
      _accessorySeparatorRect =
          NSMakeRect(separatorX, origin.y + (cellHeight - separatorLength) / 2, 1,
                     separatorLength);
      x = [self layoutAccessoriesFrom:NSMakePoint(separatorX + 1 + kAccessorySeparatorGap * k,
                                                  origin.y)
                               column:NO].x;
      _accessoryRowExtent = x - start;
    }
    if (_showsChevron) {
      CGFloat separatorX = x + kSeparatorGap * k;
      [self layoutChevronAfter:separatorX];
      _contentSize = NSMakeSize(separatorX + kChevronArea * k,
                                origin.y + cellHeight + inset);
    } else {
      _separatorRect = NSZeroRect;
      _chevronRect = NSZeroRect;
      _contentSize = NSMakeSize(x + inset, origin.y + cellHeight + inset);
    }
  }
  _contentSize.width = MAX(_contentSize.width,
                           NSMaxX(_promptRect) + kPanelRadius * k);
  _contentSize.width = ceil(_contentSize.width);
  _contentSize.height = ceil(_contentSize.height);
}
// The chevron sits at the end of the first row, past a short hairline.
- (void)layoutChevronAfter:(CGFloat)separatorX {
  CGFloat k = [self scale];
  CGFloat inset = kInset * k;
  CGFloat cellHeight = kCellHeight * k;
  CGFloat separatorLength = kSeparatorLength * k;
  CGFloat rowY = _rowsTop + inset;
  _separatorRect = NSMakeRect(separatorX,
                              rowY + (cellHeight - separatorLength) / 2, 1,
                              separatorLength);
  _chevronRect = NSMakeRect(separatorX + 1, rowY,
                            kChevronArea * k - 1 - inset, cellHeight);
}

#pragma mark Content

- (void)setCandidates:(NSArray *)candidates
                 keys:(NSArray *)keys
     highlightedIndex:(NSInteger)highlightedIndex
               prompt:(NSString *)prompt {
  _expanded = NO;
  [self applyCandidates:candidates keys:keys highlightedIndex:highlightedIndex
                 prompt:prompt];
}
- (void)setGridCandidates:(NSArray *)candidates
                     keys:(NSArray *)keys
         highlightedIndex:(NSInteger)highlightedIndex
                    width:(CGFloat)width
                   prompt:(NSString *)prompt {
  if (!_expanded || width != _gridWidth) {
    // The vertical grid starts on the column it opened from.
    _firstVisibleRow = _vertical ? -1 : 0;
    [_gridRows removeAllObjects];  // forces a fresh layout at the new width
  }
  _gridWidth = width;
  _expanded = YES;
  [self applyCandidates:candidates keys:keys highlightedIndex:highlightedIndex
                 prompt:prompt];
}
- (void)applyCandidates:(NSArray *)candidates
                   keys:(NSArray *)keys
       highlightedIndex:(NSInteger)highlightedIndex
                 prompt:(NSString *)prompt {
  // The grid depends only on the list, which stays put while the window is
  // open, so it is measured once rather than on every key.
  BOOL relayoutGrid = _expanded && !([candidates isEqualToArray:_candidates] &&
                                     [_gridRows count] == [candidates count]);
  [_candidates release];
  _candidates = [candidates copy];
  [_keys release];
  _keys = [keys copy];
  [_prompt release];
  _prompt = [(prompt ? prompt : @"") copy];
  _highlightedIndex = highlightedIndex;
  if (relayoutGrid) [self layoutGrid];
  [self layoutCells];
  [self updateCornerRadius];
  [self setNeedsDisplay:YES];
}
- (NSSize)contentSize {
  return _contentSize;
}
- (void)setAccessories:(NSArray *)accessories highlightedIndex:(NSInteger)index {
  [_accessories release];
  _accessories = [(accessories ? accessories : @[]) copy];
  _accessoryHighlight = index < (NSInteger)[_accessories count] ? index : -1;
}
- (CGFloat)accessoryRowExtent {
  return _accessoryRowExtent;
}
- (NSInteger)clickedAccessoryIndex {
  return _clickedAccessory;
}

#pragma mark Grid navigation

// Keeps to the column the current candidate starts in, landing on whichever
// candidate covers that column in the target row, or that row's last one.
- (NSInteger)gridIndexMovingRows:(NSInteger)delta fromIndex:(NSInteger)index {
  NSInteger row = [self gridRowOfIndex:index];
  if (row < 0) return -1;
  NSInteger target = row + delta;
  if (target < 0 || target >= (NSInteger)[_gridRowStarts count]) return -1;

  NSUInteger column = [[_gridColumns objectAtIndex:index] unsignedIntegerValue];
  NSInteger end = [self gridRowEnd:target];
  for (NSInteger i = [self gridRowStart:target]; i < end; i++) {
    NSUInteger first = [[_gridColumns objectAtIndex:i] unsignedIntegerValue];
    NSUInteger span = [[_gridSpans objectAtIndex:i] unsignedIntegerValue];
    if (column >= first && column < first + span) return i;
  }
  return end - 1;
}
- (NSInteger)gridIndexForKeyAtPosition:(NSInteger)position
                             fromIndex:(NSInteger)index {
  NSInteger row = [self gridRowOfIndex:index];
  if (row < 0 || position < 0) return -1;
  NSInteger target = [self gridRowStart:row] + position;
  return target < [self gridRowEnd:row] ? target : -1;
}
- (NSInteger)gridPositionInRowOfIndex:(NSInteger)index {
  NSInteger row = [self gridRowOfIndex:index];
  if (row < 0) return -1;
  return index - [self gridRowStart:row];
}

#pragma mark Settings

- (void)setCandidateTextHeight:(CGFloat)inTextHeight {
  _fontSize = inTextHeight;
}
- (void)setClickable:(BOOL)flag {
  _clickable = flag;
}
- (void)setShowsChevron:(BOOL)flag {
  _showsChevron = flag;
}
- (NSInteger)clickedIndex {
  return _clickedIndex;
}
- (void)setTarget:(id)target {
  _target = target;
}
- (void)setAction:(SEL)action {
  _action = action;
}
- (void)setChevronAction:(SEL)action {
  _chevronAction = action;
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirtyRect {
  CGFloat k = [self scale];
  // Selection keys go on the row holding the highlight (the only row in
  // single-row mode), numbered from its first candidate.
  NSInteger keyedRowStart = 0;
  NSInteger keyedRowEnd = [_candidates count];
  if (_expanded) {
    NSInteger row = [self gridRowOfIndex:_highlightedIndex];
    if (row < 0) row = _firstVisibleRow;
    if (row < (NSInteger)[_gridRowStarts count]) {
      keyedRowStart = [self gridRowStart:row];
      keyedRowEnd = [self gridRowEnd:row];
    }
  }

  NSUInteger count = [_cellRects count];
  for (NSUInteger c = 0; c < count; c++) {
    NSRect rect = [[_cellRects objectAtIndex:c] rectValue];
    NSInteger index = [[_cellIndexes objectAtIndex:c] integerValue];
    BOOL highlighted = (index == _highlightedIndex);
    if (highlighted) {
      CGFloat radius = NSHeight(rect) / 2;
      [[self highlightColor] setFill];
      [[NSBezierPath bezierPathWithRoundedRect:rect
                                       xRadius:radius
                                       yRadius:radius] fill];
    }

    NSInteger keyPosition = index - keyedRowStart;
    if (index >= keyedRowStart && index < keyedRowEnd &&
        keyPosition < (NSInteger)[_keys count]) {
      NSString *key = [_keys objectAtIndex:keyPosition];
      NSDictionary *numberAttributes = [self numberAttributesHighlighted:highlighted];
      CGFloat numberHeight = [key sizeWithAttributes:numberAttributes].height;
      [key drawAtPoint:NSMakePoint(NSMinX(rect) + kNumberX * k,
                                   NSMinY(rect) + (NSHeight(rect) - numberHeight) / 2 +
                                       kNumberDrop * k)
          withAttributes:numberAttributes];
    }

    NSString *candidate = [_candidates objectAtIndex:index];
    NSDictionary *phraseAttributes = [self phraseAttributesForText:candidate
                                                       highlighted:highlighted];
    CGFloat phraseHeight = [candidate sizeWithAttributes:phraseAttributes].height;
    [candidate drawAtPoint:NSMakePoint(NSMinX(rect) + kPhraseX * k,
                                       NSMinY(rect) + (NSHeight(rect) - phraseHeight) / 2)
            withAttributes:phraseAttributes];
  }

  // Blended, not copied: the separator color is translucent.
  [[NSColor separatorColor] setFill];
  NSRectFillUsingOperation(_separatorRect, NSCompositingOperationSourceOver);
  if (_expanded && !_vertical) {
    CGFloat inset = kInset * k;
    CGFloat rowPitch = (kCellHeight + kInset * 2) * k;
    for (NSInteger r = 1; r < _visibleRowCount; r++) {
      NSRect line = NSMakeRect(inset, _rowsTop + r * rowPitch,
                               NSWidth([self bounds]) - inset * 2, 1);
      NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
    }
  }

  // Accessories: an outlined "tab" hint, then capsules a shade off the panel.
  if ([_accessoryRects count]) {
    NSRectFillUsingOperation(_accessorySeparatorRect, NSCompositingOperationSourceOver);
    NSBezierPath *outline =
        [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(_tabHintRect, 0.5, 0.5)
                                        xRadius:3 * k
                                        yRadius:3 * k];
    [outline setLineWidth:1];
    [[NSColor tertiaryLabelColor] setStroke];
    [outline stroke];
    NSDictionary *hintAttributes = [self tabHintAttributes];
    NSSize hintSize = [@"tab" sizeWithAttributes:hintAttributes];
    [@"tab" drawAtPoint:NSMakePoint(NSMidX(_tabHintRect) - hintSize.width / 2,
                                    NSMidY(_tabHintRect) - hintSize.height / 2)
         withAttributes:hintAttributes];

    for (NSUInteger a = 0; a < [_accessoryRects count]; a++) {
      NSRect rect = [[_accessoryRects objectAtIndex:a] rectValue];
      BOOL highlighted = (NSInteger)a == _accessoryHighlight;
      CGFloat radius = NSHeight(rect) / 2;
      [(highlighted ? [self highlightColor] : [NSColor quaternaryLabelColor]) setFill];
      [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
      NSString *accessory = [_accessories objectAtIndex:a];
      NSDictionary *attributes = [self phraseAttributesHighlighted:highlighted];
      NSSize size = [accessory sizeWithAttributes:attributes];
      [accessory drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2,
                                         NSMidY(rect) - size.height / 2)
              withAttributes:attributes];
    }
  }

  // A chevron like the built-in panel's expand button.
  if (!NSIsEmptyRect(_chevronRect)) {
    NSPoint center = NSMakePoint(NSMidX(_chevronRect), NSMidY(_chevronRect));
    CGFloat halfWidth = kChevronWidth * k / 2;
    CGFloat halfHeight = kChevronHeight * k / 2;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    [chevron moveToPoint:NSMakePoint(center.x - halfWidth, center.y - halfHeight)];
    [chevron lineToPoint:NSMakePoint(center.x, center.y + halfHeight)];
    [chevron lineToPoint:NSMakePoint(center.x + halfWidth, center.y - halfHeight)];
    [chevron setLineWidth:1.5 * k];
    [chevron setLineCapStyle:NSLineCapStyleRound];
    [chevron setLineJoinStyle:NSLineJoinStyleRound];
    [[NSColor secondaryLabelColor] setStroke];
    [chevron stroke];
  }

  if ([_prompt length]) {
    [_prompt drawAtPoint:_promptRect.origin withAttributes:[self promptAttributes]];
  }
}

#pragma mark Mouse

- (NSInteger)candidateIndexForEvent:(NSEvent *)theEvent {
  NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
  NSUInteger count = [_cellRects count];
  for (NSUInteger c = 0; c < count; c++) {
    if (NSPointInRect(point, [[_cellRects objectAtIndex:c] rectValue]))
      return [[_cellIndexes objectAtIndex:c] integerValue];
  }
  return -1;
}
- (NSInteger)accessoryIndexForEvent:(NSEvent *)theEvent {
  NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
  for (NSUInteger a = 0; a < [_accessoryRects count]; a++) {
    if (NSPointInRect(point, [[_accessoryRects objectAtIndex:a] rectValue]))
      return (NSInteger)a;
  }
  return -1;
}
- (BOOL)isChevronEvent:(NSEvent *)theEvent {
  NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
  return NSPointInRect(point, _chevronRect);
}
- (void)mouseDown:(NSEvent *)theEvent {
  if (!_clickable) return;
  NSInteger accessory = [self accessoryIndexForEvent:theEvent];
  if (accessory >= 0) {
    if (accessory == _accessoryHighlight) return;
    _accessoryHighlight = accessory;
    _highlightedIndex = -1;
    [self setNeedsDisplay:YES];
    return;
  }
  NSInteger index = [self candidateIndexForEvent:theEvent];
  if (index < 0 || index == _highlightedIndex) return;
  _highlightedIndex = index;
  [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)theEvent {
  [self mouseDown:theEvent];
}
- (void)mouseUp:(NSEvent *)theEvent {
  _clickedIndex = -1;
  _clickedAccessory = -1;
  if (!_clickable) return;
  if ([self isChevronEvent:theEvent]) {
    if (_target && _chevronAction && [_target respondsToSelector:_chevronAction])
      [_target performSelector:_chevronAction withObject:self];
    return;
  }
  NSInteger accessory = [self accessoryIndexForEvent:theEvent];
  if (accessory >= 0) {
    _clickedAccessory = accessory;
    if (_target && _action && [_target respondsToSelector:_action])
      [_target performSelector:_action withObject:self];
    return;
  }
  NSInteger index = [self candidateIndexForEvent:theEvent];
  if (index < 0) return;
  _clickedIndex = index;
  if (_target && _action && [_target respondsToSelector:_action])
    [_target performSelector:_action withObject:self];
}

@end
