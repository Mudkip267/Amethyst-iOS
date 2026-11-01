#import "SkinModel.h"
#import "utils.h"
#import "authenticator/BaseAuthenticator.h"

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
        @"replacementSlot": self.replacementSlot ?: @"",
        @"name": self.name ?: @"",
        @"armStyle": @(self.armStyle),
        @"skinPath": self.skinPath ?: @"",
        @"capeId": self.capeId ?: @"",
        @"isCustom": @(self.isCustom)
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    SkinItem *item = [[SkinItem alloc] init];
    item.skinId = [dict[@"id"] isKindOfClass:NSString.class] ? dict[@"id"] : NSUUID.UUID.UUIDString;
    item.replacementSlot = [dict[@"replacementSlot"] isKindOfClass:NSString.class] ? dict[@"replacementSlot"] : @"";
    item.name = [dict[@"name"] isKindOfClass:NSString.class] ? dict[@"name"] : @"Skin";
    item.armStyle = [dict[@"armStyle"] isKindOfClass:NSNumber.class] && [dict[@"armStyle"] integerValue] == 1 ? SkinArmStyleSlim : SkinArmStyleWide;
    item.skinPath = [dict[@"skinPath"] isKindOfClass:NSString.class] ? dict[@"skinPath"] : @"";
    item.capeId = [dict[@"capeId"] isKindOfClass:NSString.class] ? dict[@"capeId"] : @"none";
    item.isCustom = [dict[@"isCustom"] isKindOfClass:NSNumber.class] && [dict[@"isCustom"] boolValue];
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


// Requests run only on a worker queue. Tokens are never used for texture requests.
static NSData *SkinRequest(NSString *url, NSString *method, NSData *body, NSString *type, NSString *token, NSError **error) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = method;
    request.timeoutInterval = 25;
    request.HTTPBody = body;
    if (type) [request setValue:type forHTTPHeaderField:@"Content-Type"];
    if (token.length) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *result;
    __block NSError *failure;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        failure = err;
        if (!failure && (status < 200 || status >= 300)) {
            failure = [NSError errorWithDomain:@"MinecraftProfile" code:status userInfo:@{NSLocalizedDescriptionKey: status == 401 ? @"Session expired. Sign in again to change your skin or cape." : [NSString stringWithFormat:@"Minecraft service returned HTTP %ld. Please try again.", (long)status]}];
        }
        result = data;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (error) *error = failure;
    return failure ? nil : result;
}
static NSString *SkinToken(BaseAuthenticator *account) {
    NSString *token = account.authData[@"accessToken"];
    if (!token.length && [account isKindOfClass:MicrosoftAuthenticator.class] && [account.authData[@"xuid"] isKindOfClass:NSString.class]) token = [MicrosoftAuthenticator tokenDataOfProfile:account.authData[@"xuid"]][@"accessToken"];
    return [token isEqualToString:@"offline"] ? nil : token;
}
static UIImage *SkinTexture(id url) {
    if (![url isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    if (![parts.host.lowercaseString isEqualToString:@"textures.minecraft.net"]) return nil;
    parts.scheme = @"https";
    NSData *data = SkinRequest(parts.URL.absoluteString, @"GET", nil, nil, nil, nil);
    return data ? [UIImage imageWithData:data] : nil;
}
- (void)fetchProfile:(void (^)(SkinItem *, NSError *))completion {
    BaseAuthenticator *account = BaseAuthenticator.current;
    NSString *token = SkinToken(account);
    [self setupDefaultCapes];
    if (!token.length) {
        completion(nil, [NSError errorWithDomain:@"MinecraftProfile" code:401 userInfo:@{NSLocalizedDescriptionKey:@"Sign in to a Microsoft account to load owned capes and change your Minecraft skin."}]);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSData *data = SkinRequest(@"https://api.minecraftservices.com/minecraft/profile", @"GET", nil, nil, token, &error);
        NSDictionary *profile = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if (profile && ![profile isKindOfClass:NSDictionary.class]) profile = nil;
        if (!profile && !error) error = [NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Invalid Minecraft profile response."}];
        NSMutableArray *capes = [NSMutableArray array];
        CapeItem *none = [CapeItem new]; none.capeId = @"none"; none.name = @"No cape"; [capes addObject:none];
        NSString *activeCape = @"none";
        NSArray *owned = [profile[@"capes"] isKindOfClass:NSArray.class] ? profile[@"capes"] : @[];
        for (NSDictionary *entry in owned) {
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSString.class]) continue;
            CapeItem *cape = [CapeItem new]; cape.capeId = entry[@"id"]; cape.name = [entry[@"alias"] isKindOfClass:NSString.class] ? entry[@"alias"] : @"Cape";
            UIImage *image = SkinTexture(entry[@"url"]);
            cape.capePath = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"cape_%@.png", [[NSUUID alloc] initWithUUIDString:cape.capeId].UUIDString ?: NSUUID.UUID.UUIDString]];
            if (image) [UIImagePNGRepresentation(image) writeToFile:cape.capePath atomically:YES];
            [capes addObject:cape];
            if ([entry[@"state"] isEqual:@"ACTIVE"]) activeCape = cape.capeId;
        }
        SkinItem *skin = nil;
        NSArray *skins = [profile[@"skins"] isKindOfClass:NSArray.class] ? profile[@"skins"] : @[];
        for (NSDictionary *entry in skins) {
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            if (![entry[@"state"] isEqual:@"ACTIVE"]) continue;
            UIImage *image = SkinTexture(entry[@"url"]);
            if (!image) break;
            skin = [SkinItem new]; skin.skinId = @"account_current"; skin.name = @"Current skin";
            skin.armStyle = [entry[@"variant"] isEqual:@"SLIM"] ? SkinArmStyleSlim : SkinArmStyleWide;
            NSString *profileId = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
            profileId = [[profileId componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            skin.skinId = [@"account_" stringByAppendingString:profileId];
            skin.skinPath = [self.skinsDirectory stringByAppendingPathComponent:[skin.skinId stringByAppendingString:@".png"]];
            [UIImagePNGRepresentation(image) writeToFile:skin.skinPath atomically:YES]; skin.capeId = activeCape;
            break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (BaseAuthenticator.current != account) { completion(nil, [NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Account changed. Close this screen and reopen it."}]); return; }
            if (!error) self.availableCapes = capes;
            completion(skin, error);
        });
    });
}
- (void)applyOnlineSkin:(SkinItem *)skin completion:(void (^)(NSError *))completion {
    BaseAuthenticator *account = BaseAuthenticator.current;
    NSString *token = SkinToken(account);
    if (!token.length) { completion([NSError errorWithDomain:@"MinecraftProfile" code:401 userInfo:@{NSLocalizedDescriptionKey:@"Sign in again to apply this skin."}]); return; }
    NSData *png = UIImagePNGRepresentation([skin loadImage]);
    if (!png) { completion([NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Select a valid skin image."}]); return; }
    NSString *capeId = skin.capeId ?: @"none";
    if (![capeId isEqual:@"none"] && ![self capeForId:capeId]) { completion([NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Reload your profile and select an owned cape."}]); return; }
    NSString *boundary = NSUUID.UUID.UUIDString;
    NSMutableData *body = [NSMutableData data];
    NSString *head = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"variant\"\r\n\r\n%@\r\n--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\nContent-Type: image/png\r\n\r\n", boundary, skin.armStyle == SkinArmStyleSlim ? @"slim" : @"classic", boundary];
    [body appendData:[head dataUsingEncoding:NSUTF8StringEncoding]]; [body appendData:png];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        SkinRequest(@"https://api.minecraftservices.com/minecraft/profile/skins", @"POST", body, [@"multipart/form-data; boundary=" stringByAppendingString:boundary], token, &error);
        if (!error) {
            BOOL hide = [capeId isEqual:@"none"];
            NSData *capeBody = hide ? nil : [NSJSONSerialization dataWithJSONObject:@{@"capeId":capeId} options:0 error:nil];
            SkinRequest(@"https://api.minecraftservices.com/minecraft/profile/capes/active", hide ? @"DELETE" : @"PUT", capeBody, @"application/json", token, &error);
            if (error) error = [NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey:[@"Skin uploaded, but cape update failed: " stringByAppendingString:error.localizedDescription]}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ NSError *result = error; if (BaseAuthenticator.current != account) result = [NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Account changed while updating. Reload the profile to verify the result."}]; completion(result); });
    });
}

- (void)setupDefaultCapes {
    NSMutableArray *capes = [NSMutableArray array];

    CapeItem *none = [[CapeItem alloc] init];
    none.capeId = @"none";
    none.name = localize(@"skin.cape.none", @"No cape");
    none.capePath = @"";
    [capes addObject:none];

    _availableCapes = [capes copy];
}

- (void)setupDefaultSkins {
    NSMutableArray *defaults = [NSMutableArray array];

    NSArray *skinDefs = @[
        @{@"name": @"Steve", @"arm": @(SkinArmStyleWide), @"file": @"steve.png"},
        @{@"name": @"Alex", @"arm": @(SkinArmStyleSlim), @"file": @"alex.png"},
        @{@"name": @"Ari", @"arm": @(SkinArmStyleSlim), @"file": @"ari.png"},
        @{@"name": @"Makena", @"arm": @(SkinArmStyleSlim), @"file": @"makena.png"},
        @{@"name": @"Noor", @"arm": @(SkinArmStyleSlim), @"file": @"noor.png"},
        @{@"name": @"Sunny", @"arm": @(SkinArmStyleSlim), @"file": @"sunny.png"},
        @{@"name": @"Zuri", @"arm": @(SkinArmStyleWide), @"file": @"zuri.png"},
        @{@"name": @"Kai", @"arm": @(SkinArmStyleSlim), @"file": @"kai.png"},
        @{@"name": @"Efe", @"arm": @(SkinArmStyleSlim), @"file": @"efe.png"}
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

    // Cache the avatar only after the Minecraft service accepted the update.
    UIImage *head = [self generateAvatarHeadFromSkin:[skin loadImage]];
    BaseAuthenticator *account = BaseAuthenticator.current;
    if (head && [account.authData[@"username"] isEqual:username]) {
        NSString *safeName = [[username componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
        NSString *headPath = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"head_%@.png",safeName]];
        if ([UIImagePNGRepresentation(head) writeToFile:headPath atomically:YES]) {
            account.authData[@"profilePicURL"] = [NSURL fileURLWithPath:headPath].absoluteString;
            NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json",getenv("AME_HOME"),username];
            NSMutableDictionary *saved = parseJSONFromFile(path);
            if ([saved isKindOfClass:NSMutableDictionary.class] && !saved[@"NSErrorObject"]) {
                saved[@"profilePicURL"] = account.authData[@"profilePicURL"];
                [saved removeObjectsForKeys:@[@"accessToken",@"msaRefreshToken"]];
                saveJSONToFile(saved,path);
            }
        }
    }
}

- (SkinItem *)saveDraft:(SkinItem *)draft image:(UIImage *)image {
    if (!draft || !image) return nil;
    SkinItem *item = [SkinItem fromDictionary:draft.toDictionary];
    if (!item.isCustom) {
        if ([item.skinId hasPrefix:@"default_"]) item.replacementSlot = item.skinId;
        item.skinId = NSUUID.UUID.UUIDString; item.isCustom = YES;
        item.name = [item.name stringByAppendingString:@" (custom)"];
    }
    // Never write to a path supplied by imported config or a bundled default.
    NSUUID *identifier = [[NSUUID alloc] initWithUUIDString:item.skinId];
    if (!identifier) { identifier = NSUUID.UUID; item.skinId = identifier.UUIDString; }
    item.skinPath = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"custom_%@.png",identifier.UUIDString]];
    if (![UIImagePNGRepresentation(image) writeToFile:item.skinPath atomically:YES]) return nil;
    NSUInteger index = [self.savedSkins indexOfObjectPassingTest:^BOOL(SkinItem *existing, NSUInteger idx, BOOL *stop) {
        return [existing.skinId isEqual:item.skinId] || (item.replacementSlot.length && [existing.replacementSlot isEqual:item.replacementSlot]);
    }];
    if (index == NSNotFound) [self.savedSkins addObject:item]; else self.savedSkins[index] = item;
    [self saveConfig]; return item;
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
    NSUUID *identifier = [[NSUUID alloc] initWithUUIDString:skin.skinId];
    if (identifier) {
        NSString *path = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"custom_%@.png",identifier.UUIDString]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
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
