//
//  AppDelegate.m
//  MacStartupSound
//

#import "AppDelegate.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "LidAngleSensor.h"

static const double kArmBelowAngle = 70.0;
static const double kLidThresholdAngle = 70.0;
static const double kTriggerDeltaThreshold = 70.0;
static const double kClosedWrapMinAngle = 300.0;
static const NSTimeInterval kTriggerWindowSeconds = 1.5;
static const NSTimeInterval kTriggerCooldownSeconds = 1.0;
static const NSTimeInterval kPollingIntervalSeconds = 0.02;
static const NSTimeInterval kMaxPlaybackSeconds = 10.0;
static NSString * const kCustomSoundFileNameDefaultsKey = @"CustomSoundFileName";

@interface AppDelegate ()

@property (nonatomic, strong) LidAngleSensor *lidSensor;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) AVAudioPlayer *triggerPlayer;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *angleMenuItem;
@property (nonatomic, strong) NSMenuItem *soundToggleMenuItem;
@property (nonatomic, strong) NSMenuItem *chooseSoundMenuItem;
@property (nonatomic, strong) NSMenuItem *useDefaultSoundMenuItem;
@property (nonatomic, assign) BOOL hasPreviousAngle;
@property (nonatomic, assign) double previousAngle;
@property (nonatomic, assign) BOOL soundEnabled;
@property (nonatomic, assign) BOOL usingCustomSound;
@property (nonatomic, copy) NSString *lastDebugEvent;
@property (nonatomic, assign) double lastDelta;
@property (nonatomic, assign) BOOL gestureArmed;
@property (nonatomic, assign) double gestureStartAngle;
@property (nonatomic, assign) CFTimeInterval gestureStartTime;
@property (nonatomic, assign) double gestureDelta;
@property (nonatomic, assign) CFTimeInterval gestureDuration;
@property (nonatomic, assign) CFTimeInterval cooldownUntil;
@property (nonatomic, assign) BOOL sampleTriggered;
@property (nonatomic, assign) NSInteger triggerCount;
@property (nonatomic, copy) dispatch_block_t stopPlaybackBlock;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.lidSensor = [[LidAngleSensor alloc] init];
    self.hasPreviousAngle = NO;
    self.soundEnabled = YES;
    self.usingCustomSound = NO;
    self.lastDebugEvent = @"Boot";
    self.lastDelta = 0.0;
    self.gestureArmed = NO;
    self.gestureStartAngle = 0.0;
    self.gestureStartTime = 0.0;
    self.gestureDelta = 0.0;
    self.gestureDuration = 0.0;
    self.cooldownUntil = 0.0;
    self.sampleTriggered = NO;
    self.triggerCount = 0;
    [self prepareTriggerPlayer];

    [self buildStatusItem];

    self.updateTimer = [NSTimer timerWithTimeInterval:kPollingIntervalSeconds
                                               target:self
                                             selector:@selector(updateLidState)
                                             userInfo:nil
                                              repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
}

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"";
    NSImage *statusIcon = nil;
    if (@available(macOS 11.0, *)) {
        statusIcon = [NSImage imageWithSystemSymbolName:@"laptopcomputer" accessibilityDescription:@"MacStartupSound"];
    } else {
        statusIcon = [NSImage imageNamed:NSImageNameComputer];
    }
    statusIcon.template = YES;
    self.statusItem.button.image = statusIcon;
    self.statusItem.button.toolTip = @"MacStartupSound";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MacStartupSound"];

    self.angleMenuItem = [[NSMenuItem alloc] initWithTitle:@"Angle: --"
                                                    action:nil
                                             keyEquivalent:@""];
    self.angleMenuItem.enabled = NO;
    [menu addItem:self.angleMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.soundToggleMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                           action:@selector(toggleSound:)
                                                    keyEquivalent:@""];
    self.soundToggleMenuItem.target = self;
    [menu addItem:self.soundToggleMenuItem];

    self.chooseSoundMenuItem = [[NSMenuItem alloc] initWithTitle:@"Choose Custom Sound…"
                                                          action:@selector(chooseCustomSound:)
                                                   keyEquivalent:@""];
    self.chooseSoundMenuItem.target = self;
    [menu addItem:self.chooseSoundMenuItem];

    self.useDefaultSoundMenuItem = [[NSMenuItem alloc] initWithTitle:@"Use Default Sound"
                                                               action:@selector(useDefaultSound:)
                                                        keyEquivalent:@""];
    self.useDefaultSoundMenuItem.target = self;
    [menu addItem:self.useDefaultSoundMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                       action:@selector(quitApp:)
                                                keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
    [self refreshSoundMenuTitle];
    [self refreshStatusUIWithAngle:-1.0];
}

- (void)refreshSoundMenuTitle {
    NSString *sourceText = self.usingCustomSound ? @"Custom" : @"Default";
    self.soundToggleMenuItem.title = self.soundEnabled
        ? [NSString stringWithFormat:@"Sound: On (%@)", sourceText]
        : [NSString stringWithFormat:@"Sound: Off (%@)", sourceText];
}

- (void)toggleSound:(id)sender {
    (void)sender;
    self.soundEnabled = !self.soundEnabled;
    [self refreshSoundMenuTitle];
    self.lastDebugEvent = self.soundEnabled ? @"Sound toggled ON" : @"Sound toggled OFF";
    [self refreshStatusUIWithAngle:self.hasPreviousAngle ? self.previousAngle : -1.0];
}

- (void)quitApp:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)prepareTriggerPlayer {
    [self loadPreferredTriggerPlayer];
}

- (void)chooseCustomSound:(id)sender {
    (void)sender;
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[@"mp3", @"m4a", @"wav", @"aiff"];

    if ([openPanel runModal] != NSModalResponseOK || openPanel.URLs.count == 0) {
        return;
    }

    NSError *copyError = nil;
    if (![self installCustomSoundFromURL:openPanel.URLs.firstObject error:&copyError]) {
        NSLog(@"[MacStartupSound] Failed to set custom sound: %@", copyError.localizedDescription);
        self.lastDebugEvent = @"Failed to set custom sound";
        [self refreshStatusUIWithAngle:self.hasPreviousAngle ? self.previousAngle : -1.0];
        return;
    }

    [self loadPreferredTriggerPlayer];
    self.lastDebugEvent = @"Loaded custom sound";
    [self refreshStatusUIWithAngle:self.hasPreviousAngle ? self.previousAngle : -1.0];
}

- (void)useDefaultSound:(id)sender {
    (void)sender;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *storedName = [defaults stringForKey:kCustomSoundFileNameDefaultsKey];
    if (storedName.length > 0) {
        NSError *dirError = nil;
        NSURL *appSupportDirectory = [self applicationSupportDirectoryURLCreatingIfNeeded:NO error:&dirError];
        if (appSupportDirectory) {
            NSURL *customFileURL = [appSupportDirectory URLByAppendingPathComponent:storedName];
            [[NSFileManager defaultManager] removeItemAtURL:customFileURL error:nil];
        }
        [defaults removeObjectForKey:kCustomSoundFileNameDefaultsKey];
    }

    [self loadPreferredTriggerPlayer];
    self.lastDebugEvent = @"Using default sound";
    [self refreshStatusUIWithAngle:self.hasPreviousAngle ? self.previousAngle : -1.0];
}

- (BOOL)loadPlayerFromURL:(NSURL *)url {
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (error || !player) {
        NSLog(@"[MacStartupSound] Failed to load sound at %@: %@", url.path, error.localizedDescription);
        return NO;
    }

    self.triggerPlayer = player;
    [self.triggerPlayer prepareToPlay];
    return YES;
}

- (NSURL *)bundledDefaultSoundURL {
    NSString *soundPath = [[NSBundle mainBundle] pathForResource:@"startup_sound" ofType:@"wav"];
    if (soundPath.length == 0) {
        return nil;
    }
    return [NSURL fileURLWithPath:soundPath];
}

- (NSURL *)applicationSupportDirectoryURLCreatingIfNeeded:(BOOL)create error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *baseURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    if (!baseURL) {
        return nil;
    }

    NSString *bundleName = [NSBundle mainBundle].bundleIdentifier ?: @"MacStartupSound";
    NSURL *appSupportDirectory = [baseURL URLByAppendingPathComponent:bundleName isDirectory:YES];
    if (create) {
        if (![fileManager createDirectoryAtURL:appSupportDirectory
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:error]) {
            return nil;
        }
    }
    return appSupportDirectory;
}

- (NSURL *)customSoundURL {
    NSString *storedName = [NSUserDefaults.standardUserDefaults stringForKey:kCustomSoundFileNameDefaultsKey];
    if (storedName.length == 0) {
        return nil;
    }

    NSError *dirError = nil;
    NSURL *appSupportDirectory = [self applicationSupportDirectoryURLCreatingIfNeeded:NO error:&dirError];
    if (!appSupportDirectory) {
        return nil;
    }

    NSURL *customFileURL = [appSupportDirectory URLByAppendingPathComponent:storedName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:customFileURL.path]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCustomSoundFileNameDefaultsKey];
        return nil;
    }
    return customFileURL;
}

- (BOOL)installCustomSoundFromURL:(NSURL *)sourceURL error:(NSError **)error {
    NSURL *appSupportDirectory = [self applicationSupportDirectoryURLCreatingIfNeeded:YES error:error];
    if (!appSupportDirectory) {
        return NO;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *previousName = [defaults stringForKey:kCustomSoundFileNameDefaultsKey];
    if (previousName.length > 0) {
        NSURL *previousURL = [appSupportDirectory URLByAppendingPathComponent:previousName];
        [[NSFileManager defaultManager] removeItemAtURL:previousURL error:nil];
    }

    NSString *extension = sourceURL.pathExtension.lowercaseString;
    if (extension.length == 0) {
        extension = @"mp3";
    }
    NSString *fileName = [NSString stringWithFormat:@"custom_sound.%@", extension];
    NSURL *destinationURL = [appSupportDirectory URLByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];

    if (![[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destinationURL error:error]) {
        return NO;
    }

    [defaults setObject:fileName forKey:kCustomSoundFileNameDefaultsKey];
    return YES;
}

- (void)loadPreferredTriggerPlayer {
    NSURL *customURL = [self customSoundURL];
    if (customURL && [self loadPlayerFromURL:customURL]) {
        self.usingCustomSound = YES;
        return;
    }

    NSURL *defaultURL = [self bundledDefaultSoundURL];
    if (defaultURL && [self loadPlayerFromURL:defaultURL]) {
        self.usingCustomSound = NO;
        return;
    }

    self.usingCustomSound = NO;
    self.triggerPlayer = nil;
    NSLog(@"[MacStartupSound] Missing bundled sound: startup_sound.wav");
}

- (void)updateLidState {
    if (!self.lidSensor.isAvailable) {
        self.sampleTriggered = NO;
        self.lastDebugEvent = @"Sensor unavailable";
        [self refreshStatusUIWithAngle:-1.0];
        return;
    }

    double angle = [self.lidSensor lidAngle];
    if (angle < 0) {
        self.sampleTriggered = NO;
        self.lastDebugEvent = @"Invalid lid read";
        [self refreshStatusUIWithAngle:-1.0];
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();

    if (angle >= kClosedWrapMinAngle) {
        self.sampleTriggered = NO;
        self.gestureArmed = NO;
        self.gestureDelta = 0.0;
        self.gestureDuration = 0.0;
        self.lastDebugEvent = @"Ignored wrap/closed angle";
        self.previousAngle = angle;
        [self refreshStatusUIWithAngle:angle];
        return;
    }

    if (!self.hasPreviousAngle) {
        self.previousAngle = angle;
        self.hasPreviousAngle = YES;
        self.gestureArmed = (angle <= kArmBelowAngle);
        self.gestureStartAngle = angle;
        self.gestureStartTime = now;
        self.lastDelta = 0.0;
        self.gestureDelta = 0.0;
        self.gestureDuration = 0.0;
        self.sampleTriggered = NO;
        self.lastDebugEvent = @"Primed first angle";
        [self refreshStatusUIWithAngle:angle];
        return;
    }

    double delta = fabs(angle - self.previousAngle);
    self.lastDelta = delta;

    if (now < self.cooldownUntil) {
        self.sampleTriggered = NO;
        self.lastDebugEvent = @"Cooldown";
        self.previousAngle = angle;
        [self refreshStatusUIWithAngle:angle];
        return;
    }

    if (angle <= kArmBelowAngle) {
        if (!self.gestureArmed) {
            self.gestureArmed = YES;
            self.gestureStartAngle = angle;
            self.gestureStartTime = now;
            self.lastDebugEvent = @"Armed";
        } else if (angle < self.gestureStartAngle) {
            self.gestureStartAngle = angle;
            self.gestureStartTime = now;
            self.lastDebugEvent = @"Armed lower baseline";
        }
    }

    if (self.gestureArmed) {
        self.gestureDuration = now - self.gestureStartTime;
        self.gestureDelta = angle - self.gestureStartAngle;
        if (self.gestureDelta < 0.0) {
            self.gestureDelta = 0.0;
        }

        self.sampleTriggered = (angle > kLidThresholdAngle &&
                                self.gestureDelta > kTriggerDeltaThreshold &&
                                self.gestureDuration <= kTriggerWindowSeconds);

        if (self.sampleTriggered) {
            [self playTriggerSound];
            self.gestureArmed = NO;
            self.cooldownUntil = now + kTriggerCooldownSeconds;
        } else if (self.gestureDuration > kTriggerWindowSeconds) {
            self.gestureArmed = (angle <= kArmBelowAngle);
            self.gestureStartAngle = angle;
            self.gestureStartTime = now;
            self.gestureDelta = 0.0;
            self.gestureDuration = 0.0;
            self.lastDebugEvent = @"Window expired";
        } else if (angle <= kLidThresholdAngle) {
            self.lastDebugEvent = @"Tracking opening gesture";
        } else {
            self.lastDebugEvent = @"Above 90 but change/window not met";
        }
    } else {
        self.sampleTriggered = NO;
        self.gestureDelta = 0.0;
        self.gestureDuration = 0.0;
        self.lastDebugEvent = @"Waiting to arm (close lid below 70)";
    }

    self.previousAngle = angle;
    [self refreshStatusUIWithAngle:angle];
}

- (void)playTriggerSound {
    if (!self.triggerPlayer || !self.soundEnabled) {
        if (!self.triggerPlayer) {
            self.lastDebugEvent = @"Blocked: player not loaded";
        } else {
            self.lastDebugEvent = @"Blocked: sound toggle OFF";
        }
        return;
    }

    self.triggerPlayer.currentTime = 0;
    BOOL played = [self.triggerPlayer play];
    if (played) {
        if (self.stopPlaybackBlock) {
            dispatch_block_cancel(self.stopPlaybackBlock);
            self.stopPlaybackBlock = nil;
        }
        __block dispatch_block_t stopBlock = nil;
        __weak typeof(self) weakSelf = self;
        stopBlock = dispatch_block_create(0, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.stopPlaybackBlock != stopBlock) {
                return;
            }
            if (strongSelf.triggerPlayer.isPlaying) {
                [strongSelf.triggerPlayer stop];
                strongSelf.lastDebugEvent = @"Stopped playback at 10s";
                [strongSelf refreshStatusUIWithAngle:strongSelf.hasPreviousAngle ? strongSelf.previousAngle : -1.0];
            }
            strongSelf.stopPlaybackBlock = nil;
        });
        self.stopPlaybackBlock = stopBlock;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMaxPlaybackSeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       stopBlock);

        self.triggerCount += 1;
        self.lastDebugEvent = @"Played trigger sound";
    } else {
        self.lastDebugEvent = @"Play call failed";
    }
}

- (void)refreshStatusUIWithAngle:(double)angle {
    NSString *angleText = (angle < 0) ? @"--" : [NSString stringWithFormat:@"%.1f", angle];
    self.angleMenuItem.title = [NSString stringWithFormat:@"Angle: %@", angleText];
    [self refreshSoundMenuTitle];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (self.stopPlaybackBlock) {
        dispatch_block_cancel(self.stopPlaybackBlock);
        self.stopPlaybackBlock = nil;
    }
    [self.updateTimer invalidate];
    [self.lidSensor stopLidAngleUpdates];
}

@end
