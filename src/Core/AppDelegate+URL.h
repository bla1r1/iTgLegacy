#import "AppDelegate.h"

@interface AppDelegate (URL)

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation;

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url;

@end
