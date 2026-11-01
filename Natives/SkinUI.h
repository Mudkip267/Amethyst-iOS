#import <UIKit/UIKit.h>
static inline UIColor *SkinAccent(void) { return [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1]; }
static inline UILabel *SkinLabel(NSString *text, CGFloat size) {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:size weight:UIFontWeightMedium]; label.numberOfLines = 0;
    return label;
}
static inline UIButton *SkinButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor; button.tintColor = SkinAccent(); button.layer.cornerRadius = 10;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
static inline void SkinAlert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
