#import "HorizonRuntime.h"
#import "utils.h"
#include <dlfcn.h>
#include <stdlib.h>

static BOOL runningHorizon;

static NSURL *horizonDataDirectory(void) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [documents URLByAppendingPathComponent:@"Horizon" isDirectory:YES];
}

static NSURL *launchMarker(void) {
    return [horizonDataDirectory() URLByAppendingPathComponent:@".launch-horizon-once"];
}

static NSString *enginePath(void) {
    return [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"libAmethystHorizon.dylib"];
}

static BOOL showFile(NSURL *file) {
    return file != nil && [NSFileManager.defaultManager fileExistsAtPath:file.path];
}

BOOL AMEHorizonAvailable(void) {
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    if (@available(iOS 16.0, *)) {
        NSString *path = enginePath();
        NSString *launcher = [NSBundle.mainBundle.privateFrameworksPath
            stringByAppendingPathComponent:@"HorizonLauncherKit.framework/HorizonLauncherKit"];
        return path && launcher && [NSFileManager.defaultManager fileExistsAtPath:path] &&
            [NSFileManager.defaultManager fileExistsAtPath:launcher];
    }
#endif
    return NO;
}

BOOL AMEHorizonHasGameFiles(void) {
    return showFile([horizonDataDirectory() URLByAppendingPathComponent:@"resources/horizon-resources.json"]);
}

BOOL AMEHorizonLaunchPending(void) {
    return showFile(launchMarker());
}

BOOL AMEHorizonQueueLaunch(NSError **error) {
    NSURL *directory = horizonDataDirectory();
    if (!AMEHorizonAvailable() || !directory) {
        if (error) *error = [NSError errorWithDomain:@"AmethystHorizon" code:1 userInfo:@{
            NSLocalizedDescriptionKey: localize(@"horizon.error.unavailable", nil)
        }];
        return NO;
    }
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [[NSData data] writeToURL:launchMarker() options:NSDataWritingAtomic error:error];
}

BOOL AMEHorizonCancelLaunch(NSError **error) {
    NSURL *marker = launchMarker();
    return !showFile(marker) || [NSFileManager.defaultManager removeItemAtURL:marker error:error];
}

BOOL AMEHorizonRunning(void) {
    return runningHorizon;
}

BOOL AMEHorizonTryBoot(void) {
    if (!AMEHorizonLaunchPending()) return NO;
    // Consume before loading so a failed engine startup cannot trap the user in a crash loop.
    NSError *error = nil;
    if (!AMEHorizonCancelLaunch(&error)) {
        NSLog(@"[Horizon] Could not consume the launch marker: %@", error);
        return NO;
    }
    if (!AMEHorizonAvailable()) return NO;

    void *engine = dlopen(enginePath().fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!engine) {
        NSLog(@"[Horizon] Engine load failed: %s", dlerror());
        return NO;
    }
    void (*start)(void) = (void (*)(void))dlsym(engine, "amethyst_horizon_main");
    if (!start) {
        NSLog(@"[Horizon] Engine is missing its Amethyst entry point");
        return NO;
    }
    const char *directory = horizonDataDirectory().fileSystemRepresentation;
    if (!directory || setenv("AME_HORIZON_DATA_DIR", directory, 1) != 0 ||
        setenv("HORIZON_HOME", directory, 1) != 0) {
        NSLog(@"[Horizon] Could not configure the game data directory");
        return NO;
    }
    runningHorizon = YES;
    start();
    // Do not start a second UIApplicationMain if the native game entry returns.
    return YES;
}

@implementation HorizonProfileViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) self.title = @"Rust/Horizons";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeProfile)];
}

- (void)closeProfile {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return localize(AMEHorizonAvailable() ? @"horizon.detail.restart" : @"horizon.error.unavailable", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Minecraft Java 26.3";
        cell.detailTextLabel.text = @"Horizon • Rust / Metal";
        cell.imageView.image = [UIImage systemImageNamed:@"cpu"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        BOOL pending = AMEHorizonLaunchPending();
        BOOL available = AMEHorizonAvailable();
        cell.textLabel.text = localize(pending ? @"horizon.action.cancel" :
            (AMEHorizonHasGameFiles() ? @"horizon.action.open" : @"horizon.action.install"), nil);
        cell.detailTextLabel.text = localize(pending ? @"horizon.detail.queued" :
            (available ? @"horizon.detail.settings" : @"horizon.error.unavailable"), nil);
        cell.imageView.image = [UIImage systemImageNamed:pending ? @"xmark.circle" : @"play.circle"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.userInteractionEnabled = pending || available;
        cell.textLabel.enabled = pending || available;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row != 1) return;
    BOOL pending = AMEHorizonLaunchPending();
    NSError *error = nil;
    BOOL ok = pending ? AMEHorizonCancelLaunch(&error) : AMEHorizonQueueLaunch(&error);
    [tableView reloadData];
    if (pending && ok) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
        message:ok ? localize(@"horizon.detail.queued", nil) : error.localizedDescription
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
