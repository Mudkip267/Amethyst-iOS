#import <UIKit/UIKit.h>
#import "SkinModel.h"

@interface SkinEditorViewController : UIViewController

@property (nonatomic, copy) void (^whenSkinAdded)(SkinItem *newSkin);
@property (nonatomic, assign) BOOL importOnOpen;
@property (nonatomic, copy) NSString *accountUsername;
@property (nonatomic, strong) SkinItem *skinToEdit; // nil if adding a new skin

@end
