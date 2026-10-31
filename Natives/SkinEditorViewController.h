#import <UIKit/UIKit.h>
#import "SkinModel.h"

@interface SkinEditorViewController : UIViewController

@property (nonatomic, copy) void (^whenSkinAdded)(SkinItem *newSkin);
@property (nonatomic, strong) SkinItem *skinToEdit; // nil if adding a new skin

@end
