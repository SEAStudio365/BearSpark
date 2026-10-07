/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>
#import "NSStringExtension.h"
#import "TakaoSettings.h"

/*!
        @header TakaoGlobal
*/

/*!
        @class TakaoGlobal
        @abstract The class to interact with user interface and the
        global settings.
*/
@interface TakaoGlobal : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
  IBOutlet NSPopUpButton *_keyboardLayoutPopUpButton;
  IBOutlet id _soundListPopUpButton;
  IBOutlet id _soundCheckBox;
  IBOutlet id _stopPlayiongButton;
  IBOutlet id _highlightColorPopUpButton;
  IBOutlet NSTableView *_moduleListTableView;
  IBOutlet NSMatrix *_candidateWindowStyleMatrix;
  IBOutlet id _useUpdateCheckBox;
  IBOutlet id _useCtrlBackSlashToggleInputMethod;
  IBOutlet id _applyCapsLockDelayOverrideCheckBox;
  IBOutlet id _shiftTogglesTemporaryEnglishCheckBox;

  NSMutableDictionary *_takaoDictionary;
  NSString *_preferenceFilePath;
  NSString *_customSoundFilePath;
  NSSound *_sound;
  NSMutableArray *_keyboardLayoutIdentifierArray;
  NSMutableArray *_inputMethods;

  // The General pane's modern layout (see layoutGeneralView:keyboardView:).
  NSArray *_nibGeneralViews;  // keeps the nib's views alive once moved
  NSPopUpButton *_candidateStylePopUpButton;

  BOOL _init;
}

#pragma mark Interface Builder actions

- (void)setInputMethods:(NSArray *)modules;

// Rearranges the General pane into TakaoForm rows. The nib's check boxes
// stay, hidden, behind switches that mirror them, so the reading and writing
// of the settings is unchanged.
- (void)layoutGeneralView:(NSView *)generalView
             keyboardView:(NSView *)keyboardView;

/*!
        @method writePreference:
        @abstract Writes the settings into the plist file.
        @param sender The sender object.
*/
- (IBAction)writePreference:(id)sender;
/*!
        @method changeSound:
        @abstract Changes the specified alert sound.
        @param sender The sender object.
*/
- (IBAction)changeSound:(id)sender;
/*!
        @method testSound:
        @abstract Plays the specified alert sound for testing.
        @param sender The sender object.
*/
- (IBAction)testSound:(id)sender;
/*!
        @method stopSound:
        @abstract Stops playing the specified alert sound.
        @param sender The sender object.
*/
- (IBAction)stopSound:(id)sender;
- (IBAction)setKeyboardLayout:(id)sender;
- (IBAction)resetKeyboardLayout:(id)sender;
- (IBAction)setHighlightColor:(id)sender;
@end

@interface TakaoColorPopUpButton : NSPopUpButton {
  IBOutlet TakaoGlobal *_controller;
  NSMenu *_colorMenu;
  NSMenuItem *_customizedColorMenuItem;
  NSMutableArray *_colors;
  NSString *_initString;
}

- (IBAction)customize:(id)sender;
- (void)changeCustomizedColorFromColorPicker:(id)sender;
- (NSString *)colorString;
- (void)setColorSelection:(NSString *)colorString;
@end
