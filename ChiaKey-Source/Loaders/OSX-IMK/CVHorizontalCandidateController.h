// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>
#import <PlainVanilla/PlainVanilla.h>

#import "CVFloatingBackground.h"
#import "CVHorizontalCandidateControl.h"
#import "CVSendKey.h"
#import "CVTDKCandidateView.h"
#import "CVTextDecoration.h"

using namespace OpenVanilla;

// What a key did to the expanded grid; see handleGridKey:panel:.
typedef enum {
  CVGridKeyIgnored,   // not a grid key; handle it as usual
  CVGridKeyMoved,     // moved the highlight
  CVGridKeyRejected,  // nowhere to move; beep
  CVGridKeyChoose     // made a candidate current; choose it
} CVGridKeyResult;

// The associated-phrase filter shows its list without taking control of the
// panel and picks with Shift plus a number, these being what those type.
extern const char CVAssociationSelectionKeys[];

@interface CVHorizontalCandidateController : NSWindowController {
  IBOutlet CVHorizontalCandidateControl *_candidateControl;
  IBOutlet CVFloatingBackground *_background;
  IBOutlet NSButton *_previousButton;
  IBOutlet NSButton *_nextButton;
  IBOutlet NSTextField *_pageTextField;
  IBOutlet NSTextField *_promptTextField;
  float _width;
  float _fontHeight;

  NSColor *_backgroundColor;
  NSColor *_foregroundColor;
  NSColor *_highlightTextColor;
  PVOneDimensionalCandidatePanel *_panel;
  CVTDKCandidateView *_candidateView;
  BOOL _expanded;
  size_t _collapsedCandidatesPerPage;
  NSArray *_gridKeys;
  CGFloat _gridWidth;  // the single row's width, which the grid keeps
  // Duration for animating the next frame change; 0 for none.
  NSTimeInterval _pendingFrameAnimation;

  BOOL _allowClick;
  BOOL _sending;
}

// Subclasses showing a different nib or a vertical list override these.
- (NSString *)nibName;
- (BOOL)isVertical;

- (void)setFontHeight:(float)newHeight;

- (void)updateContent:(PVOneDimensionalCandidatePanel *)panel
              atPoint:(NSPoint)position;
- (void)hide;

- (IBAction)sendKey:(id)sender;
- (IBAction)gotoNextPage:(id)sender;
- (IBAction)gotoPreviousPage:(id)sender;

- (void)setCandidateTextHeight:(float)inTextHeight;

// The expanded grid. While it is open the panel pages one candidate at a
// time, so its current page is the grid position; it closes again with the
// candidate window.
- (BOOL)isExpanded;
// Only when the candidates run past the single row (or column).
- (BOOL)canExpandPanel:(PVOneDimensionalCandidatePanel *)panel;
- (void)expandPanel:(PVOneDimensionalCandidatePanel *)panel;
- (void)collapsePanel:(PVOneDimensionalCandidatePanel *)panel;
- (CVGridKeyResult)handleGridKey:(const OVKey *)key
                           panel:(PVOneDimensionalCandidatePanel *)panel;
- (IBAction)toggleExpanded:(id)sender;
@end
