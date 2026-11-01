#import "SkinEditorViewController.h"
#import "SkinUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>

// Keep child layout independent of the button tag used for cape selection.
@interface SkinCapeCard : UIButton
@property(nonatomic, strong) UIImageView *picture;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *emptyLabel;
@end
@implementation SkinCapeCard
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.picture.frame = CGRectMake(12,12,MAX(0,width-24),MAX(0,height-70));
    self.nameLabel.frame = CGRectMake(6,MAX(0,height-52),MAX(0,width-12),46);
    self.emptyLabel.frame = self.picture.frame;
}
@end

@interface SkinEditorViewController () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property UIScrollView *scroll;
@property SkinPreviewView *preview;
@property UISegmentedControl *modelChoice;
@property UIButton *importButton;
@property UILabel *capeTitle;
@property UILabel *hint;
@property UIImage *image;
@property NSString *capeId;
@property NSMutableArray<SkinCapeCard *> *capeCards;
@property BOOL openedImport;
@end
@implementation SkinEditorViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Edit skin / Cape";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor; self.view.tintColor = SkinAccent();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    self.scroll = [UIScrollView new]; [self.view addSubview:self.scroll];
    self.preview = [[SkinPreviewView alloc] initWithFrame:CGRectZero]; [self.scroll addSubview:self.preview];
    self.modelChoice = [[UISegmentedControl alloc] initWithItems:@[@"Classic",@"Slim"]]; self.modelChoice.selectedSegmentIndex = self.skinToEdit.armStyle;
    [self.modelChoice addTarget:self action:@selector(updatePreview) forControlEvents:UIControlEventValueChanged]; [self.scroll addSubview:self.modelChoice];
    self.importButton = SkinButton(@"Choose skin image…",self,@selector(pick)); [self.scroll addSubview:self.importButton];
    self.hint = SkinLabel(@"PNG skin, 64 × 64 or 64 × 32 pixels. Imported images replace the selected skin tile. Save keeps a local draft; use Apply to account to publish it.",12);
    self.hint.textColor = UIColor.secondaryLabelColor; [self.scroll addSubview:self.hint];
    self.capeTitle = SkinLabel(@"Choose your cape",21); [self.scroll addSubview:self.capeTitle];
    self.image = [self.skinToEdit loadImage]; self.capeId = self.skinToEdit.capeId ?: @"none";
    self.capeCards = [NSMutableArray array];
    NSArray<CapeItem *> *capes = [SkinManager sharedManager].availableCapes;
    for (NSInteger i = 0; i < capes.count; i++) {
        CapeItem *cape = capes[i];
        SkinCapeCard *card = [SkinCapeCard buttonWithType:UIButtonTypeCustom];
        card.tag = i; card.layer.borderColor = SkinAccent().CGColor;
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        card.layer.cornerRadius = 10; card.clipsToBounds = YES;
        [card addTarget:self action:@selector(selectCape:) forControlEvents:UIControlEventTouchUpInside];
        UIImage *texture = [cape loadImage];
        UIImageView *picture = [UIImageView new]; picture.contentMode = UIViewContentModeScaleAspectFit; picture.layer.magnificationFilter = kCAFilterNearest;
        if (texture.CGImage) {
            CGFloat scale = CGImageGetWidth(texture.CGImage)/64.0;
            CGImageRef front = CGImageCreateWithImageInRect(texture.CGImage,CGRectMake(scale,scale,10*scale,16*scale));
            if (front) { picture.image = [UIImage imageWithCGImage:front]; CGImageRelease(front); }
        }
        card.picture = picture; [card addSubview:picture];
        UILabel *name = SkinLabel(cape.name,14); name.textAlignment = NSTextAlignmentCenter; card.nameLabel = name; [card addSubview:name];
        if ([cape.capeId isEqual:@"none"]) {
            UILabel *empty = SkinLabel(@"∅",48); empty.textAlignment = NSTextAlignmentCenter; empty.textColor = UIColor.tertiaryLabelColor; card.emptyLabel = empty; [card addSubview:empty];
        }
        [self.scroll addSubview:card]; [self.capeCards addObject:card];
    }
    [self updatePreview];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.importOnOpen && !self.openedImport) { self.openedImport = YES; [self pick]; }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; self.scroll.frame = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGFloat width = self.scroll.bounds.size.width;
    BOOL wide = width > 620;
    CGFloat left = wide ? MIN(300,width*0.36) : width-32;
    self.preview.frame = CGRectMake(16,12,left,250);
    self.modelChoice.frame = CGRectMake(16,274,left,36);
    self.importButton.frame = CGRectMake(16,322,left,44);
    self.hint.frame = CGRectMake(16,378,left,76);
    CGFloat x = wide ? left+32 : 16, y = wide ? 12 : 474, available = width-x-16;
    self.capeTitle.frame = CGRectMake(x,y,available,30); y += 42;
    NSInteger cols = MAX(2,(NSInteger)((available+12)/148));
    CGFloat cardWidth = (available-12*(cols-1))/cols, cardHeight = cardWidth*1.4+54;
    for (NSInteger i = 0; i < self.capeCards.count; i++) {
        SkinCapeCard *card = self.capeCards[i]; card.frame = CGRectMake(x+(i%cols)*(cardWidth+12), y+(i/cols)*(cardHeight+12),cardWidth,cardHeight);
    }
    self.scroll.contentSize = CGSizeMake(width,MAX(466,y+((self.capeCards.count+cols-1)/cols)*(cardHeight+12))+16);
}
- (void)updatePreview {
    self.preview.skinImage = self.image; self.preview.armStyle = self.modelChoice.selectedSegmentIndex;
    self.preview.capeImage = [[[SkinManager sharedManager] capeForId:self.capeId] loadImage];
    NSArray<CapeItem *> *capes = [SkinManager sharedManager].availableCapes;
    for (UIButton *card in self.capeCards) {
        if (card.tag >= capes.count) continue;
        BOOL selected = [capes[card.tag].capeId isEqual:self.capeId]; card.layer.borderWidth = selected ? 2 : 0;
        card.accessibilityLabel = capes[card.tag].name; card.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
}
- (void)selectCape:(UIButton *)sender {
    NSArray<CapeItem *> *capes = [SkinManager sharedManager].availableCapes;
    if (sender.tag < capes.count) self.capeId = capes[sender.tag].capeId;
    [self updatePreview];
}
- (void)pick {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose skin image" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Files (.png)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker;
        if (@available(iOS 14.0,*)) picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePNG] asCopy:YES];
        else picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.png"] inMode:UIDocumentPickerModeImport];
        picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIImagePickerController *picker = [UIImagePickerController new]; picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.importButton; sheet.popoverPresentationController.sourceRect = self.importButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)acceptImage:(UIImage *)image {
    size_t w = image.CGImage ? CGImageGetWidth(image.CGImage) : 0, h = image.CGImage ? CGImageGetHeight(image.CGImage) : 0;
    if (w != 64 || (h != 64 && h != 32) || image.imageOrientation != UIImageOrientationUp) {
        SkinAlert(self,@"Invalid skin",@"Choose the original 64 × 64 or 64 × 32 skin PNG, rather than a screenshot or a rotated photo."); return;
    }
    self.image = image;
    if (h == 32) self.modelChoice.selectedSegmentIndex = SkinArmStyleWide;
    [self updatePreview];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSNumber *bytes = nil; [url getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
    NSData *data = bytes && bytes.unsignedLongLongValue <= 1024*1024 ? [NSData dataWithContentsOfURL:url] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];
    // Inspect dimensions before decoding untrusted image data.
    CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL) : NULL;
    NSDictionary *info = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
    if (source) CFRelease(source);
    NSInteger w = [info[(NSString *)kCGImagePropertyPixelWidth] integerValue], h = [info[(NSString *)kCGImagePropertyPixelHeight] integerValue];
    UIImage *image = w == 64 && (h == 64 || h == 32) ? [UIImage imageWithData:data] : nil;
    [self acceptImage:image];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{ [self acceptImage:image]; }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    if (!self.image) { SkinAlert(self,@"Choose a skin",@"Select a valid skin image first."); return; }
    SkinItem *draft = [SkinItem fromDictionary:self.skinToEdit.toDictionary];
    draft.armStyle = self.modelChoice.selectedSegmentIndex; draft.capeId = self.capeId;
    SkinItem *saved = [[SkinManager sharedManager] saveDraft:draft image:self.image];
    if (!saved) { SkinAlert(self,@"Could not save",@"The skin image could not be saved. Check available storage and try again."); return; }
    if (self.whenSkinAdded) self.whenSkinAdded(saved);
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
