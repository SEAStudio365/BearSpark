/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoSmartPhonetic.h"

#import "TakaoHelper.h"
#import "TakaoKeyboardLayoutPopUpButton.h"

// The CNS 11643 fonts from the Ministry of Digital Affairs, free under the
// Open Government Data License or OFL 1.1 (https://data.gov.tw/dataset/5961).
static NSString *const TakaoCNSKaiFontURL =
    @"https://www.cns11643.gov.tw/opendata/Fonts_Kai.zip";
static NSString *const TakaoCNSSungFontURL =
    @"https://www.cns11643.gov.tw/opendata/Fonts_Sung.zip";

// Whether some installed font can show Extension B: the system's own fonts
// hold only scattered characters of it, so two far apart must both be found.
static BOOL TakaoHasRareCharacterFont(void) {
  UTF32Char probes[] = {0x20000, 0x21FE7};  // 𠀀, 𡿧
  for (size_t i = 0; i < sizeof(probes) / sizeof(probes[0]); i++) {
    NSCharacterSet *set =
        [NSCharacterSet characterSetWithRange:NSMakeRange(probes[i], 1)];
    NSFontDescriptor *wanted = [NSFontDescriptor
        fontDescriptorWithFontAttributes:@{NSFontCharacterSetAttribute : set}];
    BOOL found = NO;
    for (NSFontDescriptor *each in [wanted
             matchingFontDescriptorsWithMandatoryKeys:
                 [NSSet setWithObject:NSFontCharacterSetAttribute]]) {
      NSString *name = [each objectForKey:NSFontNameAttribute];
      if ([name length] && ![name isEqualToString:@"LastResort"]) {
        found = YES;
        break;
      }
    }
    if (!found) return NO;
  }
  return YES;
}

@implementation TakaoSmartPhonetic

- (void)dealloc {
  [_preferenceFilePath release];
  [_phoneticDictionary release];
  [super dealloc];
}
- (void)setUI {
  if (!_phoneticDictionary) return;

  [_keyboardLayoutPopUpButton
      selectLayoutIdentifier:[_phoneticDictionary
                                 valueForKey:@"KeyboardLayout"]];

  NSString *clearComposingTextWithEsc =
      [_phoneticDictionary valueForKey:@"ClearComposingTextWithEsc"];
  if ([clearComposingTextWithEsc isEqualToString:@"true"])
    [_clearComposingTextWithEscCheckBox setIntValue:1];
  else
    [_clearComposingTextWithEscCheckBox setIntValue:0];

  NSString *showCandidateListWithSpace =
      [_phoneticDictionary valueForKey:@"ShowCandidateListWithSpace"];
  if ([showCandidateListWithSpace isEqualToString:@"true"])
    [_showCandidateListWithSpaceCheckBox setIntValue:1];
  else
    [_showCandidateListWithSpaceCheckBox setIntValue:0];

  NSString *shiftKeyAlwaysCommitUppercaseCharacters =
      [_phoneticDictionary
          valueForKey:@"ShiftKeyAlwaysCommitUppercaseCharacters"];
  if ([shiftKeyAlwaysCommitUppercaseCharacters isEqualToString:@"true"])
    [_shiftKeyAlwaysCommitUppercaseCharactersCheckBox setIntValue:1];
  else
    [_shiftKeyAlwaysCommitUppercaseCharactersCheckBox setIntValue:0];

  NSString *showEmojiCandidates =
      [_phoneticDictionary valueForKey:@"ShowEmojiCandidates"];
  [_showEmojiCandidatesCheckBox
      setIntValue:[showEmojiCandidates isEqualToString:@"true"] ? 1 : 0];

  NSString *showRareCharacters =
      [_phoneticDictionary valueForKey:@"ShowRareCharacters"];
  [_showRareCharactersCheckBox
      setIntValue:[showRareCharacters isEqualToString:@"true"] ? 1 : 0];

  NSString *mixedAlphanumericalEnabled =
      [_phoneticDictionary valueForKey:@"MixedAlphanumericalEnabled"];
  if ([mixedAlphanumericalEnabled isEqualToString:@"true"])
    [_mixedAlphanumericalCheckBox setIntValue:1];
  else
    [_mixedAlphanumericalCheckBox setIntValue:0];

  NSString *candidateCursorAtEndOfTargetBlock =
      [_phoneticDictionary valueForKey:@"CandidateCursorAtEndOfTargetBlock"];
  if ([candidateCursorAtEndOfTargetBlock isEqualToString:@"true"])
    [_candidateCursorAtEndOfTargetBlockMatrix selectCellAtRow:1 column:0];
  else
    [_candidateCursorAtEndOfTargetBlockMatrix selectCellAtRow:0 column:0];

  NSString *useCharactersSupportedByEncoding =
      [_phoneticDictionary valueForKey:@"UseCharactersSupportedByEncoding"];
  if ([useCharactersSupportedByEncoding isEqualToString:@""])
    [_useCharactersSupportedByEncodingCheckBox setIntValue:1];
  else
    [_useCharactersSupportedByEncodingCheckBox setIntValue:0];

  NSString *selectionKeys =
      [_phoneticDictionary valueForKey:@"CandidateSelectionKeys"];
  [_selectionKeyComboBox setStringValue:selectionKeys];

  NSString *composingTextBufferSize =
      [_phoneticDictionary valueForKey:@"ComposingTextBufferSize"];
  int bufferSize = [composingTextBufferSize intValue];
  [_composingTextBufferSizeSlider setIntValue:bufferSize];
}
- (void)awakeFromNib {
  _phoneticDictionary = [NSMutableDictionary new];
  [_phoneticDictionary setValue:@"Standard" forKey:@"KeyboardLayout"];
  [_phoneticDictionary setValue:@"" forKey:@"UseCharactersSupportedByEncoding"];
  [_phoneticDictionary setValue:@"false" forKey:@"ClearComposingTextWithEsc"];
  [_phoneticDictionary setValue:@"true" forKey:@"ShowCandidateListWithSpace"];
  [_phoneticDictionary setValue:@"false"
                         forKey:@"ShiftKeyAlwaysCommitUppercaseCharacters"];
  [_phoneticDictionary setValue:@"false"
                         forKey:@"CandidateCursorAtEndOfTargetBlock"];
  [_phoneticDictionary setValue:@"false" forKey:@"MixedAlphanumericalEnabled"];
  [_phoneticDictionary setValue:@"false" forKey:@"ShowEmojiCandidates"];
  [_phoneticDictionary setValue:@"false" forKey:@"ShowRareCharacters"];
  [_phoneticDictionary setValue:@"123456789" forKey:@"CandidateSelectionKeys"];
  [_phoneticDictionary setValue:@"20" forKey:@"ComposingTextBufferSize"];
  LFRetainAssign(_preferenceFilePath,
                 [TakaoHelper plistFilePath:PLIST_SMARTPHONETIC_FILENAME]);

  NSData *data = [NSData dataWithContentsOfFile:_preferenceFilePath
                                        options:0
                                          error:nil];
  if (data) {
    NSPropertyListFormat format;

    NSMutableDictionary *dictionary = [NSPropertyListSerialization
        propertyListWithData:data
                      options:0
                       format:&format
                        error:nil];
    if (dictionary) [_phoneticDictionary addEntriesFromDictionary:dictionary];
  }  // end data
  [self setUI];
  [self writePreference:self];
}
- (void)updateDictionary {
  if (!_phoneticDictionary) _phoneticDictionary = [NSMutableDictionary new];

  [_phoneticDictionary
      setValue:[_keyboardLayoutPopUpButton selectedLayoutIdentifier]
        forKey:@"KeyboardLayout"];

  if ([_clearComposingTextWithEscCheckBox intValue])
    [_phoneticDictionary setValue:@"true" forKey:@"ClearComposingTextWithEsc"];
  else
    [_phoneticDictionary setValue:@"false" forKey:@"ClearComposingTextWithEsc"];

  if ([_showCandidateListWithSpaceCheckBox intValue])
    [_phoneticDictionary setValue:@"true" forKey:@"ShowCandidateListWithSpace"];
  else
    [_phoneticDictionary setValue:@"false"
                           forKey:@"ShowCandidateListWithSpace"];

  if ([_shiftKeyAlwaysCommitUppercaseCharactersCheckBox intValue])
    [_phoneticDictionary
        setValue:@"true"
          forKey:@"ShiftKeyAlwaysCommitUppercaseCharacters"];
  else
    [_phoneticDictionary
        setValue:@"false"
          forKey:@"ShiftKeyAlwaysCommitUppercaseCharacters"];

  [_phoneticDictionary
      setValue:([_showEmojiCandidatesCheckBox intValue] ? @"true" : @"false")
        forKey:@"ShowEmojiCandidates"];
  [_phoneticDictionary
      setValue:([_showRareCharactersCheckBox intValue] ? @"true" : @"false")
        forKey:@"ShowRareCharacters"];

  if ([_mixedAlphanumericalCheckBox intValue])
    [_phoneticDictionary setValue:@"true" forKey:@"MixedAlphanumericalEnabled"];
  else
    [_phoneticDictionary setValue:@"false"
                           forKey:@"MixedAlphanumericalEnabled"];

  if ([[_candidateCursorAtEndOfTargetBlockMatrix selectedCell] tag])
    [_phoneticDictionary setValue:@"true"
                           forKey:@"CandidateCursorAtEndOfTargetBlock"];
  else
    [_phoneticDictionary setValue:@"false"
                           forKey:@"CandidateCursorAtEndOfTargetBlock"];

  if ([_useCharactersSupportedByEncodingCheckBox intValue])
    [_phoneticDictionary setValue:@""
                           forKey:@"UseCharactersSupportedByEncoding"];
  else
    [_phoneticDictionary setValue:@"BIG-5"
                           forKey:@"UseCharactersSupportedByEncoding"];

  NSString *selecitonKeys = [_selectionKeyComboBox stringValue];
  [_phoneticDictionary setValue:selecitonKeys forKey:@"CandidateSelectionKeys"];

  int bufferSize = [_composingTextBufferSizeSlider intValue];
  NSString *bufferSizeString = [NSString stringWithFormat:@"%d", bufferSize];
  [_phoneticDictionary setValue:bufferSizeString
                         forKey:@"ComposingTextBufferSize"];
}
- (BOOL)validateSelectionKeys:(NSString *)selectionKeys {
  int i = 0;
  for (i = 0; i < [selectionKeys length] - 1; i++) {
    char currKey = [selectionKeys characterAtIndex:i];
    int j = i + 1;
    for (j = i + 1; i < [selectionKeys length]; i++) {
      char checkKey = [selectionKeys characterAtIndex:j];
      if (currKey == checkKey) return NO;
    }
  }
  return YES;
}

#pragma mark Interface Builder actions

- (IBAction)setSelectionKey:(id)sender {
  NSString *selectionKeys = [_selectionKeyComboBox stringValue];
  // Eight or nine keys: nine fills the single-row candidate window.
  if (![self validateSelectionKeys:selectionKeys]) selectionKeys = @"123456789";
  if ([selectionKeys length] > 9)
    selectionKeys = [selectionKeys substringToIndex:9];
  if ([selectionKeys length] < 8) selectionKeys = @"123456789";

  [_selectionKeyComboBox setStringValue:selectionKeys];
  [self writePreference:sender];
}
- (IBAction)writePreference:(id)sender {
  BOOL showedRareCharacters = [[_phoneticDictionary
      valueForKey:@"ShowRareCharacters"] isEqualToString:@"true"];
  [self updateDictionary];
  // Turned on with nothing to draw them: say which font to get.
  if (sender == _showRareCharactersCheckBox && !showedRareCharacters &&
      [_showRareCharactersCheckBox intValue] && !TakaoHasRareCharacterFont())
    [self _offerRareCharacterFonts];
  NSData *data = [NSPropertyListSerialization
      dataWithPropertyList:_phoneticDictionary
                    format:NSPropertyListXMLFormat_v1_0
                   options:0
                     error:nil];

  if (data) {
    [data writeToFile:_preferenceFilePath atomically:YES];
  }
}
- (void)_downloadFontWithTag:(NSInteger)tag {
  NSString *url = tag == 1 ? TakaoCNSSungFontURL : TakaoCNSKaiFontURL;
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}
- (IBAction)downloadRareCharacterFont:(id)sender {
  [self _downloadFontWithTag:[sender tag]];
}
- (NSString *)rareCharacterFontNote {
  return TakaoHasRareCharacterFont()
             ? NSLocalizedString(@"A font for these characters is installed.", nil)
             : NSLocalizedString(@"No font for these characters yet: download "
                                 @"one, unzip it and double-click the fonts.",
                                 nil);
}
- (void)setRareCharacterFontNoteLabel:(NSTextField *)label {
  if (!_rareCharacterFontNoteLabel)
    // Fonts get installed elsewhere; look again whenever a window comes back.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_refreshRareCharacterFontNote:)
               name:NSWindowDidBecomeKeyNotification
             object:nil];
  _rareCharacterFontNoteLabel = label;
}
- (void)_refreshRareCharacterFontNote:(NSNotification *)notification {
  NSString *note = [self rareCharacterFontNote];
  if (![[_rareCharacterFontNoteLabel stringValue] isEqualToString:note])
    [_rareCharacterFontNoteLabel setStringValue:note];
}
- (void)_offerRareCharacterFonts {
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:NSLocalizedString(
                            @"These rare characters need a font to show", nil)];
  [alert setInformativeText:NSLocalizedString(
                                @"Install the free CNS 11643 fonts from the "
                                @"Ministry of Digital Affairs: unzip the "
                                @"download and double-click the font files. "
                                @"Then switch input methods once.",
                                nil)];
  [alert addButtonWithTitle:NSLocalizedString(@"Download TW-Kai", nil)];
  [alert addButtonWithTitle:NSLocalizedString(@"Download TW-Sung", nil)];
  [alert addButtonWithTitle:NSLocalizedString(@"Later", nil)];
  void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
    if (response == NSAlertFirstButtonReturn) [self _downloadFontWithTag:0];
    if (response == NSAlertSecondButtonReturn) [self _downloadFontWithTag:1];
  };
  NSWindow *window = [_showRareCharactersCheckBox window];
  if (window)
    [alert beginSheetModalForWindow:window completionHandler:handler];
  else
    handler([alert runModal]);
}
@end
