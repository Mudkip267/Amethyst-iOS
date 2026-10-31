#import "SkinModel.h"
#import "utils.h"

@implementation SkinItem

- (UIImage *)loadImage {
    if (self.skinPath && [[NSFileManager defaultManager] fileExistsAtPath:self.skinPath]) {
        return [UIImage imageWithContentsOfFile:self.skinPath];
    }
    // Check in bundle
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:self.name.lowercaseString ofType:@"png" inDirectory:@"skins"];
    if (bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        return [UIImage imageWithContentsOfFile:bundlePath];
    }
    // Fallback to steve
    NSString *stevePath = [[NSBundle mainBundle] pathForResource:@"steve" ofType:@"png" inDirectory:@"skins"];
    if (stevePath) {
        return [UIImage imageWithContentsOfFile:stevePath];
    }
    return nil;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.skinId ?: @"",
        @"name": self.name ?: @"",
        @"armStyle": @(self.armStyle),
        @"skinPath": self.skinPath ?: @"",
        @"capeId": self.capeId ?: @"",
        @"isCustom": @(self.isCustom)
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    SkinItem *item = [[SkinItem alloc] init];
    item.skinId = dict[@"id"];
    item.name = dict[@"name"];
    item.armStyle = [dict[@"armStyle"] integerValue];
    item.skinPath = dict[@"skinPath"];
    item.capeId = dict[@"capeId"];
    item.isCustom = [dict[@"isCustom"] boolValue];
    return item;
}

@end

@implementation CapeItem

- (UIImage *)loadImage {
    if (!self.capePath || self.capePath.length == 0) return nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.capePath]) {
        return [UIImage imageWithContentsOfFile:self.capePath];
    }
    NSString *nameOnly = [self.capePath lastPathComponent];
    NSString *nameNoExt = [nameOnly stringByDeletingPathExtension];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:nameNoExt ofType:@"png" inDirectory:@"skins"];
    if (bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        return [UIImage imageWithContentsOfFile:bundlePath];
    }
    return nil;
}

@end

@interface SkinManager ()
@property (nonatomic, copy) NSString *skinsDirectory;
@property (nonatomic, copy) NSString *configFile;
@property (nonatomic, strong) NSMutableDictionary *accountActiveSkins;
@end

@implementation SkinManager

+ (instancetype)sharedManager {
    static SkinManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SkinManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        const char *ameHome = getenv("AME_HOME");
        if (ameHome && *ameHome) {
            _skinsDirectory = [NSString stringWithFormat:@"%s/skins", ameHome];
        } else {
            NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            _skinsDirectory = [doc stringByAppendingPathComponent:@"skins"];
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:_skinsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        _configFile = [_skinsDirectory stringByAppendingPathComponent:@"skins_data.json"];
        _savedSkins = [NSMutableArray array];
        _accountActiveSkins = [NSMutableDictionary dictionary];

        [self setupDefaultCapes];
        [self setupDefaultSkins];
        [self reload];
    }
    return self;
}

- (void)setupDefaultCapes {
    NSMutableArray *capes = [NSMutableArray array];

    CapeItem *none = [[CapeItem alloc] init];
    none.capeId = @"none";
    none.name = localize(@"skin.cape.none", @"Use default cape");
    none.capePath = @"";
    [capes addObject:none];

    NSArray *capeDefs = @[
        @{@"id": @"creeper", @"name": @"Creeper Cape", @"file": @"creeper_cape.png"},
        @{@"id": @"cherry", @"name": @"Cherry Blossom", @"file": @"cherry_cape.png"},
        @{@"id": @"migrator", @"name": @"Migrator Cape", @"file": @"migrator_cape.png"},
        @{@"id": @"vanilla", @"name": @"Vanilla Cape", @"file": @"vanilla_cape.png"},
        @{@"id": @"pancape", @"name": @"Pancape", @"file": @"pancape.png"}
    ];

    for (NSDictionary *def in capeDefs) {
        CapeItem *c = [[CapeItem alloc] init];
        c.capeId = def[@"id"];
        c.name = def[@"name"];
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:[def[@"file"] stringByDeletingPathExtension] ofType:@"png" inDirectory:@"skins"];
        c.capePath = bundlePath ?: [self.skinsDirectory stringByAppendingPathComponent:def[@"file"]];
        [capes addObject:c];
    }

    _availableCapes = [capes copy];
}

- (void)setupDefaultSkins {
    NSMutableArray *defaults = [NSMutableArray array];

    NSArray *skinDefs = @[
        @{@"name": @"Steve", @"arm": @(SkinArmStyleWide), @"file": @"steve.png"},
        @{@"name": @"Alex", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Ari", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Makena", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Noor", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Sunny", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Zuri", @"arm": @(SkinArmStyleWide), @"file": @"steve.png"},
        @{@"name": @"Kai", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Efe", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"}
    ];

    for (NSDictionary *def in skinDefs) {
        SkinItem *item = [[SkinItem alloc] init];
        item.skinId = [NSString stringWithFormat:@"default_%@", [def[@"name"] lowercaseString]];
        item.name = def[@"name"];
        item.armStyle = [def[@"arm"] integerValue];
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:[def[@"file"] stringByDeletingPathExtension] ofType:@"png" inDirectory:@"skins"];
        item.skinPath = bundlePath ?: [self.skinsDirectory stringByAppendingPathComponent:def[@"file"]];
        item.capeId = @"none";
        item.isCustom = NO;
        [defaults addObject:item];
    }

    _defaultSkins = [defaults copy];
}

- (void)reload {
    [self.savedSkins removeAllObjects];
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.configFile]) {
        NSData *data = [NSData dataWithContentsOfFile:self.configFile];
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSArray *savedArray = json[@"savedSkins"];
                if ([savedArray isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *dict in savedArray) {
                        if ([dict isKindOfClass:[NSDictionary class]]) {
                            [self.savedSkins addObject:[SkinItem fromDictionary:dict]];
                        }
                    }
                }
                NSDictionary *activeDict = json[@"activeSkins"];
                if ([activeDict isKindOfClass:[NSDictionary class]]) {
                    [self.accountActiveSkins setDictionary:activeDict];
                }
            }
        }
    }
}

- (void)saveConfig {
    NSMutableArray *savedArray = [NSMutableArray array];
    for (SkinItem *item in self.savedSkins) {
        [savedArray addObject:[item toDictionary]];
    }
    NSDictionary *json = @{
        @"savedSkins": savedArray,
        @"activeSkins": self.accountActiveSkins
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:self.configFile atomically:YES];
    }
}

- (CapeItem *)capeForId:(NSString *)capeId {
    if (!capeId || [capeId isEqualToString:@"none"] || capeId.length == 0) return nil;
    for (CapeItem *c in self.availableCapes) {
        if ([c.capeId isEqualToString:capeId]) return c;
    }
    return nil;
}

- (SkinItem *)activeSkinForAccount:(NSString *)username {
    if (!username || username.length == 0) username = @"default";
    NSString *skinId = self.accountActiveSkins[username];
    if (skinId) {
        for (SkinItem *item in self.savedSkins) {
            if ([item.skinId isEqualToString:skinId]) return item;
        }
        for (SkinItem *item in self.defaultSkins) {
            if ([item.skinId isEqualToString:skinId]) return item;
        }
    }
    return self.defaultSkins.firstObject;
}

- (void)setActiveSkin:(SkinItem *)skin forAccount:(NSString *)username {
    if (!username || username.length == 0) username = @"default";
    if (!skin) return;

    self.accountActiveSkins[username] = skin.skinId;
    [self saveConfig];

    // Export active skin and cape to game directory
    UIImage *skinImg = [skin loadImage];
    if (skinImg) {
        NSData *pngData = UIImagePNGRepresentation(skinImg);
        NSString *activePath = [self.skinsDirectory stringByAppendingPathComponent:@"active_skin.png"];
        [pngData writeToFile:activePath atomically:YES];

        // Generate avatar head and update account file
        UIImage *headImg = [self generateAvatarHeadFromSkin:skinImg];
        if (headImg) {
            NSString *headPath = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"head_%@.png", username]];
            [UIImagePNGRepresentation(headImg) writeToFile:headPath atomically:YES];

            // Update account JSON profilePicURL if account exists
            const char *ameHome = getenv("AME_HOME");
            if (ameHome && *ameHome) {
                NSString *accPath = [NSString stringWithFormat:@"%s/accounts/%@.json", ameHome, username];
                if ([[NSFileManager defaultManager] fileExistsAtPath:accPath]) {
                    NSMutableDictionary *accData = parseJSONFromFile(accPath);
                    if (accData && [accData isKindOfClass:[NSMutableDictionary class]]) {
                        accData[@"profilePicURL"] = [NSURL fileURLWithPath:headPath].absoluteString;
                        saveJSONToFile(accData, accPath);
                    }
                }
            }
        }
    }

    CapeItem *cape = [self capeForId:skin.capeId];
    if (cape) {
        UIImage *capeImg = [cape loadImage];
        if (capeImg) {
            NSString *activeCapePath = [self.skinsDirectory stringByAppendingPathComponent:@"active_cape.png"];
            [UIImagePNGRepresentation(capeImg) writeToFile:activeCapePath atomically:YES];
        }
    } else {
        NSString *activeCapePath = [self.skinsDirectory stringByAppendingPathComponent:@"active_cape.png"];
        [[NSFileManager defaultManager] removeItemAtPath:activeCapePath error:nil];
    }
}

- (SkinItem *)addCustomSkinWithImage:(UIImage *)image name:(NSString *)name armStyle:(SkinArmStyle)armStyle capeId:(NSString *)capeId {
    if (!image) return nil;
    NSString *skinId = [[NSUUID UUID] UUIDString];
    NSString *fileName = [NSString stringWithFormat:@"custom_%@.png", skinId];
    NSString *filePath = [self.skinsDirectory stringByAppendingPathComponent:fileName];

    NSData *data = UIImagePNGRepresentation(image);
    [data writeToFile:filePath atomically:YES];

    SkinItem *item = [[SkinItem alloc] init];
    item.skinId = skinId;
    item.name = (name && name.length > 0) ? name : [NSString stringWithFormat:@"Custom Skin %lu", (unsigned long)(self.savedSkins.count + 1)];
    item.armStyle = armStyle;
    item.skinPath = filePath;
    item.capeId = capeId ?: @"none";
    item.isCustom = YES;

    [self.savedSkins addObject:item];
    [self saveConfig];
    return item;
}

- (void)deleteCustomSkin:(SkinItem *)skin {
    if (!skin || !skin.isCustom) return;
    if (skin.skinPath && [[NSFileManager defaultManager] fileExistsAtPath:skin.skinPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:skin.skinPath error:nil];
    }
    [self.savedSkins removeObject:skin];
    [self saveConfig];
}

- (UIImage *)generateAvatarHeadFromSkin:(UIImage *)skinImage {
    if (!skinImage) return nil;
    CGImageRef src = skinImage.CGImage;
    if (!src) return nil;

    CGSize targetSize = CGSizeMake(120, 120);
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);

    // Draw Head base (8, 8, 8, 8)
    CGImageRef head = CGImageCreateWithImageInRect(src, CGRectMake(8, 8, 8, 8));
    if (head) {
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, targetSize.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, targetSize.width, targetSize.height), head);
        CGContextRestoreGState(ctx);
        CGImageRelease(head);
    }

    // Draw Hat layer (40, 8, 8, 8)
    CGImageRef hat = CGImageCreateWithImageInRect(src, CGRectMake(40, 8, 8, 8));
    if (hat) {
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, targetSize.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, targetSize.width, targetSize.height), hat);
        CGContextRestoreGState(ctx);
        CGImageRelease(hat);
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

@end
