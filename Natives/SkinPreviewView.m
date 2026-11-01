#import "SkinPreviewView.h"
#import <math.h>

// Orthographic textured cuboids: no animation loop, GPU context or web service.
// Cards are raster snapshots; only the large preview redraws while dragging.
typedef struct { CGFloat x, y, z; } SkinPoint;
@interface SkinFace : NSObject
@property UIImage *texture;
@property CGPoint a;
@property CGPoint b;
@property CGPoint c;
@property CGFloat depth;
@property CGFloat shade;
@end
@implementation SkinFace
@end

@interface SkinPreviewView () <UIGestureRecognizerDelegate>
@property CGFloat startAngle;
@property(nonatomic,strong) UIButton *rotateLeftButton;
@property(nonatomic,strong) UIButton *rotateRightButton;
@end
@implementation SkinPreviewView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) [self commonInit];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self commonInit];
    return self;
}
- (void)commonInit {
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    _rotationAngle = -0.4;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.delegate = self; [self addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(flip)];
    tap.delegate = self; [self addGestureRecognizer:tap];
    self.rotateLeftButton = [self rotationButton:@"chevron.left" label:@"Rotate skin left" action:@selector(rotateLeft)];
    self.rotateRightButton = [self rotationButton:@"chevron.right" label:@"Rotate skin right" action:@selector(rotateRight)];
}
- (UIButton *)rotationButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 22;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button]; return button;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat y = MAX(0,(self.bounds.size.height-44)/2);
    self.rotateLeftButton.frame = CGRectMake(0,y,44,44);
    self.rotateRightButton.frame = CGRectMake(MAX(0,self.bounds.size.width-44),y,44,44);
}
- (void)rotateLeft { self.rotationAngle -= M_PI/8; }
- (void)rotateRight { self.rotationAngle += M_PI/8; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}
- (void)setSkinImage:(UIImage *)image { _skinImage = image; [self setNeedsDisplay]; }
- (void)setCapeImage:(UIImage *)image { _capeImage = image; [self setNeedsDisplay]; }
- (void)setArmStyle:(SkinArmStyle)style { _armStyle = style; [self setNeedsDisplay]; }
- (void)setRotationAngle:(CGFloat)angle { _rotationAngle = angle; [self setNeedsDisplay]; }
- (void)setIsBackView:(BOOL)back { _isBackView = back; self.rotationAngle = back ? M_PI - 0.4 : -0.4; }
- (void)resetView { self.isBackView = NO; }
- (void)flip { self.isBackView = !self.isBackView; }
- (void)pan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.startAngle = self.rotationAngle;
    self.rotationAngle = self.startAngle + [gesture translationInView:self].x / 100.0;
}
static SkinPoint SkinRotate(SkinPoint p, CGFloat angle) {
    CGFloat x = p.x * cos(angle) + p.z * sin(angle);
    CGFloat z = -p.x * sin(angle) + p.z * cos(angle);
    return (SkinPoint){x, p.y * cos(0.15) - z * sin(0.15), p.y * sin(0.15) + z * cos(0.15)};
}
- (void)addBox:(NSMutableArray<SkinFace *> *)faces image:(UIImage *)image
        origin:(CGPoint)uv size:(SkinPoint)size center:(SkinPoint)center expansion:(CGFloat)extra {
    if (!image.CGImage) return;
    CGFloat x = size.x / 2 + extra, y = size.y / 2 + extra, z = size.z / 2 + extra;
    // Vertices in texture order: top left, top right, bottom left.
    SkinPoint vertices[6][3] = {
        {{-x,y,z},{x,y,z},{-x,-y,z}}, {{-x,y,-z},{-x,y,z},{-x,-y,-z}},
        {{x,y,-z},{-x,y,-z},{x,-y,-z}}, {{x,y,z},{x,y,-z},{x,-y,z}},
        {{-x,y,-z},{x,y,-z},{-x,y,z}}, {{-x,-y,z},{x,-y,z},{-x,-y,-z}}
    };
    SkinPoint normals[6] = {{0,0,1},{-1,0,0},{0,0,-1},{1,0,0},{0,1,0},{0,-1,0}};
    CGFloat u = uv.x, v = uv.y, w = size.x, h = size.y, d = size.z;
    CGRect crops[6] = {CGRectMake(u+d,v+d,w,h), CGRectMake(u,v+d,d,h),
        CGRectMake(u+2*d+w,v+d,w,h), CGRectMake(u+d+w,v+d,d,h),
        CGRectMake(u+d,v,w,d), CGRectMake(u+d+w,v,w,d)};
    for (int i = 0; i < 6; i++) {
        SkinPoint normal = SkinRotate(normals[i], self.rotationAngle);
        if (normal.z <= 0) continue;
        CGRect crop = crops[i];
        if (CGRectGetMaxX(crop) > CGImageGetWidth(image.CGImage) || CGRectGetMaxY(crop) > CGImageGetHeight(image.CGImage)) continue;
        CGImageRef piece = CGImageCreateWithImageInRect(image.CGImage, crop);
        if (!piece) continue;
        SkinFace *face = [SkinFace new];
        face.texture = [UIImage imageWithCGImage:piece];
        CGImageRelease(piece);
        SkinPoint p[3];
        for (int j = 0; j < 3; j++) {
            SkinPoint q = vertices[i][j]; q.x += center.x; q.y += center.y; q.z += center.z;
            p[j] = SkinRotate(q, self.rotationAngle);
        }
        face.a = CGPointMake(p[0].x, -p[0].y); face.b = CGPointMake(p[1].x, -p[1].y); face.c = CGPointMake(p[2].x, -p[2].y);
        face.depth = (p[1].z + p[2].z) / 2;
        face.shade = i == 4 ? 0 : (i == 0 || i == 2 ? 0.04 : 0.20);
        [faces addObject:face];
    }
}
- (void)drawModelInSize:(CGSize)size {
    if (!self.skinImage) return;
    NSMutableArray<SkinFace *> *faces = [NSMutableArray array];
    BOOL modern = CGImageGetHeight(self.skinImage.CGImage) >= 64;
    CGFloat arm = self.armStyle == SkinArmStyleSlim && modern ? 3 : 4;
    SkinPoint dimensions[] = {{8,8,8},{8,12,4},{arm,12,4},{arm,12,4},{4,12,4},{4,12,4}};
    SkinPoint centers[] = {{0,28,0},{0,18,0},{-4-arm/2,18,0},{4+arm/2,18,0},{-2,6,0},{2,6,0}};
    CGPoint base[] = {{0,0},{16,16},{40,16},modern ? CGPointMake(32,48) : CGPointMake(40,16),{0,16},modern ? CGPointMake(16,48) : CGPointMake(0,16)};
    CGPoint overlay[] = {{32,0},{16,32},{40,32},{48,48},{0,32},{0,48}};
    for (int i = 0; i < 6; i++) {
        [self addBox:faces image:self.skinImage origin:base[i] size:dimensions[i] center:centers[i] expansion:0];
        if (modern || i == 0) [self addBox:faces image:self.skinImage origin:overlay[i] size:dimensions[i] center:centers[i] expansion:i == 0 ? 0.5 : 0.25];
    }
    if (self.capeImage) [self addBox:faces image:self.capeImage origin:CGPointZero size:(SkinPoint){10,16,1} center:(SkinPoint){0,16,-3} expansion:0];
    [faces sortUsingComparator:^NSComparisonResult(SkinFace *a, SkinFace *b) {
        return a.depth < b.depth ? NSOrderedAscending : (a.depth > b.depth ? NSOrderedDescending : NSOrderedSame);
    }];
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGFloat scale = MIN(size.width / 27, size.height / 37);
    CGContextTranslateCTM(context, size.width / 2, size.height / 2 + 16 * scale);
    CGContextScaleCTM(context, scale, scale);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    for (SkinFace *face in faces) {
        CGContextSaveGState(context);
        CGAffineTransform t = CGAffineTransformMake(face.b.x-face.a.x, face.b.y-face.a.y,
            face.c.x-face.a.x, face.c.y-face.a.y, face.a.x, face.a.y);
        CGContextConcatCTM(context, t);
        [face.texture drawInRect:CGRectMake(0,0,1,1)];
        CGContextRestoreGState(context);
    }
    CGContextRestoreGState(context);
}
- (void)drawRect:(CGRect)rect { [self drawModelInSize:self.bounds.size]; }
- (UIImage *)generateThumbnailWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [self drawModelInSize:size];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
@end
