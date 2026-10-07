// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

#import "CVFloatingTableView.h"
#import "CVHorizontalCandidateController.h"

@interface CVPageButton : NSButton
@end

// The same candidate window as the horizontal one, listing a page top to
// bottom instead. Right opens the same expanded grid.
@interface CVVerticalCandidateController : CVHorizontalCandidateController {
  // Only so VerticalCandidateWindow still loads; see awakeFromNib.
  IBOutlet id _scrollView;
  IBOutlet CVFloatingTableView *_tableView;
  IBOutlet NSTextField *_pageIndicatorTextField;
}

// Target of the nib's (no longer shown) table view.
- (IBAction)updateSelectedCandidate:(id)sender;
@end
