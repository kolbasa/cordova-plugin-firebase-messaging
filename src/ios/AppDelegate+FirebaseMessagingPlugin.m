#import "AppDelegate+FirebaseMessagingPlugin.h"
#import "FirebaseMessagingPlugin.h"
#import <objc/runtime.h>

@implementation AppDelegate (FirebaseMessagingPlugin)

// Borrowed from http://nshipster.com/method-swizzling/
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(application:didFinishLaunchingWithOptions:);
        SEL swizzledSelector = @selector(identity_application:didFinishLaunchingWithOptions:);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod =
        class_addMethod(class,
                        originalSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (BOOL)identity_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // always call original method implementation first
    BOOL handled = [self identity_application:application didFinishLaunchingWithOptions:launchOptions];

    [UNUserNotificationCenter currentNotificationCenter].delegate = self;

//    if (launchOptions) {
//        NSDictionary *userInfo = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
//        if (userInfo) {
//            [self postNotification:userInfo background:TRUE];
//        }
//    }

    return handled;
}

- (FirebaseMessagingPlugin*) getPluginInstance {
    return [self.viewController getCommandInstance:@"FirebaseMessaging"];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    FirebaseMessagingPlugin* fcmPlugin = [self getPluginInstance];
    if (application.applicationState != UIApplicationStateActive) {
        [fcmPlugin sendBackgroundNotification:userInfo];
    } else {
        [fcmPlugin sendNotification:userInfo];
    }

    completionHandler(UIBackgroundFetchResultNewData);
}

- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    FirebaseMessagingPlugin* fcmPlugin = [self getPluginInstance];

    [fcmPlugin sendToken:fcmToken];
}

# pragma mark - UNUserNotificationCenterDelegate
// handle incoming notification messages while app is in the foreground
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    NSDictionary *userInfo = notification.request.content.userInfo;
    FirebaseMessagingPlugin* fcmPlugin = [self getPluginInstance];

    [fcmPlugin sendNotification:userInfo];

    completionHandler([self getPluginInstance].forceShow);
}

// handle notification messages after display notification is tapped by the user
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    FirebaseMessagingPlugin* fcmPlugin = [self getPluginInstance];

    [fcmPlugin sendBackgroundNotification:userInfo];

    completionHandler();
}

static NSNumber* notificationId = nil;

- (void)localNotification:(CDVInvokedUrlCommand *)command {
    NSString* title = [NSString stringWithFormat:@"%@", [command.arguments objectAtIndex:0]];
    NSDictionary* options = [command.arguments objectAtIndex:1];

    NSString* text;
    NSTimeInterval timeout = 0;

    if (notificationId == nil) {
        notificationId = [NSNumber numberWithInteger:0];
    }

    notificationId = [NSNumber numberWithInt:[notificationId intValue] + 1];

    if (options != nil && [options isKindOfClass:[NSDictionary class]]) {
        text = options[@"text"];

        NSNumber* _timeout = options[@"timeout"];
        if (_timeout != nil) {
            timeout = [_timeout doubleValue];
        }

        NSNumber* _notificationId = options[@"id"];
        if (_notificationId != nil) {
            notificationId = _notificationId;
        }
    }

    NSLog(@"%@", title);
    NSLog(@"%@", notificationId);
    NSLog(@"%@", [NSString stringWithFormat:@"%0.2f", timeout]);

    // Create the notification content
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = text;
    content.sound = [UNNotificationSound defaultSound];

    // Create the trigger for the notification
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];

    // Create the notification request
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[notificationId stringValue] content:content trigger:trigger];

    // Schedule the notification
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    __weak UNUserNotificationCenter *weakCenter = center;
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"Error scheduling notification: %@", error);
            return;
        }

        if (timeout == 0) {
            return;
        }

        // Remove the delivered notification after the specified time interval
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakCenter removeDeliveredNotificationsWithIdentifiers:@[request.identifier]];
        });
    }];
}

@end
