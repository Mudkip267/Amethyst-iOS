#import "SkinPreviewView.h"

@interface SkinPreviewView () {
    UIPanGestureRecognizer *_panGesture;
    UITapGestureRecognizer *_tapGesture;
    CGFloat _startAngle;
}
@end

@implementation SkinPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = YES;
    self.contentMode = UIViewContentModeRedraw;
    self.clipsToBounds = NO;
    _armStyle = SkinArmStyleWide;
    _isBackView = NO;
    _rotationAngle = 0.0;

    _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:_panGesture];

    _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:_tapGesture];
}

- (void)setSkinImage:(UIImage *)skinImage {
    _skinImage = skinImage;
    [self setNeedsDisplay];
}

- (void)setCapeImage:(UIImage *)capeImage {
    _capeImage = capeImage;
    [self setNeedsDisplay];
}

- (void)setArmStyle:(SkinArmStyle)armStyle {
    _armStyle = armStyle;
    [self setNeedsDisplay];
}

- (void)setIsBackView:(BOOL)isBackView {
    _isBackView = isBackView;
    _rotationAngle = isBackView ? M_PI : 0.0;
    [self setNeedsDisplay];
}

- (void)setRotationAngle:(CGFloat)rotationAngle {
    _rotationAngle = rotationAngle;
    // Normalize to 0 .. 2*PI
    while (_rotationAngle < 0) _rotationAngle += 2 * M_PI;
    while (_rotationAngle >= 2 * M_PI) _rotationAngle -= 2 * M_PI;
    _isBackView = (_rotationAngle > M_PI_2 && _rotationAngle < 3 * M_PI_2);
    [self setNeedsDisplay];
}

- (void)resetView {
    _rotationAngle = 0.0;
    _isBackView = NO;
    [self setNeedsDisplay];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        _startAngle = self.rotationAngle;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self];
        CGFloat deltaAngle = (translation.x / self.bounds.size.width) * (2 * M_PI);
        self.rotationAngle = _startAngle + deltaAngle;
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    // Tap flips front / back
    self.isBackView = !self.isBackView;
}

static CGImageRef sliceImage(CGImageRef src, CGRect rect) {
    if (!src) return NULL;
    return CGImageCreateWithImageInRect(src, rect);
}

static void drawSubRect(CGContextRef ctx, CGImageRef img, CGRect srcRect, CGRect dstRect) {
    if (!img) return;
    CGImageRef sub = sliceImage(img, srcRect);
    if (!sub) return;
    CGContextSaveGState(ctx);
    // CoreGraphics flips Y
    CGContextTranslateCTM(ctx, dstRect.origin.x, dstRect.origin.y + dstRect.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, dstRect.size.width, dstRect.size.height), sub);
    CGContextRestoreGState(ctx);
    CGImageRelease(sub);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);

    CGFloat viewW = self.bounds.size.width;
    CGFloat viewH = self.bounds.size.height;

    // Character dimensions in Minecraft pixels:
    // Head: 8 x 8
    // Body: 8 x 12
    // Arms: (4 or 3) x 12
    // Legs: 4 x 12 each -> 8 x 12 total
    // Total width = 8 (body) + 2 * 4 (arms) = 16 (or 14 for slim)
    // Total height = 8 (head) + 12 (body) + 12 (legs) = 32
    CGFloat armW_mc = (self.armStyle == SkinArmStyleSlim) ? 3.0 : 4.0;
    CGFloat totalW_mc = 8.0 + armW_mc * 2.0;
    CGFloat totalH_mc = 32.0;

    CGFloat scale = MIN((viewW * 0.75) / totalW_mc, (viewH * 0.78) / totalH_mc);
    if (scale <= 0) scale = 4.0;

    CGFloat charW = totalW_mc * scale;
    CGFloat charH = totalH_mc * scale;
    CGFloat startX = (viewW - charW) / 2.0;
    CGFloat startY = (viewH - charH) / 2.0 - 5.0;

    // Draw circular ground shadow
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.25].CGColor);
    CGRect shadowRect = CGRectMake(startX - 10, startY + charH - 4, charW + 20, 16);
    CGContextFillEllipseInRect(ctx, shadowRect);
    CGContextRestoreGState(ctx);

    CGImageRef skinCG = self.skinImage.CGImage;
    CGImageRef capeCG = self.capeImage.CGImage;

    CGFloat armW_pt = armW_mc * scale;
    CGFloat bodyW_pt = 8.0 * scale;
    CGFloat headSize_pt = 8.0 * scale;
    CGFloat torsoH_pt = 12.0 * scale;
    CGFloat legH_pt = 12.0 * scale;
    CGFloat legW_pt = 4.0 * scale;

    CGFloat headX = startX + armW_pt;
    CGFloat headY = startY;
    CGFloat bodyX = startX + armW_pt;
    CGFloat bodyY = startY + headSize_pt;
    CGFloat leftArmX = startX;
    CGFloat rightArmX = startX + armW_pt + bodyW_pt;
    CGFloat armY = bodyY;
    CGFloat legY = bodyY + torsoH_pt;
    CGFloat leftLegX = bodyX;
    CGFloat rightLegX = bodyX + legW_pt;

    BOOL back = self.isBackView;

    // If back view and cape is equipped: draw cape first or over body
    if (back && capeCG) {
        // Cape back is 10 x 16 (mc pixels)
        CGFloat capeW_pt = 10.0 * scale;
        CGFloat capeH_pt = 16.0 * scale;
        CGFloat capeX = startX + (charW - capeW_pt) / 2.0;
        CGFloat capeY = bodyY + 1.0 * scale;
        drawSubRect(ctx, capeCG, CGRectMake(1, 1, 10, 16), CGRectMake(capeX, capeY, capeW_pt, capeH_pt));
    }

    if (skinCG) {
        if (!back) {
            // FRONT VIEW
            // 1. Legs
            // Right leg front: (4, 20, 4, 12), pants: (4, 36, 4, 12)
            drawSubRect(ctx, skinCG, CGRectMake(4, 20, 4, 12), CGRectMake(leftLegX, legY, legW_pt, legH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(4, 36, 4, 12), CGRectMake(leftLegX, legY, legW_pt, legH_pt));

            // Left leg front: (20, 52, 4, 12), pants: (4, 52, 4, 12)
            drawSubRect(ctx, skinCG, CGRectMake(20, 52, 4, 12), CGRectMake(rightLegX, legY, legW_pt, legH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(4, 52, 4, 12), CGRectMake(rightLegX, legY, legW_pt, legH_pt));

            // 2. Torso
            // Front: (20, 20, 8, 12), jacket: (20, 36, 8, 12)
            drawSubRect(ctx, skinCG, CGRectMake(20, 20, 8, 12), CGRectMake(bodyX, bodyY, bodyW_pt, torsoH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(20, 36, 8, 12), CGRectMake(bodyX, bodyY, bodyW_pt, torsoH_pt));

            // 3. Right Arm (character's right, screen's left)
            CGFloat armSliceW = (self.armStyle == SkinArmStyleSlim) ? 3 : 4;
            drawSubRect(ctx, skinCG, CGRectMake(44, 20, armSliceW, 12), CGRectMake(leftArmX, armY, armW_pt, torsoH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(44, 36, armSliceW, 12), CGRectMake(leftArmX, armY, armW_pt, torsoH_pt));

            // 4. Left Arm (character's left, screen's right)
            drawSubRect(ctx, skinCG, CGRectMake(36, 52, armSliceW, 12), CGRectMake(rightArmX, armY, armW_pt, torsoH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(52, 52, armSliceW, 12), CGRectMake(rightArmX, armY, armW_pt, torsoH_pt));

            // 5. Head & Hat
            // Head front: (8, 8, 8, 8), Hat front: (40, 8, 8, 8)
            drawSubRect(ctx, skinCG, CGRectMake(8, 8, 8, 8), CGRectMake(headX, headY, headSize_pt, headSize_pt));
            drawSubRect(ctx, skinCG, CGRectMake(40, 8, 8, 8), CGRectMake(headX, headY, headSize_pt, headSize_pt));
        } else {
            // BACK VIEW
            // 1. Legs back
            drawSubRect(ctx, skinCG, CGRectMake(12, 20, 4, 12), CGRectMake(rightLegX, legY, legW_pt, legH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(12, 36, 4, 12), CGRectMake(rightLegX, legY, legW_pt, legH_pt));

            drawSubRect(ctx, skinCG, CGRectMake(28, 52, 4, 12), CGRectMake(leftLegX, legY, legW_pt, legH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(12, 52, 4, 12), CGRectMake(leftLegX, legY, legW_pt, legH_pt));

            // 2. Torso back (if no cape or partially visible)
            if (!capeCG) {
                drawSubRect(ctx, skinCG, CGRectMake(32, 20, 8, 12), CGRectMake(bodyX, bodyY, bodyW_pt, torsoH_pt));
                drawSubRect(ctx, skinCG, CGRectMake(32, 36, 8, 12), CGRectMake(bodyX, bodyY, bodyW_pt, torsoH_pt));
            }

            // 3. Arms back
            CGFloat armSliceW = (self.armStyle == SkinArmStyleSlim) ? 3 : 4;
            drawSubRect(ctx, skinCG, CGRectMake(52, 20, armSliceW, 12), CGRectMake(rightArmX, armY, armW_pt, torsoH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(52, 36, armSliceW, 12), CGRectMake(rightArmX, armY, armW_pt, torsoH_pt));

            drawSubRect(ctx, skinCG, CGRectMake(44, 52, armSliceW, 12), CGRectMake(leftArmX, armY, armW_pt, torsoH_pt));
            drawSubRect(ctx, skinCG, CGRectMake(60, 52, armSliceW, 12), CGRectMake(leftArmX, armY, armW_pt, torsoH_pt));

            // 4. Head back
            drawSubRect(ctx, skinCG, CGRectMake(24, 8, 8, 8), CGRectMake(headX, headY, headSize_pt, headSize_pt));
            drawSubRect(ctx, skinCG, CGRectMake(56, 8, 8, 8), CGRectMake(headX, headY, headSize_pt, headSize_pt));
        }
    }
}

- (UIImage *)generateThumbnailWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect prevBounds = self.bounds;
    self.bounds = CGRectMake(0, 0, size.width, size.height);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    self.bounds = prevBounds;
    return thumbnail;
}

@end
