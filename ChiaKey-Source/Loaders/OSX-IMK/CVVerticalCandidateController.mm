// [AUTO_HEADER]

#import "CVVerticalCandidateController.h"

#import "OpenVanillaController.h"

@implementation CVPageButton

- (BOOL)isFlipped {
  return NO;
}
- (void)drawRect:(NSRect)aRect {
  NSRect selfRect = [self frame];
  NSRect rect = NSMakeRect(0, 0, selfRect.size.width, selfRect.size.height);
  if ([self image]) {
    NSImage *i = nil;
    if ([[self cell] isHighlighted]) {
      if ([self alternateImage])
        i = [self alternateImage];
      else
        i = [self image];
    } else {
      i = [self image];
    }
    NSSize size = [i size];
    float x = (rect.size.width - size.width) / 2;
    float y = (rect.size.height - size.height) / 2;
    [i drawAtPoint:NSMakePoint(x, y)
          fromRect:NSZeroRect
         operation:NSCompositingOperationSourceOver
          fraction:1.0];
  }
}
@end

@implementation CVVerticalCandidateController

- (NSString *)nibName {
  return @"VerticalCandidateWindow";
}
- (BOOL)isVertical {
  return YES;
}
- (IBAction)updateSelectedCandidate:(id)sender {
}

@end
