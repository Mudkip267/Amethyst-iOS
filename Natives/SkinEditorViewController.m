#import "SkinEditorViewController.h"
#import "SkinPreviewView.h"
#import "utils.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SkinEditorViewController () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) UIView *dialogView;
@property (nonatomic, strong) SkinPreviewView *previewView;
@property (nonatomic, strong) UIImage *selectedSkinImage;
@property (nonatomic, strong) NSString *selectedCapeId;
@property (nonatomic, assign) SkinArmStyle selectedArmStyle;
@property (nonatomic, assign) BOOL isPickingCape;

@property (nonatomic, strong) UIButton *btnWide;
@property (nonatomic, strong) UIButton *btnSlim;
@property (nonatomic, strong) UIScrollView *capeScrollView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *capeButtons;

@end

@implementation SkinEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;

    _selectedArmStyle = SkinArmStyleWide;
    _selectedCapeId = @"none";
    _capeButtons = [NSMutableArray array];

    if (self.skinToEdit) {
        _selectedSkinImage = [self.skinToEdit loadImage];
        _selectedArmStyle = self.skinToEdit.armStyle;
        _selectedCapeId = self.skinToEdit.capeId ?: @"none";
    } else {
        // Default to Steve
        NSString *stevePath = [[NSBundle mainBundle] pathForResource:@"steve" ofType:@"png" inDirectory:@"skins"];
        if (stevePath) {
            _selectedSkinImage = [UIImage imageWithContentsOfFile:stevePath];
        }
    }

    [self buildUI];
    [self updatePreview];
}

- (void)buildUI {
    CGFloat maxW = MIN(self.view.bounds.size.width - 40, 580);
    CGFloat maxH = MIN(self.view.bounds.size.height - 40, 420);

    _dialogView = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - maxW) / 2,
                                                           (self.view.bounds.size.height - maxH) / 2,
                                                           maxW, maxH)];
    _dialogView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    _dialogView.backgroundColor = [UIColor colorWithRed:30/255.0 green:30/255.0 blue:38/255.0 alpha:1.0];
    _dialogView.layer.cornerRadius = 16;
    _dialogView.layer.borderWidth = 1.0;
    _dialogView.layer.borderColor = [UIColor colorWithRed:46/255.0 green:46/255.0 blue:60/255.0 alpha:1.0].CGColor;
    _dialogView.clipsToBounds = YES;
    [self.view addSubview:_dialogView];

    // Header: Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 20, maxW - 80, 26)];
    titleLabel.text = self.skinToEdit ? localize(@"skin.edit.title", @"Editing skin") : localize(@"skin.add.title", @"Adding a skin");
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    [_dialogView addSubview:titleLabel];

    // Header: Close Button (X)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(maxW - 48, 16, 32, 32);
    closeBtn.backgroundColor = [UIColor colorWithRed:45/255.0 green:45/255.0 blue:56/255.0 alpha:1.0];
    closeBtn.layer.cornerRadius = 16;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [closeBtn addTarget:self action:@selector(actionCancel) forControlEvents:UIControlEventTouchUpInside];
    [_dialogView addSubview:closeBtn];

    // Left Column: Preview View
    CGFloat colW = (maxW - 48 - 20) / 2;
    CGFloat contentY = 60;
    CGFloat contentH = maxH - contentY - 70;

    _previewView = [[SkinPreviewView alloc] initWithFrame:CGRectMake(24, contentY, colW, contentH)];
    _previewView.armStyle = _selectedArmStyle;
    _previewView.skinImage = _selectedSkinImage;
    [_dialogView addSubview:_previewView];

    // Right Column: Controls
    CGFloat rightX = 24 + colW + 20;
    CGFloat curY = contentY;

    // 1. Texture Section
    UILabel *lblTexture = [[UILabel alloc] initWithFrame:CGRectMake(rightX, curY, colW, 18)];
    lblTexture.text = localize(@"skin.editor.texture", @"Texture");
    lblTexture.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    lblTexture.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_dialogView addSubview:lblTexture];
    curY += 24;

    UIButton *btnReplace = [UIButton buttonWithType:UIButtonTypeSystem];
    btnReplace.frame = CGRectMake(rightX, curY, MIN(colW, 160), 36);
    btnReplace.backgroundColor = [UIColor colorWithRed:45/255.0 green:45/255.0 blue:56/255.0 alpha:1.0];
    btnReplace.layer.cornerRadius = 8;
    [btnReplace setTitle:[NSString stringWithFormat:@"⇪ %@", localize(@"skin.editor.replace", @"Replace texture")] forState:UIControlStateNormal];
    [btnReplace setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnReplace.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [btnReplace addTarget:self action:@selector(actionPickSkin) forControlEvents:UIControlEventTouchUpInside];
    [_dialogView addSubview:btnReplace];
    curY += 46;

    // 2. Arm Style Section
    UILabel *lblArm = [[UILabel alloc] initWithFrame:CGRectMake(rightX, curY, colW, 18)];
    lblArm.text = localize(@"skin.editor.arm_style", @"Arm style");
    lblArm.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    lblArm.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_dialogView addSubview:lblArm];
    curY += 24;

    _btnWide = [self makeRadioButtonWithTitle:@"Wide" selector:@selector(actionSelectWide)];
    _btnWide.frame = CGRectMake(rightX, curY, 80, 30);
    [_dialogView addSubview:_btnWide];

    _btnSlim = [self makeRadioButtonWithTitle:@"Slim" selector:@selector(actionSelectSlim)];
    _btnSlim.frame = CGRectMake(rightX + 90, curY, 80, 30);
    [_dialogView addSubview:_btnSlim];
    curY += 42;

    // 3. Cape Section
    UILabel *lblCape = [[UILabel alloc] initWithFrame:CGRectMake(rightX, curY, colW, 18)];
    lblCape.text = localize(@"skin.editor.cape", @"Cape");
    lblCape.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    lblCape.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_dialogView addSubview:lblCape];
    curY += 22;

    _capeScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(rightX, curY, colW, 72)];
    _capeScrollView.showsHorizontalScrollIndicator = NO;
    [_dialogView addSubview:_capeScrollView];

    [self populateCapes];

    // Bottom Action Row
    CGFloat btnY = maxH - 54;
    UIButton *btnAdd = [UIButton buttonWithType:UIButtonTypeCustom];
    btnAdd.frame = CGRectMake(24, btnY, 110, 38);
    // Green accent like screenshot or Amethyst purple
    btnAdd.backgroundColor = [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0];
    btnAdd.layer.cornerRadius = 8;
    [btnAdd setTitle:[NSString stringWithFormat:@"✓ %@", (self.skinToEdit ? localize(@"Save", @"Save") : localize(@"skin.editor.add", @"Add skin"))] forState:UIControlStateNormal];
    [btnAdd setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnAdd.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [btnAdd addTarget:self action:@selector(actionSave) forControlEvents:UIControlEventTouchUpInside];
    [_dialogView addSubview:btnAdd];

    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeCustom];
    btnCancel.frame = CGRectMake(144, btnY, 90, 38);
    btnCancel.backgroundColor = [UIColor colorWithRed:45/255.0 green:45/255.0 blue:56/255.0 alpha:1.0];
    btnCancel.layer.cornerRadius = 8;
    [btnCancel setTitle:[NSString stringWithFormat:@"✕ %@", localize(@"Cancel", @"Cancel")] forState:UIControlStateNormal];
    [btnCancel setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
    btnCancel.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [btnCancel addTarget:self action:@selector(actionCancel) forControlEvents:UIControlEventTouchUpInside];
    [_dialogView addSubview:btnCancel];

    [self updateArmRadioButtons];
}

- (UIButton *)makeRadioButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)updateArmRadioButtons {
    BOOL isWide = (self.selectedArmStyle == SkinArmStyleWide);
    [self.btnWide setTitle:[NSString stringWithFormat:@"%@ Wide", isWide ? @"◉" : @"○"] forState:UIControlStateNormal];
    [self.btnWide setTitleColor:isWide ? [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0] : [UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];

    [self.btnSlim setTitle:[NSString stringWithFormat:@"%@ Slim", !isWide ? @"◉" : @"○"] forState:UIControlStateNormal];
    [self.btnSlim setTitleColor:!isWide ? [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0] : [UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];

    self.previewView.armStyle = self.selectedArmStyle;
}

- (void)actionSelectWide {
    self.selectedArmStyle = SkinArmStyleWide;
    [self updateArmRadioButtons];
}

- (void)actionSelectSlim {
    self.selectedArmStyle = SkinArmStyleSlim;
    [self updateArmRadioButtons];
}

- (void)populateCapes {
    for (UIView *v in self.capeScrollView.subviews) {
        [v removeFromSuperview];
    }
    [self.capeButtons removeAllObjects];

    NSArray<CapeItem *> *capes = [SkinManager sharedManager].availableCapes;
    CGFloat cardW = 54;
    CGFloat cardH = 68;
    CGFloat curX = 0;

    for (CapeItem *cape in capes) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(curX, 0, cardW, cardH);
        btn.layer.cornerRadius = 6;
        btn.clipsToBounds = YES;
        btn.layer.borderWidth = 1.5;
        BOOL isSel = [cape.capeId isEqualToString:self.selectedCapeId];
        btn.layer.borderColor = isSel ? [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0].CGColor : [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
        btn.backgroundColor = [UIColor colorWithRed:25/255.0 green:25/255.0 blue:32/255.0 alpha:1.0];

        if ([cape.capeId isEqualToString:@"none"]) {
            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(4, 8, cardW - 8, cardH - 16)];
            lbl.text = @"Use\ndefault\ncape";
            lbl.numberOfLines = 3;
            lbl.textAlignment = NSTextAlignmentCenter;
            lbl.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
            lbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
            [btn addSubview:lbl];
        } else {
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(11, 6, 32, 48)];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.image = [cape loadImage];
            [btn addSubview:iv];

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(2, cardH - 14, cardW - 4, 12)];
            lbl.text = cape.name;
            lbl.textAlignment = NSTextAlignmentCenter;
            lbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            lbl.font = [UIFont systemFontOfSize:7 weight:UIFontWeightRegular];
            [btn addSubview:lbl];
        }

        objc_setAssociatedObject(btn, "cape_id", cape.capeId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(actionSelectCapeBtn:) forControlEvents:UIControlEventTouchUpInside];
        [self.capeScrollView addSubview:btn];
        [self.capeButtons addObject:btn];

        curX += cardW + 8;
    }

    // "More" button to pick custom cape
    UIButton *btnMore = [UIButton buttonWithType:UIButtonTypeCustom];
    btnMore.frame = CGRectMake(curX, 0, 44, cardH);
    btnMore.layer.cornerRadius = 6;
    btnMore.backgroundColor = [UIColor colorWithRed:25/255.0 green:25/255.0 blue:32/255.0 alpha:1.0];
    btnMore.layer.borderWidth = 1.0;
    btnMore.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    UILabel *lblMore = [[UILabel alloc] initWithFrame:btnMore.bounds];
    lblMore.text = @"> \nMore";
    lblMore.numberOfLines = 2;
    lblMore.textAlignment = NSTextAlignmentCenter;
    lblMore.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    lblMore.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [btnMore addSubview:lblMore];
    [btnMore addTarget:self action:@selector(actionPickCustomCape) forControlEvents:UIControlEventTouchUpInside];
    [self.capeScrollView addSubview:btnMore];
    curX += 44 + 8;

    self.capeScrollView.contentSize = CGSizeMake(curX, cardH);
}

- (void)actionSelectCapeBtn:(UIButton *)sender {
    NSString *capeId = objc_getAssociatedObject(sender, "cape_id");
    self.selectedCapeId = capeId ?: @"none";
    for (UIButton *b in self.capeButtons) {
        NSString *cid = objc_getAssociatedObject(b, "cape_id");
        BOOL isSel = [cid isEqualToString:self.selectedCapeId];
        b.layer.borderColor = isSel ? [UIColor colorWithRed:16/255.0 green:185/255.0 blue:129/255.0 alpha:1.0].CGColor : [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    }
    [self updatePreview];
}

- (void)updatePreview {
    self.previewView.skinImage = self.selectedSkinImage;
    self.previewView.armStyle = self.selectedArmStyle;
    CapeItem *c = [[SkinManager sharedManager] capeForId:self.selectedCapeId];
    self.previewView.capeImage = [c loadImage];
}

- (void)actionPickSkin {
    UIAlertController *pickerSheet = [UIAlertController alertControllerWithTitle:localize(@"skin.pick.source", @"Choose skin image")
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    [pickerSheet addAction:[UIAlertAction actionWithTitle:localize(@"skin.pick.files", @"Files App (.png)")
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        self.isPickingCape = NO;
        UIDocumentPickerViewController *docPicker;
        if (@available(iOS 14.0, *)) {
            docPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePNG] asCopy:YES];
        } else {
            docPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.png"] inMode:UIDocumentPickerModeImport];
        }
        docPicker.delegate = self;
        [self presentViewController:docPicker animated:YES completion:nil];
    }]];

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [pickerSheet addAction:[UIAlertAction actionWithTitle:localize(@"skin.pick.photos", @"Photo Library")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
            self.isPickingCape = NO;
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        }]];
    }

    [pickerSheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    pickerSheet.popoverPresentationController.sourceView = self.dialogView;
    pickerSheet.popoverPresentationController.sourceRect = CGRectMake(self.dialogView.bounds.size.width / 2, self.dialogView.bounds.size.height / 2, 1, 1);
    [self presentViewController:pickerSheet animated:YES completion:nil];
}

- (void)actionPickCustomCape {
    self.isPickingCape = YES;
    UIDocumentPickerViewController *docPicker;
    if (@available(iOS 14.0, *)) {
        docPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePNG] asCopy:YES];
    } else {
        docPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.png"] inMode:UIDocumentPickerModeImport];
    }
    docPicker.delegate = self;
    [self presentViewController:docPicker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate & UIImagePickerControllerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    [url stopAccessingSecurityScopedResource];
    if (data) {
        UIImage *img = [UIImage imageWithData:data];
        if (self.isPickingCape) {
            // Save custom cape
            NSString *customCapePath = [[SkinManager sharedManager].skinsDirectory stringByAppendingPathComponent:@"user_custom_cape.png"];
            [data writeToFile:customCapePath atomically:YES];
            self.selectedCapeId = @"user_custom";
            self.previewView.capeImage = img;
            [self populateCapes];
        } else {
            self.selectedSkinImage = img;
            [self updatePreview];
        }
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        self.selectedSkinImage = img;
        [self updatePreview];
    }
}

- (void)actionSave {
    if (!self.selectedSkinImage) {
        [self actionCancel];
        return;
    }
    SkinItem *item = [[SkinManager sharedManager] addCustomSkinWithImage:self.selectedSkinImage
                                                                    name:nil
                                                                armStyle:self.selectedArmStyle
                                                                  capeId:self.selectedCapeId];
    if (self.whenSkinAdded) {
        self.whenSkinAdded(item);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
