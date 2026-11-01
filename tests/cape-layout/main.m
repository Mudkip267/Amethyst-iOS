#import <UIKit/UIKit.h>
#import "CapeCardUnderTest.h"
@interface RegressionApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation RegressionApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSString *result = @"PASS: cape layout remains inside each card for 21 cape indices, portrait, landscape and repeated resizing.";
    @try {
        // Confirm UIKit's self-first tag lookup reproduces the original cause.
        UIButton *legacy = [UIButton new]; legacy.tag = 1;
        UIView *child = [UIView new]; child.tag = 1; [legacy addSubview:child];
        NSCAssert([legacy viewWithTag:1] == legacy, @"Expected original tag collision");
        for (NSInteger index = 0; index < 21; index++) {
            SkinCapeCard *card = [SkinCapeCard buttonWithType:UIButtonTypeCustom]; card.tag = index;
            card.picture = [UIImageView new]; card.picture.tag = 1; [card addSubview:card.picture];
            card.nameLabel = [UILabel new]; card.nameLabel.tag = 2; [card addSubview:card.nameLabel];
            card.emptyLabel = [UILabel new]; card.emptyLabel.tag = 3; [card addSubview:card.emptyLabel];
            for (NSNumber *width in @[@390,@844,@430,@932,@390]) {
                CGFloat w = width.doubleValue > 620 ? 144 : (width.doubleValue-44)/2;
                CGRect frame = CGRectMake(16+(index%2)*(w+12),516+(index/2)*(w*1.4+66),w,w*1.4+54);
                card.frame = frame; [card setNeedsLayout]; [card layoutIfNeeded];
                NSCAssert(CGRectEqualToRect(card.frame,frame), @"Child layout moved the cape card");
                for (UIView *part in @[card.picture,card.nameLabel,card.emptyLabel]) {
                    NSCAssert(CGRectContainsRect(card.bounds,part.frame), @"Cape content escaped the card");
                    NSCAssert(part.superview == card, @"Missing card child");
                }
                NSCAssert(card.tag == index, @"Selection index changed");
            }
        }
    } @catch(NSException *error) { result = [@"FAIL: " stringByAppendingString:error.reason]; }
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [UIViewController new]; self.window.rootViewController = controller;
    [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(RegressionApp.class)); } }
