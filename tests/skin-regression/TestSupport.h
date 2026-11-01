#import <Foundation/Foundation.h>
NSString *localize(NSString *key, NSString *comment);
NSMutableDictionary *parseJSONFromFile(NSString *path);
NSError *saveJSONToFile(NSDictionary *dict, NSString *path);
