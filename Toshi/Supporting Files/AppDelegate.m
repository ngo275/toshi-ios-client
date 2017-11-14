
#import "AppDelegate.h"

#import "Toshi-Swift.h"

#import "NSData+ows_StripToken.h"
#import "EmptyCallHandler.h"

#import <EtherealCereal/EtherealCereal.h>

#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <SignalServiceKit/OWSDispatch.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import "ProfileManager.h"

#import <AxolotlKit/SessionCipher.h>

NSString *const LaunchedBefore = @"LaunchedBefore";
NSString *const RequiresSignIn = @"RequiresSignIn";

@import WebRTC;

@interface AppDelegate ()

@property (nonatomic) UIWindow *screenProtectionWindow;

@property (nonatomic, copy, readwrite) NSString *token;
@property (nonatomic) NSString *voipToken;

@end

@implementation AppDelegate
@synthesize token = _token;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSString *tokenChatServiceBaseURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"TokenChatServiceBaseURL"];
    [OWSSignalService setBaseURLPath:tokenChatServiceBaseURL];

    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.

    srand((unsigned int)time(NULL));

    [APIKeysManager setup];

    [Theme setupBasicAppearance];

    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

    if (![Yap isUserDatabaseFileAccessible] && ![Yap isUserDatabasePasswordAccessible]) {
        [self configureAndPresentWindow];

        return YES;
    }

    BOOL shouldProceedToDBSetup = ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground);
    if (shouldProceedToDBSetup) {

        if ([self __tryToOpenDB]) {
            [self configureForCurrentSession];
        } else {

            // There might be a case when filesystem state is weird and it doesn't return true results, saying file is not present even if it is.
            // to determine this we might check keychain for database password being there
            // in this case we want to wait a bit and try to open file again
            // if it still fails - both password and database file, whatever is present in Yap, is deleted and splash is presented

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([self __tryToOpenDB]) {
                    [self configureForCurrentSession];
                } else {
                    [Yap.sharedInstance processInconsistencyError];
                    [self configureAndPresentWindow];
                }
            });
        }
    }

    return YES;
}

+ (NSString *)documentsPath
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      NSString *groupName = [@"group." stringByAppendingString:[[NSBundle mainBundle] bundleIdentifier]];

                      NSURL *groupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupName];
                      if (groupURL != nil)
                      {
                          NSString *documentsPath = [[groupURL path] stringByAppendingPathComponent:@"Documents"];

                          [[NSFileManager defaultManager] createDirectoryAtPath:documentsPath withIntermediateDirectories:true attributes:nil error:NULL];

                          path = documentsPath;
                      }
                      else
                          path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true)[0];
                  });

    return path;
}

- (void)configureAndPresentWindow {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [Theme viewBackgroundColor];
    TabBarController *tabBarController = [[TabBarController alloc] init];
    self.window.rootViewController = tabBarController;

    [self.window makeKeyAndVisible];

    if (![Yap isUserDatabaseFileAccessible] || ![Yap isUserDatabasePasswordAccessible]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[NSString addressChangeAlertShown]]; //suppress alert for users created >=v1.1.2
        [[NSUserDefaults standardUserDefaults] synchronize];

        [self presentSplash];
    } else {
        [tabBarController setupControllers];
    }
}

- (void)showNetworkAlertIfNeeded {
    // To drive this point really home we could show this for every launch instead.
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DidShowMoneyAlert"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"network-alert-title", nil) message:NSLocalizedString(@"network-alert-text", nil) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"alert-ok-action-title", nil) style:UIAlertActionStyleCancel handler:nil]];
        alert.view.tintColor = Theme.tintColor;

        [self.window.rootViewController presentViewController:alert animated:YES completion:^{
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DidShowMoneyAlert"];
        }];
    }
}

- (void)signOutUser
{
    __weak typeof(self)weakSelf = self;
    [TSAccountManager unregisterTextSecureWithSuccess:^{

        typeof(self)strongSelf = weakSelf;

        [[NSNotificationCenter defaultCenter] postNotificationName:@"UserDidSignOut" object:nil];
        [AvatarManager.shared cleanCache];

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[EthereumAPIClient shared] deregisterFromMainNetworkPushNotifications];
        [[TSStorageManager sharedManager] resetSignalStorageWithBackup:TokenUser.current.verified];
        [[Yap sharedInstance] wipeStorage];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RequiresSignIn];
        [[NSUserDefaults standardUserDefaults] synchronize];

        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

        [strongSelf.contactsManager refreshContacts];

        exit(0);
    } failure:^(NSError *error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"sign-out-failure-title", nil) message:NSLocalizedString(@"sign-out-failure-message", nil) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"alert-ok-action-title", nil) style:UIAlertActionStyleCancel handler:nil]];

        [Navigator presentModally:alert];
    }];
}

- (void)createNewUser
{
    [[Navigator tabbarController] setupControllers];

    __weak typeof(self)weakSelf = self;
    [[IDAPIClient shared] registerUserIfNeeded:^(UserRegisterStatus status, NSString *message){

        if (status != UserRegisterStatusFailed) {

            typeof(self)strongSelf = weakSelf;

            [strongSelf didCreateUser];
            [strongSelf setupDB];

            [[ChatAPIClient shared] registerUserWithCompletion:^(BOOL success, NSString *message) {
                if (status == UserRegisterStatusRegistered) {
                    [ChatInteractor triggerBotGreeting];
                }
            }];
        }
    }];
}

- (void)signInUser
{
    [self showNetworkAlertIfNeeded];
    [self setupDB];

    [[Navigator tabbarController] setupControllers];
}

- (void)setupDB
{
    [self setupTSKitEnv];
    [self setupSignalService];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"ChatDatabaseCreated" object:nil];
}

- (void)didCreateUser {
    [self.contactsManager refreshContacts];

    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:RequiresSignIn];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [Navigator presentAddressChangeAlertIfNeeded];
}

- (void)presentSplash
{
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed: @"launch-screen"]];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.userInteractionEnabled = YES;
    [self.window addSubview:imageView];

    SplashNavigationController *splashNavigationController = [[SplashNavigationController alloc] init];
    [self.window.rootViewController presentViewController:splashNavigationController animated:NO completion:^{
        [imageView removeFromSuperview];
    }];
}

- (void)setupSignalService {
    // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
    [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];

    [CrashlyticsClient setupForUserWith:[[Cereal shared] address]];

    __weak typeof(self)weakSelf = self;

    [TSSocketManager requestSocketOpen];
    RTCInitializeSSL();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        typeof(self)strongSelf = weakSelf;
        [strongSelf registerForRemoteNotifications];
    });
}

- (BOOL)isFirstLaunch
{
    return  [[NSUserDefaults standardUserDefaults] boolForKey:LaunchedBefore] == NO;
}

- (void)setupTSKitEnv {
    NSLog(@"Setting up Signal KIT environment");

    // ensure this is called from main queue for the first time
    // otherwise app crashes, because of some code path differences between
    // us and Signal app.
    [OWSSignalService sharedInstance];

    self.networkManager = [TSNetworkManager sharedManager];
    self.contactsManager = [[ContactsManager alloc] init];

    self.contactsUpdater = [ContactsUpdater sharedUpdater];

    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager setupForAccountName:TokenUser.current.address isFirstLaunch:[self isFirstLaunch]];

    [[TSAccountManager sharedInstance] storeLocalNumber:[Cereal shared].address];

    if (![storageManager database]) {
        [CrashlyticsLogger log:@"Failed to create chat databse for the suer" attributes:nil];
    }

    self.messageSender = [[OWSMessageSender alloc] initWithNetworkManager:self.networkManager storageManager:storageManager contactsManager:self.contactsManager contactsUpdater:self.contactsUpdater];

    TextSecureKitEnv *sharedEnv = [[TextSecureKitEnv alloc] initWithCallMessageHandler:[EmptyCallHandler new] contactsManager:self.contactsManager messageSender:self.messageSender notificationsManager:[SignalNotificationManager new] profileManager:ProfileManager.sharedManager];

    [TextSecureKitEnv setSharedEnv:sharedEnv];

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:LaunchedBefore];
}

- (BOOL)isSendingIdentityApprovalRequired
{
    return NO;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    if ([TSAccountManager isRegistered]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activateScreenProtection];
            // [TSSocketManager resignActivity];
        });
    }
}

- (BOOL)__tryToOpenDB
{
    if ([Yap isUserDatabaseFileAccessible] && [Yap isUserDatabasePasswordAccessible]) {
        [TokenUser retrieveCurrentUser];
        [self setupDB];

        return YES;
    }

    [CrashlyticsLogger log:Yap.inconsistentStateDescription attributes:nil];

    return NO;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

    if ([TSAccountManager isRegistered]) {
        [TSSocketManager requestSocketOpen];
    }

    // Send screen protection deactivation to the same queue as when resigning
    // to avoid some weird UIKit issue where app is going inactive during the launch process
    // and back to active again. Due to the queue difference, some racing conditions may apply
    // leaving the app with a protection screen when it shouldn't have any.

    dispatch_async(dispatch_get_main_queue(), ^{
        [self deactivateScreenProtection];
    });

    [TSPreKeyManager checkPreKeysIfNecessary];
}

- (void)activateScreenProtection {

    if (self.screenProtectionWindow == nil) {
        UIWindow *window = [[UIWindow alloc] init];
        window.hidden = YES;
        window.backgroundColor = [UIColor clearColor];
        window.userInteractionEnabled = NO;
        window.windowLevel = CGFLOAT_MAX;
        window.alpha = 0;

        UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
        [window addSubview:effectView];

        [effectView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [[effectView.topAnchor constraintEqualToAnchor:window.topAnchor] setActive:YES];
        [[effectView.leftAnchor constraintEqualToAnchor:window.leftAnchor] setActive:YES];
        [[effectView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor] setActive:YES];
        [[effectView.rightAnchor constraintEqualToAnchor:window.rightAnchor] setActive:YES];

        self.screenProtectionWindow = window;
    }

    [UIView animateWithDuration:0.3 animations:^{
        self.screenProtectionWindow.alpha = 1;
    }];

    self.screenProtectionWindow.hidden = NO;
}

- (void)configureForCurrentSession
{
    [self configureAndPresentWindow];
    [SignalNotificationManager updateUnreadMessagesNumber];
}

- (void)deactivateScreenProtection
{
    if (self.screenProtectionWindow.alpha == 0) {
        return;
    }

    [UIView animateWithDuration:0.3 animations:^{
        self.screenProtectionWindow.alpha = 0;
    } completion:^(BOOL finished) {
        self.screenProtectionWindow.hidden = YES;
    }];
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if ([url.scheme isEqualToString:@"toshi"]) {
        TabBarController *controller = (TabBarController *)self.window.rootViewController;
        [controller openDeepLinkURL:url];

        return YES;
    }

    return NO;
}

#pragma mark - Accessors

- (NSString *)token {
    if (!_token) {
        _token = @"";
    }

    return _token;
}

- (void)setToken:(NSString *)token {
    _token = token;

    [self updateRemoteNotificationCredentials];
}

#pragma mark - Push notifications

- (void)registerForRemoteNotifications {
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error){
            @throw error.localizedDescription;
        } else if (granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            });
        }
    }];


    PKPushRegistry *voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)updateRemoteNotificationCredentials {
    NSLog(@"\n||--------------------\n||\n|| --- Account is registered: %@ \n||\n||--------------------\n\n", @([TSAccountManager isRegistered]));

    [[TSAccountManager sharedInstance] registerForPushNotificationsWithPushToken:self.token voipToken:nil success:^{
        NSLog(@"\n\n||------- \n||\n|| - TOKEN: chat PN register - SUCCESS: token: %@,\n|| - voip: %@\n||\n||------- \n", self.token, self.voipToken);

        [[EthereumAPIClient shared] registerForMainNetworkPushNotifications];

        [[EthereumAPIClient shared] registerForSwitchedNetworkPushNotificationsIfNeededWithCompletion:nil];

    } failure:^(NSError *error) {
        NSLog(@"\n\n||------- \n|| - TOKEN: chat PN register - FAILURE: %@\n||------- \n", error.localizedDescription);
        [CrashlyticsLogger log:@"Failed to register for PNs" attributes:@{@"error": error.localizedDescription}];
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    [BackgroundNotificationHandler handle:notification :^(UNNotificationPresentationOptions options) {
        completionHandler(options);
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    NSString *identifier = response.notification.request.content.threadIdentifier;
    [Navigator navigateTo:identifier animated:YES];

    completionHandler();
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    self.token = [deviceToken hexadecimalString];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"Failed to register for remote notifications. %@", error);
}

@end

