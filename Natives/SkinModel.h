#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SkinPreviewView.h"

@interface SkinItem : NSObject

@property (nonatomic, copy) NSString *skinId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) SkinArmStyle armStyle;
@property (nonatomic, copy) NSString *skinPath;
@property (nonatomic, copy) NSString *capeId;
@property (nonatomic, assign) BOOL isCustom;

- (UIImage *)loadImage;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

@interface CapeItem : NSObject

@property (nonatomic, copy) NSString *capeId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *capePath;

- (UIImage *)loadImage;

@end

@interface SkinManager : NSObject

@property (nonatomic, copy, readonly) NSString *skinsDirectory;
@property (nonatomic, strong) NSMutableArray<SkinItem *> *savedSkins;
@property (nonatomic, strong) NSArray<SkinItem *> *defaultSkins;
@property (nonatomic, strong) NSArray<CapeItem *> *availableCapes;

+ (instancetype)sharedManager;
- (void)reload;
- (void)saveConfig;

- (SkinItem *)activeSkinForAccount:(NSString *)username;
- (void)setActiveSkin:(SkinItem *)skin forAccount:(NSString *)username;

- (CapeItem *)capeForId:(NSString *)capeId;
- (SkinItem *)addCustomSkinWithImage:(UIImage *)image name:(NSString *)name armStyle:(SkinArmStyle)armStyle capeId:(NSString *)capeId;
- (void)deleteCustomSkin:(SkinItem *)skin;

- (UIImage *)generateAvatarHeadFromSkin:(UIImage *)skinImage;

@end
