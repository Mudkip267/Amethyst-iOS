#import <UIKit/UIKit.h>
#import "SkinModel.h"

@interface SkinManagerViewController : UIViewController

@property (nonatomic, copy) NSString *currentAccountUsername;
@property (nonatomic, copy) void (^whenSkinChanged)(SkinItem *activeSkin);

@end
