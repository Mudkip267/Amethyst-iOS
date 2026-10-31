#import "SkinManagerViewController.h"
#import "SkinPreviewView.h"
#import "SkinEditorViewController.h"
#import "utils.h"

@interface SkinManagerViewController ()

@property (nonatomic, strong) SkinPreviewView *mainPreviewView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIButton *btnChangeCape;
@property (nonatomic, strong) UIButton *btnApply;
@property (nonatomic, strong) UIScrollView *rightScrollView;
@property (nonatomic, strong) UIView *savedSkinsContainer;
@property (nonatomic, strong) UIView *defaultSkinsContainer;

@property (nonatomic, strong) SkinItem *currentActiveSkin;

@end

@implementation SkinManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"skin.manager.title", @"Skins");
    self.view.backgroundColor = [UIColor colorWithRed:20/255.0 green:20/255.0 blue:26/255.0 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(actionDone)];

    if (!self.currentAccountUsername || self.currentAccountUsername.length == 0) {
        self.currentAccountUsername = getPrefObject(@"internal.selected_account") ?: @"default";
    }

    _currentActiveSkin = [[SkinManager sharedManager] activeSkinForAccount:self.currentAccountUsername];

    [self buildLayout];
    [self refreshSkinsList];
    [self updateMainPreview];
}

- (void)buildLayout {
    CGFloat totalW = self.view.bounds.size.width;
    CGFloat totalH = self.view.bounds.size.height;
    CGFloat topBarH = self.navigationController.navigationBar.frame.size.height + [UIApplication sharedApplication].statusBarFrame.size.height;
    if (topBarH < 60) topBarH = 60;

    CGFloat contentH = totalH - topBarH;

    // Responsive: Split into Left Column (35%) and Right Column (65%)
    CGFloat leftColW = MAX(240, MIN(320, totalW * 0.35));
    CGFloat rightColX = leftColW + 16;
    CGFloat rightColW = totalW - rightColX - 16;

    // === LEFT COLUMN ===
    UIView *leftCol = [[UIView alloc] initWithFrame:CGRectMake(16, topBarH + 10, leftColW, contentH - 20)];
    leftCol.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:leftCol];

    // Username badge
    _usernameLabel = [[UILabel alloc] initWithFrame:CGRectMake((leftColW - 160) / 2, 8, 160, 32)];
    _usernameLabel.text = self.currentAccountUsername;
    _usernameLabel.textAlignment = NSTextAlignmentCenter;
    _usernameLabel.textColor = [UIColor whiteColor];
    _usernameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _usernameLabel.backgroundColor = [UIColor colorWithRed:32/255.0 green:32/255.0 blue:42/255.0 alpha:1.0];
    _usernameLabel.layer.cornerRadius = 8;
    _usernameLabel.clipsToBounds = YES;
    [leftCol addSubview:_usernameLabel];

    // Big Character Preview
    CGFloat previewH = MIN(leftCol.bounds.size.height - 150, 340);
    _mainPreviewView = [[SkinPreviewView alloc] initWithFrame:CGRectMake(10, 48, leftColW - 20, previewH)];
    _mainPreviewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [leftCol addSubview:_mainPreviewView];

    // Drag to rotate label
    UILabel *rotateHint = [[UILabel alloc] initWithFrame:CGRectMake(10, 48 + previewH + 4, leftColW - 20, 18)];
    rotateHint.text = localize(@"skin.drag.hint", @"Drag to rotate / Tap to flip");
    rotateHint.textAlignment = NSTextAlignmentCenter;
    rotateHint.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    rotateHint.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    [leftCol addSubview:rotateHint];

    // Button Change Cape
    _btnChangeCape = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnChangeCape.frame = CGRectMake((leftColW - 140) / 2, 48 + previewH + 28, 140, 36);
    _btnChangeCape.backgroundColor = [UIColor colorWithRed:35/255.0 green:35/255.0 blue:48/255.0 alpha:1.0];
    _btnChangeCape.layer.cornerRadius = 8;
    [_btnChangeCape setTitle:localize(@"skin.change_cape", @"Change cape") forState:UIControlStateNormal];
    [_btnChangeCape setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
    _btnChangeCape.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_btnChangeCape addTarget:self action:@selector(actionChangeCape) forControlEvents:UIControlEventTouchUpInside];
    [leftCol addSubview:_btnChangeCape];

    // Button Apply
    _btnApply = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnApply.frame = CGRectMake((leftColW - 180) / 2, 48 + previewH + 72, 180, 40);
    _btnApply.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0]; // Amethyst purple
    _btnApply.layer.cornerRadius = 10;
    [_btnApply setTitle:localize(@"skin.apply.account", @"Apply to Account") forState:UIControlStateNormal];
    [_btnApply setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnApply.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_btnApply addTarget:self action:@selector(actionApplyToAccount) forControlEvents:UIControlEventTouchUpInside];
    [leftCol addSubview:_btnApply];

    // === RIGHT COLUMN ===
    _rightScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(rightColX, topBarH + 10, rightColW, contentH - 20)];
    _rightScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _rightScrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:_rightScrollView];
}

- (void)updateMainPreview {
    if (!self.currentActiveSkin) {
        self.currentActiveSkin = [SkinManager sharedManager].defaultSkins.firstObject;
    }
    self.mainPreviewView.skinImage = [self.currentActiveSkin loadImage];
    self.mainPreviewView.armStyle = self.currentActiveSkin.armStyle;
    CapeItem *c = [[SkinManager sharedManager] capeForId:self.currentActiveSkin.capeId];
    self.mainPreviewView.capeImage = [c loadImage];
    self.usernameLabel.text = self.currentAccountUsername;
}

- (void)refreshSkinsList {
    for (UIView *v in self.rightScrollView.subviews) {
        [v removeFromSuperview];
    }

    CGFloat contentW = self.rightScrollView.bounds.size.width;
    CGFloat curY = 0;

    // --- Section: Saved Skins ---
    UILabel *lblSaved = [[UILabel alloc] initWithFrame:CGRectMake(8, curY, contentW - 16, 26)];
    lblSaved.text = localize(@"skin.section.saved", @"Saved skins");
    lblSaved.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    lblSaved.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.rightScrollView addSubview:lblSaved];
    curY += 34;

    CGFloat cardW = 96;
    CGFloat cardH = 130;
    CGFloat spacing = 12;
    int cols = MAX(1, (int)((contentW - 16 + spacing) / (cardW + spacing)));
    CGFloat startX = 8;

    int itemIdx = 0;

    // 1. "+ Add a skin" card
    CGFloat cardX = startX + (itemIdx % cols) * (cardW + spacing);
    CGFloat cardY = curY + (itemIdx / cols) * (cardH + spacing);

    UIButton *addCard = [UIButton buttonWithType:UIButtonTypeCustom];
    addCard.frame = CGRectMake(cardX, cardY, cardW, cardH);
    addCard.backgroundColor = [UIColor colorWithRed:28/255.0 green:28/255.0 blue:36/255.0 alpha:1.0];
    addCard.layer.cornerRadius = 10;
    addCard.layer.borderWidth = 1.0;
    addCard.layer.borderColor = [UIColor colorWithRed:44/255.0 green:44/255.0 blue:56/255.0 alpha:1.0].CGColor;

    UILabel *plusIcon = [[UILabel alloc] initWithFrame:CGRectMake(0, 32, cardW, 36)];
    plusIcon.text = @"+";
    plusIcon.textAlignment = NSTextAlignmentCenter;
    plusIcon.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    plusIcon.font = [UIFont systemFontOfSize:32 weight:UIFontWeightLight];
    [addCard addSubview:plusIcon];

    UILabel *addText = [[UILabel alloc] initWithFrame:CGRectMake(4, 72, cardW - 8, 20)];
    addText.text = localize(@"skin.add.skin", @"Add a skin");
    addText.textAlignment = NSTextAlignmentCenter;
    addText.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    addText.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [addCard addSubview:addText];

    [addCard addTarget:self action:@selector(actionOpenSkinEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.rightScrollView addSubview:addCard];
    itemIdx++;

    // 2. User's saved skins
    NSArray<SkinItem *> *saved = [SkinManager sharedManager].savedSkins;
    for (SkinItem *skin in saved) {
        cardX = startX + (itemIdx % cols) * (cardW + spacing);
        cardY = curY + (itemIdx / cols) * (cardH + spacing);

        UIView *card = [self createSkinCardWithSkin:skin frame:CGRectMake(cardX, cardY, cardW, cardH)];
        [self.rightScrollView addSubview:card];
        itemIdx++;
    }

    curY += ((itemIdx + cols - 1) / cols) * (cardH + spacing) + 20;

    // --- Section: Default Skins ---
    UILabel *lblDefault = [[UILabel alloc] initWithFrame:CGRectMake(8, curY, contentW - 16, 26)];
    lblDefault.text = localize(@"skin.section.default", @"Default skins");
    lblDefault.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    lblDefault.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.rightScrollView addSubview:lblDefault];
    curY += 34;

    itemIdx = 0;
    NSArray<SkinItem *> *defaults = [SkinManager sharedManager].defaultSkins;
    for (SkinItem *skin in defaults) {
        cardX = startX + (itemIdx % cols) * (cardW + spacing);
        cardY = curY + (itemIdx / cols) * (cardH + spacing);

        UIView *card = [self createSkinCardWithSkin:skin frame:CGRectMake(cardX, cardY, cardW, cardH)];
        [self.rightScrollView addSubview:card];
        itemIdx++;
    }

    curY += ((itemIdx + cols - 1) / cols) * (cardH + spacing) + 30;
    self.rightScrollView.contentSize = CGSizeMake(contentW, curY);
}

- (UIView *)createSkinCardWithSkin:(SkinItem *)skin frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = [UIColor colorWithRed:28/255.0 green:28/255.0 blue:36/255.0 alpha:1.0];
    card.layer.cornerRadius = 10;
    card.clipsToBounds = YES;

    BOOL isSelected = [skin.skinId isEqualToString:self.currentActiveSkin.skinId];
    if (isSelected) {
        // Highlight active skin with green or Amethyst border
        card.layer.borderWidth = 2.0;
        card.layer.borderColor = [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0].CGColor;
    } else {
        card.layer.borderWidth = 1.0;
        card.layer.borderColor = [UIColor colorWithRed:44/255.0 green:44/255.0 blue:56/255.0 alpha:1.0].CGColor;
    }

    // Mini Preview View
    SkinPreviewView *miniPreview = [[SkinPreviewView alloc] initWithFrame:CGRectMake(8, 8, frame.size.width - 16, 92)];
    miniPreview.userInteractionEnabled = NO;
    miniPreview.skinImage = [skin loadImage];
    miniPreview.armStyle = skin.armStyle;
    CapeItem *c = [[SkinManager sharedManager] capeForId:skin.capeId];
    miniPreview.capeImage = [c loadImage];
    [card addSubview:miniPreview];

    // Label Name
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, frame.size.height - 24, frame.size.width - 8, 18)];
    nameLabel.text = skin.name;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.textColor = isSelected ? [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0] : [UIColor colorWithWhite:0.8 alpha:1.0];
    nameLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [card addSubview:nameLabel];

    // Tap button covering card
    UIButton *tapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    tapBtn.frame = card.bounds;
    objc_setAssociatedObject(tapBtn, "skin_target", skin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tapBtn addTarget:self action:@selector(actionSelectSkinCard:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:tapBtn];

    // Delete button for custom skins
    if (skin.isCustom) {
        UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        delBtn.frame = CGRectMake(frame.size.width - 24, 4, 20, 20);
        delBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        delBtn.layer.cornerRadius = 10;
        [delBtn setTitle:@"✕" forState:UIControlStateNormal];
        [delBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
        delBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        objc_setAssociatedObject(delBtn, "skin_delete", skin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [delBtn addTarget:self action:@selector(actionDeleteSkin:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:delBtn];
    }

    return card;
}

- (void)actionSelectSkinCard:(UIButton *)sender {
    SkinItem *skin = objc_getAssociatedObject(sender, "skin_target");
    if (!skin) return;

    self.currentActiveSkin = skin;
    [self updateMainPreview];
    [self refreshSkinsList];
}

- (void)actionDeleteSkin:(UIButton *)sender {
    SkinItem *skin = objc_getAssociatedObject(sender, "skin_delete");
    if (!skin) return;

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:localize(@"skin.delete.title", @"Delete skin")
                                                                     message:localize(@"skin.delete.confirm", @"Are you sure you want to delete this custom skin?")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"Delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[SkinManager sharedManager] deleteCustomSkin:skin];
        if ([self.currentActiveSkin.skinId isEqualToString:skin.skinId]) {
            self.currentActiveSkin = [SkinManager sharedManager].defaultSkins.firstObject;
        }
        [self updateMainPreview];
        [self refreshSkinsList];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)actionOpenSkinEditor {
    SkinEditorViewController *editor = [[SkinEditorViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    editor.whenSkinAdded = ^(SkinItem *newSkin) {
        weakSelf.currentActiveSkin = newSkin;
        [weakSelf updateMainPreview];
        [weakSelf refreshSkinsList];
    };
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)actionChangeCape {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"skin.change_cape", @"Change cape")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<CapeItem *> *capes = [SkinManager sharedManager].availableCapes;
    for (CapeItem *c in capes) {
        NSString *title = [c.capeId isEqualToString:@"none"] ? localize(@"skin.cape.none", @"Use default cape") : c.name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.currentActiveSkin.capeId = c.capeId;
            [[SkinManager sharedManager] saveConfig];
            [self updateMainPreview];
            [self refreshSkinsList];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.btnChangeCape;
    sheet.popoverPresentationController.sourceRect = self.btnChangeCape.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)actionApplyToAccount {
    [[SkinManager sharedManager] setActiveSkin:self.currentActiveSkin forAccount:self.currentAccountUsername];

    if (self.whenSkinChanged) {
        self.whenSkinChanged(self.currentActiveSkin);
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"Success", @"Success")
                                                                   message:localize(@"skin.applied.msg", @"Skin and cape updated successfully for this account!")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", @"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)actionDone {
    // Automatically apply before closing if needed
    [[SkinManager sharedManager] setActiveSkin:self.currentActiveSkin forAccount:self.currentAccountUsername];
    if (self.whenSkinChanged) {
        self.whenSkinChanged(self.currentActiveSkin);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
