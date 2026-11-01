#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SkinArmStyle) {
    SkinArmStyleWide = 0, // Classic 4px (Steve)
    SkinArmStyleSlim = 1  // Slim 3px (Alex)
};

@interface SkinPreviewView : UIView

@property (nonatomic, strong) UIImage *skinImage;
@property (nonatomic, strong) UIImage *capeImage;
@property (nonatomic, assign) SkinArmStyle armStyle;
@property (nonatomic, assign) BOOL isBackView;
@property (nonatomic, assign) CGFloat rotationAngle; // in radians, allows 360-degree rotation

- (instancetype)initWithFrame:(CGRect)frame;
- (void)resetView;
- (UIImage *)generateThumbnailWithSize:(CGSize)size;

@end
