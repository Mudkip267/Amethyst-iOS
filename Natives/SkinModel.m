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
    NSURL *requestURL = [NSURL URLWithString:url];
    if (!requestURL || !requestURL.scheme.length || !requestURL.host.length) {
        if (error) *error = [NSError errorWithDomain:@"MinecraftProfile" code:NSURLErrorBadURL userInfo:@{NSLocalizedDescriptionKey: @"Minecraft returned an invalid texture URL."}];
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = method;
    request.timeoutInterval = 25;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.HTTPBody = body;
    if (type) [request setValue:type forHTTPHeaderField:@"Content-Type"];
    if (token.length) {
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    }
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
static NSDictionary *SkinActiveEntry(id profile, NSString *key) {
    if (![profile isKindOfClass:NSDictionary.class]) return nil;
    id entries = profile[key];
    if (![entries isKindOfClass:NSArray.class]) return nil;
    for (id entry in entries) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"state"] isEqual:@"ACTIVE"]) return entry;
    }
    return nil;
}
static NSString *SkinTextureIdentity(NSDictionary *entry) {
    id url = entry[@"url"];
    if (![url isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    if (![parts.host.lowercaseString isEqual:@"textures.minecraft.net"] || ![parts.path hasPrefix:@"/texture/"]) return nil;
    return parts.path;
}
static UIImage *SkinTexture(id url) {
    if (![url isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    if (![parts.host.lowercaseString isEqualToString:@"textures.minecraft.net"]) return nil;
    parts.scheme = @"https";
    NSURL *textureURL = parts.URL;
    if (!textureURL) return nil;
    NSData *data = SkinRequest(textureURL.absoluteString, @"GET", nil, nil, nil, nil);
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    return image.CGImage ? image : nil;
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
            NSData *capePNG = image ? UIImagePNGRepresentation(image) : nil;
            if (capePNG && ![capePNG writeToFile:cape.capePath atomically:YES]) cape.capePath = @"";
            if (!capePNG) cape.capePath = @"";
            [capes addObject:cape];
            if ([entry[@"state"] isEqual:@"ACTIVE"]) activeCape = cape.capeId;
        }
        SkinItem *skin = nil;
        NSArray *skins = [profile[@"skins"] isKindOfClass:NSArray.class] ? profile[@"skins"] : @[];
        for (NSDictionary *entry in skins) {
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            if (![entry[@"state"] isEqual:@"ACTIVE"]) continue;
            UIImage *image = SkinTexture(entry[@"url"]);
            if (!image) {
                error = [NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Could not download your current skin texture. Check your connection and reload the profile."}];
                break;
            }
            skin = [SkinItem new]; skin.skinId = @"account_current"; skin.name = @"Current skin";
            skin.armStyle = [entry[@"variant"] isEqual:@"SLIM"] ? SkinArmStyleSlim : SkinArmStyleWide;
            NSString *profileId = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
            profileId = [[profileId componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            skin.skinId = [@"account_" stringByAppendingString:profileId];
            skin.skinPath = [self.skinsDirectory stringByAppendingPathComponent:[skin.skinId stringByAppendingString:@".png"]];
            NSData *skinPNG = UIImagePNGRepresentation(image);
            if (!skinPNG || ![skinPNG writeToFile:skin.skinPath atomically:YES]) {
                skin = nil;
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSLocalizedDescriptionKey: @"Could not save your current skin texture. Check available storage and try again."}];
                break;
            }
            skin.capeId = activeCape;
            break;
        }
        if (!error && !skin) {
            error = [NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Minecraft did not return an active skin for this account."}];
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
    UIImage *skinImage = [skin loadImage];
    CGImageRef skinCGImage = skinImage.CGImage;
    size_t skinWidth = skinCGImage ? CGImageGetWidth(skinCGImage) : 0;
    size_t skinHeight = skinCGImage ? CGImageGetHeight(skinCGImage) : 0;
    if (skinWidth != 64 || (skinHeight != 64 && skinHeight != 32)) {
        completion([NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Choose a valid 64 × 64 or 64 × 32 PNG skin before applying."}]);
        return;
    }
    NSData *png = UIImagePNGRepresentation(skinImage);
    if (!png) { completion([NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Select a valid skin image."}]); return; }
    NSString *capeId = skin.capeId ?: @"none";
    NSString *variant = skin.armStyle == SkinArmStyleSlim ? @"SLIM" : @"CLASSIC";
    if (![capeId isEqual:@"none"] && ![self capeForId:capeId]) { completion([NSError errorWithDomain:@"MinecraftProfile" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Reload your profile and select an owned cape."}]); return; }
    NSString *boundary = NSUUID.UUID.UUIDString;
    NSMutableData *body = [NSMutableData data];
    NSString *head = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"variant\"\r\n\r\n%@\r\n--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\nContent-Type: image/png\r\n\r\n", boundary, skin.armStyle == SkinArmStyleSlim ? @"slim" : @"classic", boundary];
    [body appendData:[head dataUsingEncoding:NSUTF8StringEncoding]]; [body appendData:png];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSData *uploaded = SkinRequest(@"https://api.minecraftservices.com/minecraft/profile/skins", @"POST", body, [@"multipart/form-data; boundary=" stringByAppendingString:boundary], token, &error);
        id uploadedProfile = uploaded.length ? [NSJSONSerialization JSONObjectWithData:uploaded options:0 error:nil] : nil;
        NSString *expectedTexture = SkinTextureIdentity(SkinActiveEntry(uploadedProfile, @"skins"));
        if (!error) {
            BOOL hide = [capeId isEqual:@"none"];
            NSData *capeBody = hide ? nil : [NSJSONSerialization dataWithJSONObject:@{@"capeId":capeId} options:0 error:nil];
            SkinRequest(@"https://api.minecraftservices.com/minecraft/profile/capes/active", hide ? @"DELETE" : @"PUT", capeBody, @"application/json", token, &error);
            if (error) error = [NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey:[@"Skin uploaded, but cape update failed: " stringByAppendingString:error.localizedDescription]}];
        }
        if (!error) {
            BOOL confirmed = NO;
            // The profile endpoint can lag behind a successful upload, so retry reads only.
            for (NSInteger attempt = 0; attempt < 3; attempt++) {
                if (attempt) [NSThread sleepForTimeInterval:attempt == 1 ? 0.4 : 1.0];
                NSData *profileData = SkinRequest(@"https://api.minecraftservices.com/minecraft/profile", @"GET", nil, nil, token, &error);
                if (error) break;
                id profile = profileData.length ? [NSJSONSerialization JSONObjectWithData:profileData options:0 error:nil] : nil;
                NSDictionary *activeSkin = SkinActiveEntry(profile, @"skins");
                NSDictionary *activeCape = SkinActiveEntry(profile, @"capes");
                BOOL valid = [profile isKindOfClass:NSDictionary.class] && [profile[@"skins"] isKindOfClass:NSArray.class] && [profile[@"capes"] isKindOfClass:NSArray.class];
                BOOL capeMatches = [capeId isEqual:@"none"] ? !activeCape : [activeCape[@"id"] isEqual:capeId];
                confirmed = valid && expectedTexture.length && [SkinTextureIdentity(activeSkin) isEqual:expectedTexture] && [activeSkin[@"variant"] isEqual:variant] && capeMatches;
                if (confirmed) break;
            }
            if (!confirmed) {
                NSString *message = error ? [@"Changes were sent, but Minecraft could not confirm them: " stringByAppendingString:error.localizedDescription] : @"Changes were sent, but Minecraft has not confirmed the selected skin and cape. Reload the profile to check before trying again.";
                error = [NSError errorWithDomain:@"MinecraftProfile" code:error.code userInfo:@{NSLocalizedDescriptionKey: message}];
            }
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

- (BOOL)saveConfig {
    NSMutableArray *savedArray = [NSMutableArray array];
    for (SkinItem *item in self.savedSkins) {
        [savedArray addObject:[item toDictionary]];
    }
    NSDictionary *json = @{
        @"savedSkins": savedArray,
        @"activeSkins": self.accountActiveSkins
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) return NO;
    return [data writeToFile:self.configFile options:NSDataWritingAtomic error:&error];
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

- (BOOL)setActiveSkin:(SkinItem *)skin forAccount:(NSString *)username {
    if (!username || username.length == 0) username = @"default";
    if (!skin) return NO;

    NSString *previousSkinId = self.accountActiveSkins[username];
    self.accountActiveSkins[username] = skin.skinId;
    if (![self saveConfig]) {
        if (previousSkinId) self.accountActiveSkins[username] = previousSkinId;
        else [self.accountActiveSkins removeObjectForKey:username];
        return NO;
    }

    // Cache the avatar only after the Minecraft service accepted the update.
    UIImage *head = [self generateAvatarHeadFromSkin:[skin loadImage]];
    BaseAuthenticator *account = BaseAuthenticator.current;
    if (head && [account.authData[@"username"] isEqual:username]) {
        NSString *safeName = [[username componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
        NSString *headPath = [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"head_%@.png",safeName]];
        if ([UIImagePNGRepresentation(head) writeToFile:headPath atomically:YES]) {
            account.authData[@"profilePicURL"] = [NSURL fileURLWithPath:headPath].absoluteString;
            const char *home = getenv("AME_HOME");
            if (home && *home) {
                NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
                [allowed addCharactersInString:@"_-"];
                NSString *safeAccountName = [[username componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@""];
                if (safeAccountName.length) {
                    NSString *accountsDirectory = [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"accounts"];
                    NSString *path = [[accountsDirectory stringByAppendingPathComponent:safeAccountName] stringByAppendingPathExtension:@"json"];
                    NSMutableDictionary *saved = parseJSONFromFile(path);
                    if ([saved isKindOfClass:NSMutableDictionary.class] && !saved[@"NSErrorObject"]) {
                        saved[@"profilePicURL"] = account.authData[@"profilePicURL"];
                        [saved removeObjectsForKeys:@[@"accessToken",@"msaRefreshToken"]];
                        saveJSONToFile(saved,path);
                    }
                }
            }
        }
    }
    return YES;
}

- (SkinItem *)saveDraft:(SkinItem *)draft image:(UIImage *)image {
    if (!draft || !image) return nil;
    CGImageRef cgImage = image.CGImage;
    size_t width = cgImage ? CGImageGetWidth(cgImage) : 0, height = cgImage ? CGImageGetHeight(cgImage) : 0;
    if (width != 64 || (height != 64 && height != 32)) return nil;
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
    NSData *previousImage = [NSData dataWithContentsOfFile:item.skinPath];
    NSData *skinPNG = UIImagePNGRepresentation(image);
    if (!skinPNG || ![skinPNG writeToFile:item.skinPath atomically:YES]) return nil;
    NSUInteger index = [self.savedSkins indexOfObjectPassingTest:^BOOL(SkinItem *existing, NSUInteger idx, BOOL *stop) {
        return [existing.skinId isEqual:item.skinId] || (item.replacementSlot.length && [existing.replacementSlot isEqual:item.replacementSlot]);
    }];
    SkinItem *previous = index == NSNotFound ? nil : self.savedSkins[index];
    if (index == NSNotFound) [self.savedSkins addObject:item]; else self.savedSkins[index] = item;
    if (![self saveConfig]) {
        if (index == NSNotFound) [self.savedSkins removeObject:item]; else self.savedSkins[index] = previous;
        if (previousImage) [previousImage writeToFile:item.skinPath atomically:YES];
        else [[NSFileManager defaultManager] removeItemAtPath:item.skinPath error:nil];
        return nil;
    }
    return item;
}

- (SkinItem *)addCustomSkinWithImage:(UIImage *)image name:(NSString *)name armStyle:(SkinArmStyle)armStyle capeId:(NSString *)capeId {
    if (!image) return nil;
    CGImageRef cgImage = image.CGImage;
    size_t width = cgImage ? CGImageGetWidth(cgImage) : 0, height = cgImage ? CGImageGetHeight(cgImage) : 0;
    if (width != 64 || (height != 64 && height != 32)) return nil;
    NSString *skinId = [[NSUUID UUID] UUIDString];
    NSString *fileName = [NSString stringWithFormat:@"custom_%@.png", skinId];
    NSString *filePath = [self.skinsDirectory stringByAppendingPathComponent:fileName];

    NSData *data = UIImagePNGRepresentation(image);
    if (!data || ![data writeToFile:filePath atomically:YES]) return nil;

    SkinItem *item = [[SkinItem alloc] init];
    item.skinId = skinId;
    item.name = (name && name.length > 0) ? name : [NSString stringWithFormat:@"Custom Skin %lu", (unsigned long)(self.savedSkins.count + 1)];
    item.armStyle = armStyle;
    item.skinPath = filePath;
    item.capeId = capeId ?: @"none";
    item.isCustom = YES;

    [self.savedSkins addObject:item];
    if (![self saveConfig]) {
        [self.savedSkins removeObject:item];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        return nil;
    }
    return item;
}

- (BOOL)deleteCustomSkin:(SkinItem *)skin {
    if (!skin || !skin.isCustom) return NO;
    NSUInteger index = [self.savedSkins indexOfObjectIdenticalTo:skin];
    if (index == NSNotFound) return NO;
    NSUUID *identifier = [[NSUUID alloc] initWithUUIDString:skin.skinId];
    NSString *expectedPath = identifier ? [self.skinsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"custom_%@.png",identifier.UUIDString]] : nil;
    NSString *storedPath = skin.skinPath;
    [self.savedSkins removeObjectAtIndex:index];
    if (![self saveConfig]) {
        [self.savedSkins insertObject:skin atIndex:index];
        return NO;
    }
    // Remove only a file owned by the skin cache; imported config paths are never trusted.
    NSString *path = [storedPath.stringByStandardizingPath stringByDeletingLastPathComponent];
    if ([path isEqualToString:self.skinsDirectory.stringByStandardizingPath] && [storedPath.lastPathComponent hasPrefix:@"custom_"]) {
        [[NSFileManager defaultManager] removeItemAtPath:storedPath error:nil];
    } else if (expectedPath) {
        [[NSFileManager defaultManager] removeItemAtPath:expectedPath error:nil];
    }
    return YES;
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
