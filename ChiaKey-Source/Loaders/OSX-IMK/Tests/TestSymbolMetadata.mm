#import "CVButtonViewController.h"
#import "OpenVanillaController.h"
#include <assert.h>
#import "CVFloatingPanelWindow.h"
#include <PlainVanilla/PVPropertyList.h>
#include <sstream>

using namespace OpenVanilla;

// Minimal nib owner: load the real window and its production panel class.
@interface SymbolWindowTestOwner : NSWindowController {
  IBOutlet NSPopUpButton *_popUpButton;
  IBOutlet NSView *_symbolContentView;
}
- (IBAction)toggleSymbol:(id)sender;
@end
@implementation SymbolWindowTestOwner
- (IBAction)toggleSymbol:(id)sender {}
@end

// Only replace the host insertion endpoint; compile the real button controller.
static NSString *sentText;
@implementation OpenVanillaController
+ (void)sendComposedStringToCurrentlyActiveContext:(NSString *)text {
  sentText = text;
}
@end

// Mirrors OpenVanillaLoader's mergeCannedMessagesData: the DB plist is parsed
// into PVPlistValue and re-dumped before AppKit sees it.
static NSDictionary *RoundTripThroughLoader(NSDictionary *category) {
  NSData *xml = [NSPropertyListSerialization
      dataWithPropertyList:@{@"CannedMessages" : @[category]}
                    format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
  assert(xml);
  NSString *text = [[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] autorelease];
  PVPlistValue *parsed = PVPropertyList::ParsePlistFromString([text UTF8String]);
  assert(parsed);
  PVPlistValue *msgs = parsed->valueForKey("CannedMessages");
  PVPlistValue msgArray(PVPlistValue::Array);
  for (size_t i = 0; i < msgs->arraySize(); i++)
    msgArray.addArrayElement(msgs->arrayElementAtIndex(i));
  PVPlistValue newData(PVPlistValue::Dictionary);
  newData.setKeyValue("CannedMessages", &msgArray);
  delete parsed;
  std::stringstream sst;
  sst << newData;
  const std::string &s = sst.str();
  id plist = [NSPropertyListSerialization
      propertyListWithData:[NSData dataWithBytes:s.c_str() length:s.length()]
                   options:NSPropertyListMutableContainersAndLeaves
                    format:NULL error:nil];
  assert(plist);
  return plist[@"CannedMessages"][0];
}

static void CheckCategory(NSDictionary *category, BOOL hasMetadata) {
  CVButtonViewController *controller = [[CVButtonViewController alloc] initWithDictionary:category];
  NSArray *buttons = [[controller view] subviews];
  NSArray *symbols = category[@"Buttons"];
  assert([buttons count] == [symbols count]);
  for (NSUInteger i = 0; i < [buttons count]; i++) {
    NSButton *button = buttons[i];
    [controller sendString:button];
    assert([sentText isEqualToString:symbols[i]]);
    assert([[button toolTip] length] > 0);
#if CHIAKEY_DEV_LOGGING
    [button updateTrackingAreas];
    BOOL hasAlwaysActiveProbe = NO;
    for (NSTrackingArea *area in [button trackingAreas]) {
      if (([area options] & NSTrackingActiveAlways) &&
          ([area options] & NSTrackingMouseEnteredAndExited)) hasAlwaysActiveProbe = YES;
    }
    assert(hasAlwaysActiveProbe);
#endif
    assert(NSContainsRect([[controller view] bounds], [button frame]));
    for (NSUInteger j = 0; j < i; j++)
      assert(!NSIntersectsRect([button frame], [buttons[j] frame]));
  }
  NSButton *space = buttons[0];
  assert([[space toolTip] containsString:@"U+3000"]);
  if (hasMetadata) {
    assert([[space title] isEqualToString:@"全形空白"]);
    assert([[space toolTip] containsString:@"詞庫提供的說明"]);
    assert([[space accessibilityLabel] isEqualToString:@"全形空白"]);
    assert([space frame].size.width >= [[space cell] cellSize].width);
  } else {
    assert([[space title] isEqualToString:@"　"]);
    assert([[space toolTip] containsString:@"IDEOGRAPHIC SPACE"]);
  }
  assert([[(NSButton *)buttons[1] toolTip] containsString:@"U+1F600"]);
  assert([[(NSButton *)buttons[2] toolTip] containsString:@"U+0061 U+0301"]);
  assert([[(NSButton *)buttons[2] accessibilityLabel]
      isEqualToString:@"a, COMBINING ACUTE ACCENT"]);
  [controller release];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    assert(argc == 2);
    [NSApplication sharedApplication];
    NSData *nibData = [NSData dataWithContentsOfFile:
        [NSString stringWithUTF8String:argv[1]]];
    assert(nibData);
    NSNib *nib = [[NSNib alloc] initWithNibData:nibData bundle:nil];
    SymbolWindowTestOwner *owner = [[SymbolWindowTestOwner alloc] init];
    NSArray *objects = nil;
    BOOL loaded = [nib instantiateWithOwner:owner topLevelObjects:&objects];
    assert(loaded);
    NSWindow *window = [owner window];
    assert([window isKindOfClass:[CVFloatingPanelWindow class]]);
    assert([window allowsToolTipsWhenApplicationIsInactive]);
    assert(![window canBecomeKeyWindow]);
    assert(![window canBecomeMainWindow]);
    assert([window styleMask] & NSWindowStyleMaskNonactivatingPanel);
    [owner release];
    [nib release];
    NSArray *symbols = @[@"　", @"😀", @"á", @"·", @"．", @"‧", @"!", @"?", @"@", @"#", @"$", @"&", @"<"];
    NSDictionary *metadata = @{
      @"　":@{@"Name":@"全形空白", @"DisplayLabel":@"全形空白", @"Description":@"詞庫提供的說明"},
      @"&":@{@"Name":@"A & B"}, @"<":@{@"Name":@"<小於>"},
    };
    NSDictionary *modern = @{@"Buttons":symbols, @"SymbolMetadata":metadata};
    CheckCategory(modern, YES);
    // XML-special keys must survive the loader's re-dump, or every category is lost.
    NSDictionary *loadedModern = RoundTripThroughLoader(modern);
    assert([loadedModern isEqual:modern]);
    CheckCategory(loadedModern, YES);
    // New app + old DB; malformed optional metadata must also fall back.
    CheckCategory(@{@"Buttons":symbols}, NO);
    CheckCategory(@{@"Buttons":symbols, @"SymbolMetadata":@7}, NO);
    CheckCategory(@{@"Buttons":symbols, @"SymbolMetadata":@{@"　":@7}}, NO);
    CheckCategory(@{@"Buttons":symbols, @"SymbolMetadata":@{@"　":@{@"Name":@7, @"DisplayLabel":@NO, @"Description":@[]}}}, NO);
    puts("Symbol metadata, button layout, and inactive nonactivating window tooltips passed.");
  }
}
