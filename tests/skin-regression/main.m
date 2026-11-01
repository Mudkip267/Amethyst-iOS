#import <UIKit/UIKit.h>
#import "SkinEditorViewController.h"
#import "authenticator/BaseAuthenticator.h"
#import "TestSupport.h"

NSString *localize(NSString *key, NSString *comment) { return comment; }
NSMutableDictionary *parseJSONFromFile(NSString *path) { return nil; }
NSError *saveJSONToFile(NSDictionary *dict, NSString *path) { return nil; }
static BaseAuthenticator *testAccount;
@implementation BaseAuthenticator
+ (BaseAuthenticator *)current { return testAccount; }
+ (void)setCurrent:(BaseAuthenticator *)account { testAccount = account; }
+ (NSDictionary *)tokenDataOfProfile:(NSString *)profile { return nil; }
+ (id)loadSavedName:(NSString *)name { return nil; }
- (id)initWithInput:(NSString *)string { return [super init]; }
- (void)loginWithCallback:(Callback)callback {}
- (void)refreshTokenWithCallback:(Callback)callback {}
- (BOOL)saveChanges { return YES; }
@end
@implementation MicrosoftAuthenticator
+ (void)clearTokenDataOfProfile:(NSString *)profile {}
@end

static NSString *mode;
static NSMutableArray<NSString *> *requests;
static BOOL requestsValid;
static NSInteger reads;
static NSDictionary *Profile(BOOL stale) {
    return @{@"skins":@[@{@"state":@"ACTIVE",@"url":stale ? @"https://textures.minecraft.net/texture/old" : @"https://textures.minecraft.net/texture/new",@"variant":@"CLASSIC"}],
             @"capes":[mode isEqual:@"hide"] ? @[] : @[@{@"state":@"ACTIVE",@"id":@"owned-cape"}]};
}
@interface MockService : NSURLProtocol
@end
@implementation MockService
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; } // No real network in tests.
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *method = self.request.HTTPMethod, *path = self.request.URL.path;
    [requests addObject:[NSString stringWithFormat:@"%@ %@",method,path]];
    requestsValid &= [self.request.URL.host isEqual:@"api.minecraftservices.com"];
    requestsValid &= [[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer test-token"];
    NSInteger status = 200; id response = @{};
    if ([method isEqual:@"POST"]) {
        response = Profile(NO);
        if ([mode isEqual:@"upload-failure"]) status = 401;
    } else if ([method isEqual:@"PUT"]) {
        if ([mode isEqual:@"cape-failure"]) status = 403;
    } else if ([method isEqual:@"GET"]) {
        reads++;
        requestsValid &= self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData;
        requestsValid &= [[self.request valueForHTTPHeaderField:@"Cache-Control"] isEqual:@"no-cache"];
        response = Profile([mode isEqual:@"stale"] || ([mode isEqual:@"eventual"] && reads == 1));
        if ([mode isEqual:@"wrong-cape"]) response = @{@"skins":Profile(NO)[@"skins"],@"capes":@[]};
        if ([mode isEqual:@"malformed"]) response = @{};
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    NSHTTPURLResponse *http = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:http cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static UIImage *Texture(BOOL cape) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(64,cape ? 32 : 64),NO,1);
    if (cape) {
        [UIColor.redColor setFill]; UIRectFill(CGRectMake(1,1,10,16));
        [UIColor.blueColor setFill]; UIRectFill(CGRectMake(12,1,10,16));
    } else {
        [UIColor.greenColor setFill]; UIRectFill(CGRectMake(0,0,64,32));
        // Transparent hat and modern overlays keep a predictable opaque base body.
        CGContextClearRect(UIGraphicsGetCurrentContext(),CGRectMake(32,0,32,16));
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
}
static BOOL CenterIs(UIImage *image, NSInteger component) {
    unsigned char pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel,1,1,8,4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextTranslateCTM(context,-CGImageGetWidth(image.CGImage)/2.0,-CGImageGetHeight(image.CGImage)/2.0);
    CGContextDrawImage(context,CGRectMake(0,0,CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage)),image.CGImage);
    CGContextRelease(context);
    return pixel[component] > 200 && pixel[(component+1)%3] < 30 && pixel[(component+2)%3] < 30;
}
@interface SkinEditorViewController (Testing)
- (void)save;
@end
@interface RegressionApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property SkinItem *skin;
@property NSArray *cases;
@property NSInteger caseIndex;
@end
@implementation RegressionApp
- (void)finish:(NSString *)result {
    [result writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = [UIViewController new]; [self.window makeKeyAndVisible];
    @try {
        SkinPreviewView *preview = [SkinPreviewView new]; preview.skinImage = Texture(NO); preview.capeImage = Texture(YES);
        preview.rotationAngle = M_PI;
        NSCAssert(CenterIs([preview generateThumbnailWithSize:CGSizeMake(270,370)],0),@"Cape outside must show main red artwork, not blue inner face");
        preview.rotationAngle = 0;
        NSCAssert(CenterIs([preview generateThumbnailWithSize:CGSizeMake(270,370)],1),@"Skin torso must occlude cape from front");
        [NSURLProtocol registerClass:MockService.class];
        BaseAuthenticator.current = [BaseAuthenticator new]; BaseAuthenticator.current.authData = [@{@"accessToken":@"test-token",@"username":@"TestPlayer"} mutableCopy];
        CapeItem *cape = [CapeItem new]; cape.capeId = @"owned-cape"; cape.name = @"Owned cape";
        SkinManager.sharedManager.availableCapes = @[cape];
        self.skin = [SkinManager.sharedManager addCustomSkinWithImage:Texture(NO) name:@"Test" armStyle:SkinArmStyleWide capeId:@"owned-cape"];
        self.cases = @[@"success",@"hide",@"stale",@"wrong-cape",@"malformed",@"eventual",@"cape-failure",@"upload-failure"];
        [self next];
    } @catch(NSException *error) { [self finish:[@"FAIL: " stringByAppendingString:error.reason]]; }
    return YES;
}
- (void)next {
    if (self.caseIndex == self.cases.count) { [self testEditorSave]; return; }
    mode = self.cases[self.caseIndex++]; requests = [NSMutableArray array]; reads = 0; requestsValid = YES;
    self.skin.capeId = [mode isEqual:@"hide"] ? @"none" : @"owned-cape";
    [SkinManager.sharedManager applyOnlineSkin:self.skin completion:^(NSError *error) {
        @try {
            BOOL succeeds = [@[@"success",@"hide",@"eventual"] containsObject:mode];
            NSCAssert((error == nil) == succeeds,@"Unexpected confirmation result for %@: %@",mode,error);
            NSCAssert(requestsValid,@"Wrong auth or cached confirmation read");
            NSCAssert([requests.firstObject isEqual:@"POST /minecraft/profile/skins"],@"Missing skin upload");
            if ([mode isEqual:@"upload-failure"]) NSCAssert(requests.count == 1,@"Do not modify cape after upload fails");
            else {
                NSCAssert([requests[1] isEqual:[mode isEqual:@"hide"] ? @"DELETE /minecraft/profile/capes/active" : @"PUT /minecraft/profile/capes/active"],@"Wrong cape update");
                NSCAssert(requests.count == 2+reads,@"Mutations must never be retried");
                if ([mode isEqual:@"cape-failure"]) NSCAssert(reads == 0 && [error.localizedDescription containsString:@"Skin uploaded"],@"Surface partial update");
                else NSCAssert(reads == ([mode isEqual:@"eventual"] ? 2 : succeeds ? 1 : 3),@"Unexpected confirmation retry count");
            }
            [self next];
        } @catch(NSException *failure) { [self finish:[@"FAIL: " stringByAppendingString:failure.reason]]; }
    }];
}
- (void)testEditorSave {
    mode = @"success"; requests = [NSMutableArray array]; reads = 0; requestsValid = YES;
    self.skin.capeId = @"owned-cape";
    SkinEditorViewController *editor = [SkinEditorViewController new]; editor.skinToEdit = self.skin; editor.accountUsername = @"TestPlayer";
    [editor loadViewIfNeeded];
    editor.whenSkinAdded = ^(SkinItem *saved) {
        @try {
            NSCAssert(requestsValid && requests.count == 3 && reads == 1,@"Save must publish and confirm without separate Apply");
            NSCAssert([[SkinManager.sharedManager activeSkinForAccount:@"TestPlayer"].capeId isEqual:@"owned-cape"],@"Persist confirmed selection locally");
            [self finish:@"PASS: cape artwork and front occlusion; publish/show/hide; stale skin, wrong cape and malformed responses rejected; read retry only; partial failure; editor Save publishes and confirms."];
        } @catch(NSException *error) { [self finish:[@"FAIL: " stringByAppendingString:error.reason]]; }
    };
    [editor save];
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(RegressionApp.class)); } }
