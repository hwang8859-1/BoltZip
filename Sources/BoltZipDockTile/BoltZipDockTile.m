#import <AppKit/AppKit.h>

static NSString * const StyleKey = @"BoltZip.AppIconStyle";
static NSString * const StyleChangedNotification = @"dev.boltzip.macos.dockIconStyleDidChange";

@interface BoltZipDockTile : NSObject <NSDockTilePlugIn>
@property (nonatomic, strong) NSDockTile *tile;
@property (nonatomic, strong) NSBundle *applicationBundle;
@property (nonatomic, copy) NSString *style;

@end

@implementation BoltZipDockTile

- (void)setDockTile:(NSDockTile *)tile {
    NSDistributedNotificationCenter *notifications = NSDistributedNotificationCenter.defaultCenter;
    [notifications removeObserver:self];
    self.tile = tile;
    if (!tile) return;

    NSURL *bundleURL = [NSBundle bundleForClass:self.class].bundleURL;
    for (NSUInteger i = 0; i < 3; i++) {
        bundleURL = [bundleURL URLByDeletingLastPathComponent];
    }
    self.applicationBundle = [NSBundle bundleWithURL:bundleURL];
    NSString *identifier = self.applicationBundle.bundleIdentifier;
    if (!identifier) return;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:identifier];
    NSString *style = [defaults stringForKey:StyleKey];
    if (!style && [defaults boolForKey:@"BoltZip.UseWhiteAppIcon"]) style = @"light";
    self.style = style;
    [self updateIcon];

    [notifications addObserver:self
                       selector:@selector(styleChanged:)
                           name:StyleChangedNotification
                         object:identifier
             suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [notifications addObserver:self
                       selector:@selector(systemAppearanceChanged:)
                           name:@"AppleInterfaceThemeChangedNotification"
                         object:nil
             suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

- (void)styleChanged:(NSNotification *)note {
    id style = note.userInfo[StyleKey];
    self.style = [style isKindOfClass:NSString.class] ? style : nil;
    [self updateIcon];
}

- (void)systemAppearanceChanged:(NSNotification *)note {
    if (![self.style isEqualToString:@"light"] && ![self.style isEqualToString:@"dark"]) {
        [self updateIcon];
    }
}

- (void)updateIcon {
    NSDockTile *tile = self.tile;
    if (!tile) return;

    BOOL dark;
    if ([self.style isEqualToString:@"light"]) {
        dark = NO;
    } else if ([self.style isEqualToString:@"dark"]) {
        dark = YES;
    } else {
        NSString *systemStyle = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleInterfaceStyle"];
        dark = [systemStyle isEqualToString:@"Dark"];
    }

    NSString *assetName = dark ? @"BoltZipDockDark" : @"BoltZipDockLight";
    NSURL *assetURL = [self.applicationBundle URLForResource:assetName withExtension:@"png"];
    NSImage *image = assetURL ? [[NSImage alloc] initWithContentsOfURL:assetURL] : nil;
    if (image) {
        NSImageView *view = [[NSImageView alloc] initWithFrame:(NSRect){NSZeroPoint, tile.size}];
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.imageScaling = NSImageScaleProportionallyUpOrDown;
        view.image = image;
        tile.contentView = view;
    } else {
        tile.contentView = nil;
    }
    [tile display];
}

- (void)dealloc {
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}

@end
