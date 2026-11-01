#import "SkinManagerViewController.h"
#import "SkinEditorViewController.h"
#import "SkinUI.h"
#import <objc/runtime.h>

@interface SkinManagerViewController ()
@property UIScrollView *scroll;
@property UIView *previewPanel;
@property UIView *grid;
@property SkinPreviewView *preview;
@property UILabel *accountLabel;
@property UILabel *statusLabel;
@property UIButton *editButton;
@property UIButton *applyButton;
@property UIButton *reloadButton;
@property SkinItem *selection;
@property BOOL busy;
@property BOOL profileLoaded;
@property CGFloat gridWidth;
@end
@implementation SkinManagerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Skin / Cape";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.view.tintColor = SkinAccent();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.scroll = [UIScrollView new]; [self.view addSubview:self.scroll];
    self.previewPanel = [UIView new]; [self.scroll addSubview:self.previewPanel];
    self.grid = [UIView new]; [self.scroll addSubview:self.grid];
    self.accountLabel = SkinLabel(self.currentAccountUsername, 19); self.accountLabel.textAlignment = NSTextAlignmentCenter;
    [self.previewPanel addSubview:self.accountLabel];
    self.preview = [[SkinPreviewView alloc] initWithFrame:CGRectZero]; [self.previewPanel addSubview:self.preview];
    UILabel *hint = SkinLabel(@"Drag to rotate · Tap to flip", 12); hint.textAlignment = NSTextAlignmentCenter; hint.textColor = UIColor.secondaryLabelColor; hint.tag = 10;
    [self.previewPanel addSubview:hint];
    self.editButton = SkinButton(@"Edit skin / Cape", self, @selector(edit)); [self.previewPanel addSubview:self.editButton];
    self.applyButton = SkinButton(@"Apply to account", self, @selector(apply)); self.applyButton.backgroundColor = SkinAccent(); self.applyButton.tintColor = UIColor.whiteColor;
    [self.previewPanel addSubview:self.applyButton];
    self.statusLabel = SkinLabel(@"", 12); self.statusLabel.textAlignment = NSTextAlignmentCenter; [self.previewPanel addSubview:self.statusLabel];
    self.reloadButton = SkinButton(@"Reload profile", self, @selector(loadProfile)); [self.previewPanel addSubview:self.reloadButton];
    self.selection = [SkinItem fromDictionary:[[[SkinManager sharedManager] activeSkinForAccount:self.currentAccountUsername] toDictionary]];
    [self updatePreview]; [self loadProfile];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scroll.frame = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat width = self.scroll.bounds.size.width;
    BOOL landscape = width > 620;
    CGFloat left = landscape ? MIN(300, width * 0.35) : width - 32;
    self.previewPanel.frame = CGRectMake(16, 12, left, 474);
    self.accountLabel.frame = CGRectMake(0,0,left,28);
    self.preview.frame = CGRectMake(0,32,left,260);
    [self.previewPanel viewWithTag:10].frame = CGRectMake(0,296,left,20);
    self.editButton.frame = CGRectMake(0,324,left,44);
    self.applyButton.frame = CGRectMake(0,376,left,44);
    self.statusLabel.frame = CGRectMake(0,428,left,56);
    self.reloadButton.frame = CGRectMake(0,490,left,44);
    self.previewPanel.frame = CGRectMake(16,12,left,534);
    CGFloat x = landscape ? left+32 : 16, y = landscape ? 12 : 566;
    CGFloat gridWidth = MAX(100, width-x-16);
    self.grid.frame = CGRectMake(x,y,gridWidth,self.grid.bounds.size.height);
    if (self.gridWidth != gridWidth) { self.gridWidth = gridWidth; [self rebuildGrid]; }
    self.scroll.contentSize = CGSizeMake(width, MAX(CGRectGetMaxY(self.grid.frame), CGRectGetMaxY(self.previewPanel.frame))+20);
}
- (void)setWorking:(BOOL)working {
    self.busy = working; self.applyButton.enabled = !working && self.profileLoaded; self.editButton.enabled = !working;
    self.reloadButton.enabled = !working; self.grid.userInteractionEnabled = !working;
    self.navigationItem.rightBarButtonItem.enabled = !working;
    self.modalInPresentation = working; self.navigationController.modalInPresentation = working;
}
- (void)loadProfile {
    if (self.busy) return;
    self.profileLoaded = NO; [self setWorking:YES]; self.statusLabel.text = @"Loading your skin and owned capes…";
    __weak typeof(self) weakSelf = self;
    [[SkinManager sharedManager] fetchProfile:^(SkinItem *skin, NSError *error) {
        typeof(self) self = weakSelf; if (!self) return;
        self.profileLoaded = !error; [self setWorking:NO];
        self.statusLabel.text = error ? error.localizedDescription : @"Choose a skin, then apply to your account.";
        if (skin) self.selection = skin;
        [self updatePreview]; [self rebuildGrid];
    }];
}
- (void)updatePreview {
    self.preview.skinImage = [self.selection loadImage]; self.preview.armStyle = self.selection.armStyle;
    self.preview.capeImage = [[[SkinManager sharedManager] capeForId:self.selection.capeId] loadImage];
}
- (void)rebuildGrid {
    if (self.gridWidth <= 0) return;
    for (UIView *view in self.grid.subviews) [view removeFromSuperview];
    CGFloat width = self.gridWidth, gap = 12;
    NSInteger columns = MAX(2, (NSInteger)((width+gap)/144));
    CGFloat cardWidth = (width - gap*(columns-1))/columns, cardHeight = cardWidth*1.35+30;
    CGFloat y = 0;
    SkinManager *manager = [SkinManager sharedManager];
    NSMutableArray *saved = [NSMutableArray arrayWithObject:NSNull.null];
    for (SkinItem *skin in manager.savedSkins) if (!skin.replacementSlot.length) [saved addObject:skin];
    NSMutableArray *defaults = [NSMutableArray array];
    for (SkinItem *base in manager.defaultSkins) {
        SkinItem *shown = base;
        for (SkinItem *custom in manager.savedSkins) if ([custom.replacementSlot isEqual:base.skinId]) { shown = custom; break; }
        [defaults addObject:shown];
    }
    NSArray *sections = @[saved,defaults];
    for (NSInteger section = 0; section < 2; section++) {
        UILabel *title = SkinLabel(section == 0 ? @"Saved skins" : @"Default skins", 20);
        title.frame = CGRectMake(0,y,width,28); [self.grid addSubview:title]; y += 38;
        NSArray *items = sections[section];
        for (NSInteger index = 0; index < items.count; index++) {
            CGRect frame = CGRectMake((index%columns)*(cardWidth+gap), y+(index/columns)*(cardHeight+gap), cardWidth,cardHeight);
            if (items[index] == NSNull.null) {
                UIButton *add = SkinButton(@"＋ Add skin", self, @selector(add)); add.frame = frame;
                add.titleLabel.numberOfLines = 2; [self.grid addSubview:add]; continue;
            }
            SkinItem *skin = items[index];
            UIButton *card = SkinButton(@"", self, @selector(select:)); card.frame = frame;
            card.layer.borderWidth = [skin.skinId isEqual:self.selection.skinId] ? 2 : 0;
            card.layer.borderColor = SkinAccent().CGColor; card.accessibilityLabel = skin.name;
            objc_setAssociatedObject(card, @selector(select:), skin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            SkinPreviewView *model = [[SkinPreviewView alloc] initWithFrame:CGRectZero]; model.skinImage = [skin loadImage]; model.armStyle = skin.armStyle;
            UIImageView *thumbnail = [[UIImageView alloc] initWithImage:[model generateThumbnailWithSize:CGSizeMake(cardWidth-12,cardHeight-36)]];
            thumbnail.frame = CGRectMake(6,4,cardWidth-12,cardHeight-36); thumbnail.contentMode = UIViewContentModeScaleAspectFit;
            [card addSubview:thumbnail];
            UILabel *name = SkinLabel(skin.name,13); name.textAlignment = NSTextAlignmentCenter; name.frame = CGRectMake(4,cardHeight-30,cardWidth-8,26); [card addSubview:name];
            [self.grid addSubview:card];
            if (skin.isCustom) {
                UIButton *remove = SkinButton(@"×", self, @selector(remove:)); remove.frame = CGRectMake(CGRectGetMaxX(frame)-44,frame.origin.y,44,44);
                remove.accessibilityLabel = [@"Delete " stringByAppendingString:skin.name];
                objc_setAssociatedObject(remove,@selector(remove:),skin,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [self.grid addSubview:remove];
            }
        }
        y += ((items.count+columns-1)/columns)*(cardHeight+gap)+20;
    }
    CGRect frame = self.grid.frame; frame.size.height = y; self.grid.frame = frame; [self.view setNeedsLayout];
}
- (void)select:(UIButton *)button {
    SkinItem *skin = objc_getAssociatedObject(button,@selector(select:));
    NSString *cape = self.selection.capeId;
    self.selection = [SkinItem fromDictionary:skin.toDictionary]; self.selection.capeId = cape ?: @"none";
    [self updatePreview]; [self rebuildGrid];
}
- (void)openEditor:(BOOL)importing {
    SkinEditorViewController *editor = [SkinEditorViewController new];
    editor.skinToEdit = [SkinItem fromDictionary:self.selection.toDictionary]; editor.importOnOpen = importing;
    editor.accountUsername = self.currentAccountUsername;
    __weak typeof(self) weakSelf = self;
    editor.whenSkinAdded = ^(SkinItem *skin) {
        typeof(self) self = weakSelf; if (!self) return;
        self.selection = skin; [self updatePreview]; [self rebuildGrid];
        self.statusLabel.text = @"Skin and cape confirmed on your account. Restart Minecraft to refresh cached textures.";
        if (self.whenSkinChanged) self.whenSkinChanged(skin);
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)edit { [self openEditor:NO]; }
- (void)add { [self openEditor:YES]; }
- (void)remove:(UIButton *)button {
    SkinItem *skin = objc_getAssociatedObject(button,@selector(remove:));
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete saved skin?" message:@"This removes the local copy. Your Minecraft account will keep its current skin." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[SkinManager sharedManager] deleteCustomSkin:skin];
        if ([self.selection.skinId isEqual:skin.skinId]) self.selection = [SkinItem fromDictionary:[SkinManager sharedManager].defaultSkins.firstObject.toDictionary];
        [self updatePreview]; [self rebuildGrid];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)apply {
    if (self.busy || !self.profileLoaded) return;
    [self setWorking:YES]; self.statusLabel.text = @"Updating Minecraft account…";
    SkinItem *selection = [SkinItem fromDictionary:self.selection.toDictionary];
    [[SkinManager sharedManager] applyOnlineSkin:selection completion:^(NSError *error) {
        [self setWorking:NO]; self.statusLabel.text = error ? error.localizedDescription : @"Skin and cape confirmed on your account. Restart Minecraft to refresh cached textures.";
        if (error) { SkinAlert(self,@"Could not finish updating",error.localizedDescription); return; }
        [[SkinManager sharedManager] setActiveSkin:selection forAccount:self.currentAccountUsername];
        if (self.whenSkinChanged) self.whenSkinChanged(selection);
    }];
}
- (void)done { if (!self.busy) [self dismissViewControllerAnimated:YES completion:nil]; }
@end
