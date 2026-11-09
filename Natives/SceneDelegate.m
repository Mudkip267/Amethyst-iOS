#import "SceneDelegate.h"
#import "HorizonRuntime.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

extern UIWindow *mainWindow;

@interface SceneDelegate ()
@property(nonatomic, strong) id<UIWindowSceneDelegate> horizonScene;
@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (AMEHorizonRunning()) {
        self.horizonScene = [NSClassFromString(@"WinitSceneDelegate") new];
        [self.horizonScene scene:scene willConnectToSession:session options:connectionOptions];
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    mainWindow = self.window;
    launchInitialViewController(self.window);
    [self.window makeKeyAndVisible];
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    [self.horizonScene sceneDidDisconnect:scene];
    self.horizonScene = nil;
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self.horizonScene sceneDidBecomeActive:scene];
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}


- (void)sceneWillResignActive:(UIScene *)scene {
    [self.horizonScene sceneWillResignActive:scene];
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    [self.horizonScene sceneWillEnterForeground:scene];
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    if (AMEHorizonRunning()) {
        [self.horizonScene sceneDidEnterBackground:scene];
        return;
    }
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
    CallbackBridge_pauseGameIfNeed();
}

@end
