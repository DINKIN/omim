#import "MapsAppDelegate.h"
#import "MapViewController.h"
#import "SettingsManager.h"
#import "Preferences.h"
#import "LocationManager.h"
#import "Statistics.h"

#include <sys/xattr.h>

#include "Framework.h"

#include "../../../storage/storage.hpp"

#include "../../../platform/settings.hpp"
#include "../../../platform/platform.hpp"
#include "../../../platform/preferred_languages.hpp"


#define NOTIFICATION_ALERT_VIEW_TAG 665

/// Adds needed localized strings to C++ code
/// @TODO Refactor localization mechanism to make it simpler
void InitLocalizedStrings()
{
  Framework & f = GetFramework();
  // Texts on the map screen when map is not downloaded or is downloading
  f.AddString("country_status_added_to_queue", [NSLocalizedString(@"country_status_added_to_queue", @"Message to display at the center of the screen when the country is added to the downloading queue") UTF8String]);
  f.AddString("country_status_downloading", [NSLocalizedString(@"country_status_downloading", @"Message to display at the center of the screen when the country is downloading") UTF8String]);
  f.AddString("country_status_download", [NSLocalizedString(@"country_status_download", @"Button text for the button at the center of the screen when the country is not downloaded") UTF8String]);
  f.AddString("country_status_download_failed", [NSLocalizedString(@"country_status_download_failed", @"Message to display at the center of the screen when the country download has failed") UTF8String]);
  f.AddString("try_again", [NSLocalizedString(@"try_again", @"Button text for the button under the country_status_download_failed message") UTF8String]);
  // Default texts for bookmarks added in C++ code (by URL Scheme API)
  f.AddString("dropped_pin", [NSLocalizedString(@"dropped_pin", nil) UTF8String]);
  f.AddString("my_places", [NSLocalizedString(@"my_places", nil) UTF8String]);
}

@interface MapsAppDelegate()
@property (nonatomic, retain) NSString * lastGuidesUrl;
@end

@implementation MapsAppDelegate

@synthesize m_mapViewController;
@synthesize m_locationManager;


+ (MapsAppDelegate *) theApp
{
  return (MapsAppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (void) applicationWillTerminate: (UIApplication *) application
{
	[m_mapViewController OnTerminate];
}

- (void) applicationDidEnterBackground: (UIApplication *) application
{
	[m_mapViewController OnEnterBackground];
  if(m_activeDownloadsCounter)
  {
    m_backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
      [application endBackgroundTask:m_backgroundTask];
      m_backgroundTask = UIBackgroundTaskInvalid;
    }];
  }
}

- (void) applicationWillEnterForeground: (UIApplication *) application
{
  [m_locationManager orientationChanged];
  [m_mapViewController OnEnterForeground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
  if (GetPlatform().IsPro() && !m_didOpenedWithUrl)
  {
    UIPasteboard * pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.string.length)
    {
      if (GetFramework().ShowMapForURL([pasteboard.string UTF8String]))
      {
        [self showMap];

        pasteboard.string = @"";
      }
    }
  }

  m_didOpenedWithUrl = NO;
}

- (SettingsManager *)settingsManager
{
  if (!m_settingsManager)
    m_settingsManager = [[SettingsManager alloc] init];
  return m_settingsManager;
}

- (void) dealloc
{
  [m_locationManager release];
  [m_settingsManager release];
  self.m_mapViewController = nil;
  [m_navController release];
  [m_window release];
  self.lastGuidesUrl = nil;
  [super dealloc];

  // Global cleanup
  DeleteFramework();
}

- (void) disableStandby
{
  ++m_standbyCounter;
  [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void) enableStandby
{
  --m_standbyCounter;
  if (m_standbyCounter <= 0)
  {
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    m_standbyCounter = 0;
  }
}

- (void) disableDownloadIndicator
{
  --m_activeDownloadsCounter;
  if (m_activeDownloadsCounter <= 0)
  {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    m_activeDownloadsCounter = 0;
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground)
    {
      [[UIApplication sharedApplication] endBackgroundTask:m_backgroundTask];
      m_backgroundTask = UIBackgroundTaskInvalid;
    }
  }
}

- (void) enableDownloadIndicator
{
  ++m_activeDownloadsCounter;
  [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

// We process memory warnings in MapsViewController
//- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
//{
//  NSLog(@"applicationDidReceiveMemoryWarning");
//}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  NSLog(@"application didFinishLaunchingWithOptions");
  [[Statistics instance] startSession];

  InitLocalizedStrings();

  [m_mapViewController OnEnterForeground];

  [Preferences setup:m_mapViewController];
  m_locationManager = [[LocationManager alloc] init];

  m_navController = [[UINavigationController alloc] initWithRootViewController:m_mapViewController];
  m_navController.navigationBarHidden = YES;
  m_navController.delegate = self;
  m_window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  m_window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  m_window.clearsContextBeforeDrawing = NO;
  m_window.multipleTouchEnabled = YES;
  [m_window setRootViewController:m_navController];
  [m_window makeKeyAndVisible];

  m_didOpenedWithUrl = NO;

  if (GetPlatform().IsPro())
  {
    int val = 0;
    if (Settings::Get("NumberOfBookmarksPerSession", val))
      [[Statistics instance] logEvent:@"Bookmarks Per Session" withParameters:@{@"Number of bookmarks" : [NSNumber numberWithInt:val]}];
    Settings::Set("NumberOfBookmarksPerSession", 0);
  }

  [self subscribeToStorage];

  std::vector<guides::GuideInfo> guides;
  GetFramework().GetGuidesInfosWithDownloadedMaps(guides);
  for (size_t i = 0; i < guides.size();++i)
    if ([self ShowNotificationWithGuideInfo:guides[i]])
      break;

  return [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey] != nil;
}

-(void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
  NSDictionary * dict = notification.userInfo;
  if ([[dict objectForKey:@"Proposal"] isEqual:@"OpenGuides"])
  {
    self.lastGuidesUrl = [dict objectForKey:@"GuideUrl"];
    UIAlertView * view = [[UIAlertView alloc] initWithTitle:[dict objectForKey:@"GuideTitle"] message:[dict objectForKey:@"GuideMessage"] delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:NSLocalizedString(@"get_it_now", nil), nil];
    view.tag = NOTIFICATION_ALERT_VIEW_TAG;
    [view show];
    [view release];
  }
}

// We don't support HandleOpenUrl as it's deprecated from iOS 4.2
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
  NSString * scheme = url.scheme;
  Framework & f = GetFramework();

  // geo scheme support, see http://tools.ietf.org/html/rfc5870
  if ([scheme isEqualToString:@"geo"] || [scheme isEqualToString:@"ge0"])
  {
    if (f.ShowMapForURL([url.absoluteString UTF8String]))
    {
      m_didOpenedWithUrl = YES;

      if ([scheme isEqualToString:@"geo"])
        [[Statistics instance] logEvent:@"geo Import"];
      if ([scheme isEqualToString:@"ge0"])
        [[Statistics instance] logEvent:@"ge0(zero) Import"];

      [self showMap];
      return YES;
    }
  }

  if ([scheme isEqualToString:@"mapswithme"] || [scheme isEqualToString:@"mwm"])
  {
    if (f.ShowMapForURL([url.absoluteString UTF8String]));
    {
      m_didOpenedWithUrl = YES;
      [[Statistics instance] logApiUsage:sourceApplication];

      [self showMap];
      [m_mapViewController prepareForApi];
      return YES;
    }
  }

  if ([scheme isEqualToString:@"file"])
  {
     if (!f.AddBookmarksFile([[url relativePath] UTF8String]))
     {
       [self showLoadFileAlertIsSuccessful:NO];
       return NO;
     }
     [[NSNotificationCenter defaultCenter] postNotificationName:@"KML file added" object:nil];
     [self showLoadFileAlertIsSuccessful:YES];
     m_didOpenedWithUrl = YES;
     [[Statistics instance] logEvent:@"KML Import"];
     return YES;
  }
  NSLog(@"Scheme %@ is not supported", scheme);
  return NO;
}

-(void)showLoadFileAlertIsSuccessful:(BOOL) successful
{
  m_loadingAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"load_kmz_title", nil)
                                                  message:
                        (successful ? NSLocalizedString(@"load_kmz_successful", nil) : NSLocalizedString(@"load_kmz_failed", nil))
                                                 delegate:nil
                                      cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil];
  m_loadingAlertView.delegate = self;
  [m_loadingAlertView show];
  [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(dismissAlert) userInfo:nil repeats:NO];
  [m_loadingAlertView release];
}

-(void)dismissAlert
{
  if (m_loadingAlertView)
    [m_loadingAlertView dismissWithClickedButtonIndex:0 animated:YES];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
  if (alertView.tag == NOTIFICATION_ALERT_VIEW_TAG)
  {
    if (buttonIndex != alertView.cancelButtonIndex)
    {
      [[Statistics instance] logEvent:@"Download Guides Proposal" withParameters:@{@"Answer" : @"YES"}];
      NSURL * url = [NSURL URLWithString:self.lastGuidesUrl];
      [[UIApplication sharedApplication] openURL:url];
    }
    else
      [[Statistics instance] logEvent:@"Download Guides Proposal" withParameters:@{@"Answer" : @"NO"}];
  }
  else
    m_loadingAlertView = nil;
}

-(void)showMap
{
  [m_navController popToRootViewControllerAnimated:YES];
  [m_mapViewController dismissPopover];
  if (![m_navController.visibleViewController isMemberOfClass:NSClassFromString(@"MapViewController")])
    [m_mapViewController dismissModalViewControllerAnimated:YES];
  [m_navController setNavigationBarHidden:YES animated:YES];
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  if ([viewController isMemberOfClass:NSClassFromString(@"MapViewController")] && ![m_mapViewController shouldShowNavBar])
    [m_navController setNavigationBarHidden:YES animated:YES];
}

-(void)subscribeToStorage
{
  typedef void (*TChangeFunc)(id, SEL, storage::TIndex const &);
  SEL changeSel = @selector(OnCountryChange:);
  TChangeFunc changeImpl = (TChangeFunc)[self methodForSelector:changeSel];

  typedef void (*TProgressFunc)(id, SEL, storage::TIndex const &, pair<int64_t, int64_t> const &);
  SEL emptySel = @selector(EmptyFunction:withProgress:);
  TProgressFunc progressImpl = (TProgressFunc)[self methodForSelector:emptySel];

  GetFramework().Storage().Subscribe(bind(changeImpl, self, changeSel, _1),
                                   bind(progressImpl, self, emptySel, _1, _2));
}

- (void) OnCountryChange: (storage::TIndex const &)index
{
  Framework const & f = GetFramework();
  guides::GuideInfo guide;
  if (f.GetCountryStatus(index) == storage::EOnDisk && f.GetGuideInfo(index, guide))
    [self ShowNotificationWithGuideInfo:guide];
}

- (void) EmptyFunction: (storage::TIndex const &) index withProgress: (pair<int64_t, int64_t> const &) progress
{
}

-(BOOL) ShowNotificationWithGuideInfo:(guides::GuideInfo const &)guide
{
  guides::GuidesManager & guidesManager = GetFramework().GetGuidesManager();
  string const appID = guide.GetAppID();

  if (guidesManager.WasAdvertised(appID) ||
      [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:[NSString stringWithUTF8String:appID.c_str()]]])
    return NO;

  UILocalNotification * notification = [[UILocalNotification alloc] init];
  notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
  notification.repeatInterval = 0;
  notification.timeZone = [NSTimeZone defaultTimeZone];
  notification.soundName = UILocalNotificationDefaultSoundName;

  string const lang = languages::CurrentLanguage();
  NSString * message = [NSString stringWithUTF8String:guide.GetAdMessage(lang).c_str()];
  notification.alertBody = message;
  notification.userInfo = @{
                            @"Proposal" : @"OpenGuides",
                            @"GuideUrl" : [NSString stringWithUTF8String:guide.GetURL().c_str()],
                            @"GuideTitle" : [NSString stringWithUTF8String:guide.GetAdTitle(lang).c_str()],
                            @"GuideMessage" : message
                            };

  [[UIApplication sharedApplication] scheduleLocalNotification:notification];
  [notification release];

  guidesManager.SetWasAdvertised(appID);
  return YES;
}

@end
