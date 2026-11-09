#import <UIKit/UIKit.h>

BOOL AMEHorizonAvailable(void);
BOOL AMEHorizonHasGameFiles(void);
BOOL AMEHorizonLaunchPending(void);
BOOL AMEHorizonQueueLaunch(NSError **error);
BOOL AMEHorizonCancelLaunch(NSError **error);
BOOL AMEHorizonTryBoot(void);
BOOL AMEHorizonRunning(void);

@interface HorizonProfileViewController : UITableViewController
@end
