#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>

static NSString *const DeviceIDKey = @"id";
static NSString *const DeviceNameKey = @"name";
static NSString *const DeviceInputKey = @"input";
static NSString *const DeviceOutputKey = @"output";

static NSString *DeviceName(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef name = NULL;
    UInt32 size = sizeof(name);
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &name) != noErr || !name) {
        return @"Périphérique inconnu";
    }
    return CFBridgingRelease(name);
}

static UInt32 ChannelCount(AudioDeviceID deviceID, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamConfiguration,
        scope,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) != noErr || size == 0) return 0;
    AudioBufferList *list = malloc(size);
    if (!list) return 0;
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, list) != noErr) {
        free(list);
        return 0;
    }
    UInt32 count = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) count += list->mBuffers[i].mNumberChannels;
    free(list);
    return count;
}

static NSArray<NSDictionary *> *AllDevices(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr) return @[];
    AudioDeviceID *ids = malloc(size);
    if (!ids) return @[];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids) != noErr) {
        free(ids);
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    NSUInteger count = size / sizeof(AudioDeviceID);
    for (NSUInteger i = 0; i < count; i++) {
        BOOL input = ChannelCount(ids[i], kAudioDevicePropertyScopeInput) > 0;
        BOOL output = ChannelCount(ids[i], kAudioDevicePropertyScopeOutput) > 0;
        if (!input && !output) continue;
        [result addObject:@{
            DeviceIDKey: @(ids[i]),
            DeviceNameKey: DeviceName(ids[i]),
            DeviceInputKey: @(input),
            DeviceOutputKey: @(output)
        }];
    }
    free(ids);
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[DeviceNameKey] localizedStandardCompare:b[DeviceNameKey]];
    }];
}

static AudioDeviceID DefaultDevice(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = { selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceID);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &deviceID);
    return deviceID;
}

static OSStatus SetDefaultDevice(AudioDeviceID deviceID, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = { selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, sizeof(deviceID), &deviceID);
}

static NSColor *RGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

@interface StudioBackgroundView : NSView
@end

@implementation StudioBackgroundView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:RGB(5, 10, 16, 1)
                                                       endingColor:RGB(12, 25, 28, 1)];
    [gradient drawInRect:self.bounds angle:-35];

    NSBezierPath *glow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-120, -170, 520, 380)];
    [RGB(230, 36, 41, 0.075) setFill];
    [glow fill];

    NSBezierPath *bottomGlow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(self.bounds.size.width - 280, self.bounds.size.height - 120, 430, 280)];
    [RGB(23, 105, 170, 0.060) setFill];
    [bottomGlow fill];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSWindow *window;
@property NSPopUpButton *inputPopup;
@property NSPopUpButton *outputPopup;
@property NSTextField *statusLabel;
@property NSStatusItem *statusItem;
@property NSArray<NSDictionary *> *devices;
@property NSTimer *timer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self buildMainMenu];
    [self buildWindow];
    [self buildStatusItem];
    [self refresh:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshQuietly:) userInfo:nil repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (void)buildMainMenu {
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [main addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Source Audio"];
    [appMenu addItemWithTitle:@"À propos de Source Audio" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:@"Quitter Source Audio" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;
    NSApp.mainMenu = main;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSView *)deviceCardWithTitle:(NSString *)title subtitle:(NSString *)subtitle popup:(NSPopUpButton **)popup {
    NSBox *card = [[NSBox alloc] init];
    card.boxType = NSBoxCustom;
    card.cornerRadius = 18;
    card.fillColor = RGB(15, 27, 33, 0.92);
    card.borderColor = RGB(230, 36, 41, 0.28);
    card.borderWidth = 1;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSString *symbol = [title isEqualToString:@"Entrée"] ? @"mic.fill" : @"speaker.wave.2.fill";
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title]];
    icon.contentTintColor = RGB(242, 48, 54, 1);
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:19 weight:NSFontWeightMedium];
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *eyebrow = [self label:[title isEqualToString:@"Entrée"] ? @"SOURCE ACTIVE" : @"DESTINATION ACTIVE"
                                      size:10 weight:NSFontWeightBold];
    eyebrow.textColor = RGB(242, 48, 54, 0.88);
    NSTextField *heading = [self label:title size:20 weight:NSFontWeightSemibold];
    NSTextField *detail = [self label:subtitle size:12 weight:NSFontWeightRegular];
    detail.textColor = RGB(181, 199, 202, 0.72);
    NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    picker.controlSize = NSControlSizeLarge;
    picker.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    picker.contentTintColor = RGB(245, 232, 233, 1);
    picker.target = self;
    picker.action = [title isEqualToString:@"Entrée"] ? @selector(inputChanged:) : @selector(outputChanged:);
    *popup = picker;

    [card.contentView addSubview:icon];
    [card.contentView addSubview:eyebrow];
    [card.contentView addSubview:heading];
    [card.contentView addSubview:detail];
    [card.contentView addSubview:picker];
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:24],
        [icon.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:22],
        [icon.widthAnchor constraintEqualToConstant:28],
        [icon.heightAnchor constraintEqualToConstant:28],
        [eyebrow.topAnchor constraintEqualToAnchor:icon.topAnchor constant:1],
        [eyebrow.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [heading.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:1],
        [heading.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [detail.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:9],
        [detail.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [picker.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:18],
        [picker.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [picker.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-22],
        [picker.heightAnchor constraintEqualToConstant:34],
        [picker.bottomAnchor constraintLessThanOrEqualToAnchor:card.contentView.bottomAnchor constant:-22]
    ]];
    return card;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 455)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                               backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Source Audio";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.minSize = NSMakeSize(720, 420);
    [self.window center];

    StudioBackgroundView *content = [[StudioBackgroundView alloc] initWithFrame:self.window.contentView.bounds];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = content;

    NSImageView *brandIcon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    brandIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    brandIcon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *kicker = [self label:@"MAC AUDIO ROUTER" size:10 weight:NSFontWeightBold];
    kicker.textColor = RGB(242, 48, 54, 0.92);
    NSTextField *title = [self label:@"Source Audio" size:32 weight:NSFontWeightBold];
    NSTextField *subtitle = [self label:@"Pilote simplement le son de ton Mac." size:14 weight:NSFontWeightRegular];
    subtitle.textColor = RGB(181, 199, 202, 0.78);
    NSButton *refresh = [NSButton buttonWithTitle:@"↻  Actualiser" target:self action:@selector(refresh:)];
    refresh.bezelStyle = NSBezelStyleRounded;
    refresh.controlSize = NSControlSizeLarge;
    refresh.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    refresh.contentTintColor = RGB(242, 48, 54, 1);
    refresh.translatesAutoresizingMaskIntoConstraints = NO;

    NSPopUpButton *inputPopup = nil;
    NSPopUpButton *outputPopup = nil;
    NSView *inputCard = [self deviceCardWithTitle:@"Entrée" subtitle:@"Microphone et interfaces audio" popup:&inputPopup];
    NSView *outputCard = [self deviceCardWithTitle:@"Sortie" subtitle:@"Casque, enceintes et écrans" popup:&outputPopup];
    self.inputPopup = inputPopup;
    self.outputPopup = outputPopup;
    self.statusLabel = [self label:@"●  Détection des périphériques…" size:12 weight:NSFontWeightMedium];
    self.statusLabel.textColor = RGB(242, 48, 54, 0.82);
    NSTextField *menubarHint = [self label:@"Disponible aussi depuis la barre des menus" size:12 weight:NSFontWeightRegular];
    menubarHint.textColor = RGB(181, 199, 202, 0.56);

    for (NSView *view in @[brandIcon, kicker, title, subtitle, refresh, inputCard, outputCard, self.statusLabel, menubarHint]) [content addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [brandIcon.topAnchor constraintEqualToAnchor:content.topAnchor constant:55],
        [brandIcon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:34],
        [brandIcon.widthAnchor constraintEqualToConstant:42],
        [brandIcon.heightAnchor constraintEqualToConstant:42],
        [kicker.topAnchor constraintEqualToAnchor:brandIcon.topAnchor constant:-1],
        [kicker.leadingAnchor constraintEqualToAnchor:brandIcon.trailingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:kicker.bottomAnchor constant:1],
        [title.leadingAnchor constraintEqualToAnchor:kicker.leadingAnchor],
        [subtitle.centerYAnchor constraintEqualToAnchor:title.centerYAnchor constant:3],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:16],
        [refresh.centerYAnchor constraintEqualToAnchor:brandIcon.centerYAnchor],
        [refresh.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-34],
        [inputCard.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:31],
        [inputCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:34],
        [inputCard.widthAnchor constraintEqualToAnchor:outputCard.widthAnchor],
        [inputCard.heightAnchor constraintEqualToConstant:186],
        [outputCard.topAnchor constraintEqualToAnchor:inputCard.topAnchor],
        [outputCard.leadingAnchor constraintEqualToAnchor:inputCard.trailingAnchor constant:18],
        [outputCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-34],
        [outputCard.heightAnchor constraintEqualToAnchor:inputCard.heightAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:22],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor],
        [menubarHint.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [menubarHint.trailingAnchor constraintEqualToAnchor:outputCard.trailingAnchor]
    ]];
}

- (void)buildStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"waveform" accessibilityDescription:@"Source Audio"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Source Audio"];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

- (void)fillPopup:(NSPopUpButton *)popup devices:(NSArray<NSDictionary *> *)devices selected:(AudioDeviceID)selected {
    [popup removeAllItems];
    if (devices.count == 0) {
        [popup addItemWithTitle:@"Aucun périphérique détecté"];
        popup.enabled = NO;
        return;
    }
    popup.enabled = YES;
    for (NSDictionary *device in devices) {
        [popup addItemWithTitle:device[DeviceNameKey]];
        popup.lastItem.representedObject = device[DeviceIDKey];
        if ([device[DeviceIDKey] unsignedIntValue] == selected) [popup selectItem:popup.lastItem];
    }
}

- (void)refresh:(id)sender {
    (void)sender;
    [self loadDevicesShowingStatus:YES];
}

- (void)refreshQuietly:(NSTimer *)timer {
    (void)timer;
    [self loadDevicesShowingStatus:NO];
}

- (void)loadDevicesShowingStatus:(BOOL)showStatus {
    self.devices = AllDevices();
    NSArray *inputs = [self.devices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *_) {
        (void)_;
        return [d[DeviceInputKey] boolValue];
    }]];
    NSArray *outputs = [self.devices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *_) {
        (void)_;
        return [d[DeviceOutputKey] boolValue];
    }]];
    [self fillPopup:self.inputPopup devices:inputs selected:DefaultDevice(kAudioHardwarePropertyDefaultInputDevice)];
    [self fillPopup:self.outputPopup devices:outputs selected:DefaultDevice(kAudioHardwarePropertyDefaultOutputDevice)];
    if (showStatus || self.statusLabel.stringValue.length == 0) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu périphérique%@ détecté%@ • mise à jour automatique",
            (unsigned long)self.devices.count, self.devices.count > 1 ? @"s" : @"", self.devices.count > 1 ? @"s" : @""];
    }
}

- (void)showError:(OSStatus)status {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Impossible de changer le périphérique";
    alert.informativeText = [NSString stringWithFormat:@"Core Audio a retourné l’erreur %d.", status];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)inputChanged:(NSPopUpButton *)sender {
    AudioDeviceID deviceID = [sender.selectedItem.representedObject unsignedIntValue];
    OSStatus status = SetDefaultDevice(deviceID, kAudioHardwarePropertyDefaultInputDevice);
    if (status != noErr) [self showError:status];
    [self loadDevicesShowingStatus:NO];
}

- (void)outputChanged:(NSPopUpButton *)sender {
    AudioDeviceID deviceID = [sender.selectedItem.representedObject unsignedIntValue];
    OSStatus status = SetDefaultDevice(deviceID, kAudioHardwarePropertyDefaultOutputDevice);
    if (status == noErr) SetDefaultDevice(deviceID, kAudioHardwarePropertyDefaultSystemOutputDevice);
    else [self showError:status];
    [self loadDevicesShowingStatus:NO];
}

- (void)selectMenuInput:(NSMenuItem *)item {
    OSStatus status = SetDefaultDevice([item.representedObject unsignedIntValue], kAudioHardwarePropertyDefaultInputDevice);
    if (status != noErr) [self showError:status];
}

- (void)selectMenuOutput:(NSMenuItem *)item {
    AudioDeviceID deviceID = [item.representedObject unsignedIntValue];
    OSStatus status = SetDefaultDevice(deviceID, kAudioHardwarePropertyDefaultOutputDevice);
    if (status == noErr) SetDefaultDevice(deviceID, kAudioHardwarePropertyDefaultSystemOutputDevice);
    else [self showError:status];
}

- (NSMenu *)deviceSubmenuForInput:(BOOL)isInput {
    NSMenu *submenu = [[NSMenu alloc] init];
    AudioDeviceID selected = DefaultDevice(isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice);
    for (NSDictionary *device in self.devices) {
        if (![device[isInput ? DeviceInputKey : DeviceOutputKey] boolValue]) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:device[DeviceNameKey]
                                                     action:isInput ? @selector(selectMenuInput:) : @selector(selectMenuOutput:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = device[DeviceIDKey];
        item.state = [device[DeviceIDKey] unsignedIntValue] == selected ? NSControlStateValueOn : NSControlStateValueOff;
        [submenu addItem:item];
    }
    return submenu;
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self loadDevicesShowingStatus:NO];
    [menu removeAllItems];
    NSMenuItem *input = [[NSMenuItem alloc] initWithTitle:@"Entrée" action:nil keyEquivalent:@""];
    input.submenu = [self deviceSubmenuForInput:YES];
    [menu addItem:input];
    NSMenuItem *output = [[NSMenuItem alloc] initWithTitle:@"Sortie" action:nil keyEquivalent:@""];
    output.submenu = [self deviceSubmenuForInput:NO];
    [menu addItem:output];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *open = [menu addItemWithTitle:@"Ouvrir Source Audio…" action:@selector(showWindow:) keyEquivalent:@""];
    open.target = self;
    NSMenuItem *quit = [menu addItemWithTitle:@"Quitter" action:@selector(terminate:) keyEquivalent:@""];
    quit.target = NSApp;
}

- (void)showWindow:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--check") == 0) {
            NSArray<NSDictionary *> *devices = AllDevices();
            printf("%lu périphérique(s) audio détecté(s)\n", (unsigned long)devices.count);
            for (NSDictionary *device in devices) {
                printf("- %s%s%s\n",
                       [device[DeviceNameKey] UTF8String],
                       [device[DeviceInputKey] boolValue] ? " [entrée]" : "",
                       [device[DeviceOutputKey] boolValue] ? " [sortie]" : "");
            }
            return devices.count > 0 ? 0 : 2;
        }
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app run];
    }
    return 0;
}
