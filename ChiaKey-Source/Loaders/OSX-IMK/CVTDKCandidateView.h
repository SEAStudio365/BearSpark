// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

// Candidate list styled after the macOS built-in Zhuyin candidate window: a
// capsule glass panel, an accent-colored capsule highlight, small selection
// numbers and a trailing chevron. Expanded, it flows every candidate onto a
// six-column grid and shows five rows of it at a time, as the built-in window
// does. The vertical list instead expands into side-by-side columns of one
// page each, five at a time; the grid methods' "rows" are then those columns.
// Shared by the horizontal and the vertical candidate controllers.
@interface CVTDKCandidateView : NSView {
  NSArray *_candidates;
  NSArray *_keys;
  NSString *_prompt;

  // Grid placement of every candidate while expanded.
  NSMutableArray *_gridRows;      // row of each candidate
  NSMutableArray *_gridColumns;   // first grid column of each candidate
  NSMutableArray *_gridSpans;     // grid columns each candidate covers
  NSMutableArray *_gridRowStarts; // first candidate of each row
  NSInteger _firstVisibleRow;
  CGFloat _gridWidth;     // requested panel width; 0 for the natural width
  CGFloat _gridColumnPitch;  // vertical: the width of every column

  // What is on screen: one rect per drawn candidate, and its index.
  NSMutableArray *_cellRects;
  NSMutableArray *_cellIndexes;
  NSRect _chevronRect;
  NSRect _separatorRect;
  NSRect _promptRect;
  CGFloat _rowsTop;
  NSInteger _visibleRowCount;
  NSSize _contentSize;

  NSInteger _highlightedIndex;
  NSInteger _clickedIndex;
  BOOL _vertical;
  BOOL _expanded;
  BOOL _clickable;
  BOOL _showsChevron;
  CGFloat _fontSize;

  NSView *_containerView;
  NSView *_backgroundView;

  id _target;
  SEL _action;
  SEL _chevronAction;
}

- (id)initWithVertical:(BOOL)vertical;

// Replaces the window's content with a rounded glass container hosting this
// view.
- (void)installInWindow:(NSWindow *)window;

// Single row; highlightedIndex and clickedIndex count within it.
- (void)setCandidates:(NSArray *)candidates
                 keys:(NSArray *)keys
     highlightedIndex:(NSInteger)highlightedIndex
               prompt:(NSString *)prompt;
// Expanded grid of the whole candidate list; highlightedIndex and
// clickedIndex count within it. The row holding the highlight shows the keys.
// The six columns widen to fill width when it is wider than they need, so the
// grid can match the single row it opened from.
- (void)setGridCandidates:(NSArray *)candidates
                     keys:(NSArray *)keys
         highlightedIndex:(NSInteger)highlightedIndex
                    width:(CGFloat)width
                   prompt:(NSString *)prompt;
- (NSSize)contentSize;

// Grid navigation, valid after setGridCandidates:. Each returns -1 when there
// is no such candidate.
- (NSInteger)gridIndexMovingRows:(NSInteger)delta fromIndex:(NSInteger)index;
- (NSInteger)gridIndexForKeyAtPosition:(NSInteger)position
                             fromIndex:(NSInteger)index;
- (NSInteger)gridPositionInRowOfIndex:(NSInteger)index;

- (void)setCandidateTextHeight:(CGFloat)inTextHeight;
- (void)setClickable:(BOOL)flag;
// Whether the single row ends in the chevron; off when there is nothing more
// to show. Applies from the next setCandidates:. A vertical list never shows
// one.
- (void)setShowsChevron:(BOOL)flag;
- (NSInteger)clickedIndex;
- (void)setTarget:(id)target;
// Sent when a candidate is clicked; read clickedIndex for which one.
- (void)setAction:(SEL)action;
// Sent when the chevron is clicked.
- (void)setChevronAction:(SEL)action;
@end
