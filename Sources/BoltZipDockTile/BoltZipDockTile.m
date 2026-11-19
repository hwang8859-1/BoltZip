#import <AppKit/AppKit.h>

static NSString * const StyleKey = @"BoltZip.AppIconStyle";
static NSString * const StyleChangedNotification = @"dev.boltzip.macos.dockIconStyleDidChange";

@interface BoltZipDockTile : NSObject <NSDockTilePlugIn>
@property (nonatomic, strong) NSDockTile *tile;
@property (nonatomic, strong) NSBundle *applicationBundle;

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
    [self updateIcon:style];

    [notifications addObserver:self
                       selector:@selector(styleChanged:)
                           name:StyleChangedNotification
                         object:identifier
             suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

- (void)styleChanged:(NSNotification *)note {
    id style = note.userInfo[StyleKey];
    [self updateIcon:[style isKindOfClass:NSString.class] ? style : nil];
}

- (void)updateIcon:(NSString *)style {
    NSDockTile *tile = self.tile;
    if (!tile) return;

    NSString *assetName = nil;
    if ([style isEqualToString:@"light"]) assetName = @"BoltZipDockLight";
    if ([style isEqualToString:@"dark"]) assetName = @"BoltZipDockDark";
    NSURL *assetURL = assetName ? [self.applicationBundle URLForResource:assetName withExtension:@"png"] : nil;
    NSImage *image = assetURL ? [[NSImage alloc] initWithContentsOfURL:assetURL] : nil;
    if (image) {
        NSRect tileRect = (NSRect){NSZeroPoint, tile.size};
        NSView *content = [[NSView alloc] initWithFrame:tileRect];
        content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSRect iconRect = NSInsetRect(tileRect, tile.size.width * 0.045, tile.size.height * 0.045);
        NSImageView *view = [[NSImageView alloc] initWithFrame:iconRect];
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.imageScaling = NSImageScaleProportionallyUpOrDown;
        view.image = image;
        [content addSubview:view];
        tile.contentView = content;
    } else {
        tile.contentView = nil;
    }
    [tile display];
}

- (void)dealloc {
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}

@end
