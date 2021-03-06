//
//  CleverTapPlugin.m
//  Copyright (C) 2015 CleverTap
//
//  This code is provided under a commercial License.
//  A copy of this license has been distributed in a file called LICENSE
//  with this source code.
//
//

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@import UserNotifications;
#endif

#import "CleverTapPlugin.h"
#import <CleverTapSDK/CleverTap.h>
#import <CleverTapSDK/CleverTapSyncDelegate.h>
#import <CleverTapSDK/CleverTapInAppNotificationDelegate.h>
#import <CleverTapSDK/CleverTapEventDetail.h>
#import <CleverTapSDK/CleverTapUTMDetail.h>
#import <CoreLocation/CoreLocation.h>

static NSDateFormatter *dateFormatter;

static CleverTap *clevertap;

static NSDictionary *launchNotification;

static NSURL *launchDeepLink;

@interface CleverTapPlugin () <CleverTapSyncDelegate, CleverTapInAppNotificationDelegate> {
}

@end

@implementation CleverTapPlugin

#pragma mark Private

+(void)load {
    
    // Listen for UIApplicationDidFinishLaunchingNotification to get a hold of launchOptions
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidFinishLaunchingNotification:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    
    // Listen to re-broadcast events from Cordova's AppDelegate
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidFailToRegisterForRemoteNotificationsWithError:) name:CTRemoteNotificationRegisterError object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onHandleRegisterForRemoteNotification:) name:CTRemoteNotificationDidRegister object:nil];
    
    clevertap = [CleverTap sharedInstance];
}

+(void)onDidFinishLaunchingNotification:(NSNotification *)notification {
    NSDictionary *launchOptions = notification.userInfo;
    if (!launchOptions) return;
    
    if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
        [clevertap handleNotificationWithData:launchOptions];
        launchNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    }
    
    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        launchDeepLink = launchOptions[UIApplicationLaunchOptionsURLKey];
    }
}

+(void)onDidFailToRegisterForRemoteNotificationsWithError:(NSNotification *)notification {
    //Log Failures
    NSLog(@"onRemoteRegisterFail: %@", notification.object);
}

+(void)onHandleRegisterForRemoteNotification:(NSNotification *)notification {
    [clevertap setPushTokenAsString:notification.object];
}

-(void)onHandleOpenURLNotification:(NSNotification *)notification {
    [clevertap handleOpenURL:notification.object sourceApplication:nil];
    [self handleDeepLink:notification.object];
}

-(void)onHandleNotification:(NSNotification *)notification {
    [clevertap handleNotificationWithData:notification.object];
    [self notifyPushNotification:notification.object];
}

-(void)pluginInitialize {
    [super pluginInitialize];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onHandleOpenURLNotification:) name: CTHandleOpenURLNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onHandleNotification:) name:CTDidReceiveNotification object:nil];
    
    [clevertap setSyncDelegate:self];
    
    [clevertap setInAppNotificationDelegate:self];
}

-(NSDictionary*)_eventDetailToDict:(CleverTapEventDetail*)detail {
    NSMutableDictionary *_dict = [NSMutableDictionary new];
    
    if(detail) {
        if(detail.eventName) {
            [_dict setObject:detail.eventName forKey:@"eventName"];
        }
        
        if(detail.firstTime){
            [_dict setObject:@(detail.firstTime) forKey:@"firstTime"];
        }
        
        if(detail.lastTime){
            [_dict setObject:@(detail.lastTime) forKey:@"lastTime"];
        }
        
        if(detail.count){
            [_dict setObject:@(detail.count) forKey:@"count"];
        }
    }
    
    return _dict;
}

-(NSDictionary*)_utmDetailToDict:(CleverTapUTMDetail*)detail {
    NSMutableDictionary *_dict = [NSMutableDictionary new];
    
    if(detail) {
        if(detail.source) {
            [_dict setObject:detail.source forKey:@"source"];
        }
        
        if(detail.medium) {
            [_dict setObject:detail.medium forKey:@"medium"];
        }
        
        if(detail.campaign) {
            [_dict setObject:detail.campaign forKey:@"campaign"];
        }
    }
    
    return _dict;
}

-(NSString *)_dictToJson:(NSDictionary *)dict {
    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&err];
    
    if(err != nil) {
        return nil;
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

-(NSDictionary *)formatProfile:(NSDictionary *)profile {
    NSMutableDictionary *_profile = [NSMutableDictionary new];
    
    for (NSString *key in [profile keyEnumerator]) {
        id value = [profile objectForKey:key];
        
        if([key isEqualToString:@"DOB"]) {
            
            NSDate *dob = nil;
            
            if([value isKindOfClass:[NSString class]]) {
                
                if(!dateFormatter) {
                    dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateFormat:@"yyyy-MM-dd"];
                }
                
                dob = [dateFormatter dateFromString:value];
                
            }
            else if ([value isKindOfClass:[NSNumber class]]) {
                dob = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
            }
            
            if(dob) {
                value = dob;
            }
        }
        
        [_profile setObject:value forKey:key];
    }
    
    return _profile;
}

// custom helper method to fire push data into the Cordova WebView
-(void)notifyPushNotification:(id)notification {
    NSDictionary * _notification;
    if ([notification isKindOfClass:[UILocalNotification class]]) {
        _notification = [((UILocalNotification *) notification) userInfo];
    } else if ([notification isKindOfClass:[NSDictionary class]]) {
        _notification = notification;
    }
    
    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_notification options:0 error:&err];
    
    if(err == nil) {
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSString *js = [NSString stringWithFormat:@"cordova.fireDocumentEvent('onPushNotification', {'notification':%@})", json];
        [self.commandDelegate evalJs:js];
    }
}

#pragma mark CleverTapInAppNotificationDelegate

-(void)inAppNotificationDismissedWithExtras:(NSDictionary *)extras andActionExtras:(NSDictionary *)actionExtras {
    NSMutableDictionary *jsonDict = [NSMutableDictionary new];
    
    if (extras != nil) {
        jsonDict[@"extras"] = extras;
    }
    
    if (actionExtras != nil) {
        jsonDict[@"actionExtras"] = actionExtras;
    }
    
    NSString *jsonString = [self _dictToJson:jsonDict];
    
    if (jsonString != nil) {
        NSString *js = [NSString stringWithFormat:@"cordova.fireDocumentEvent('onCleverTapInAppNotificationDismissed', %@);", jsonString];
        [self.commandDelegate evalJs:js];
    }
}


#pragma mark CleverTapSyncDelegate

-(void)profileDidInitialize:(NSString*)CleverTapID {
    if(!CleverTapID) {
        return ;
    }
    
    NSString *jsonString = [self _dictToJson:@{@"CleverTapID":CleverTapID}];
    
    if (jsonString != nil) {
        NSString *js = [NSString stringWithFormat:@"cordova.fireDocumentEvent('onCleverTapProfileDidInitialize', %@);", jsonString];
        [self.commandDelegate evalJs:js];
    }
   
}

-(void)profileDataUpdated:(NSDictionary *)updates {
    if(!updates) {
        return ;
    }
    
    NSString *jsonString = [self _dictToJson:@{@"updates":updates}];
    
    if (jsonString != nil) {
        NSString *js = [NSString stringWithFormat:@"cordova.fireDocumentEvent('onCleverTapProfileSync', %@);", jsonString];
        [self.commandDelegate evalJs:js];
    }
}

#pragma mark Public

# pragma mark launch

-(void)notifyDeviceReady:(CDVInvokedUrlCommand *)command {
    if (launchNotification) {
        [self notifyPushNotification:[launchNotification copy]];
        launchNotification = nil;
    }
    
    if (launchDeepLink) {
        [self handleDeepLink:[launchDeepLink copy]];
        launchDeepLink = nil;
    }
}

#pragma mark Push

-(void)registerPush:(CDVInvokedUrlCommand *)command {
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
            UIUserNotificationType types = (UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound);
            UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
            [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        } else {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
            [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];
#pragma GCC diagnostic pop
        }
    } else {
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
        // IOS 10
        UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound| UNAuthorizationOptionBadge;
        [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (granted) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [[UIApplication sharedApplication] registerForRemoteNotifications];
                });
            }
         }];
#endif
    }
}

-(void)setPushTokenAsString:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *token = [command argumentAtIndex:0];
        if (token != nil && [token isKindOfClass:[NSString class]]) {
            [clevertap setPushTokenAsString:token];
        }
    }];
}

-(void)setPushToken:(NSData*)pushToken {
    [clevertap setPushToken:pushToken];
}

-(void)handleNotification:(id)notification {
    [clevertap handleNotificationWithData:notification];
    [self notifyPushNotification:notification];
}

-(void)handleDeepLink:(NSURL *)url {
    NSString *js = [NSString stringWithFormat:@"cordova.fireDocumentEvent('onDeepLink', {'deeplink':'%@'});", url.description];
    [self.commandDelegate evalJs:js];
}

#pragma mark Developer Options

-(void)setDebugLevel:(CDVInvokedUrlCommand *)command {
    NSNumber *level = [command argumentAtIndex:0];
    if (level != nil && [level isKindOfClass:[NSNumber class]]) {
        [CleverTap setDebugLevel:[level intValue]];
    }
}

#pragma mark Personalization

-(void)enablePersonalization:(CDVInvokedUrlCommand *)command {
    [CleverTap enablePersonalization];
}

#pragma mark Event API

-(void)recordScreenView:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *screenName = [command argumentAtIndex:0];
        if (screenName != nil && [screenName isKindOfClass:[NSString class]]) {
            [clevertap recordScreenView:screenName];
        }
    }];
}

-(void)recordEventWithName:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]]) {
            [clevertap recordEvent:eventName];
        }
    }];
}

-(void)recordEventWithNameAndProps:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        NSDictionary *eventProps = [command argumentAtIndex:1];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]] && eventProps != nil && [eventProps isKindOfClass:[NSDictionary class]]) {
            [clevertap recordEvent:eventName withProps:eventProps];
        }
    }];
}

-(void)recordChargedEventWithDetailsAndItems:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *details = [command argumentAtIndex:0];
        NSArray *items = [command argumentAtIndex:1];
        
        if (details != nil && [details isKindOfClass:[NSDictionary class]] && items != nil && [items isKindOfClass:[NSArray class]]) {
            [clevertap recordChargedEventWithDetails:details andItems:items];
        }
    }];
}

-(void)eventGetFirstTime:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]]) {
            NSTimeInterval first = [clevertap eventGetFirstTime:eventName];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:first];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

-(void)eventGetLastTime:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]]) {
            NSTimeInterval last = [clevertap eventGetLastTime:eventName];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:last];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

-(void)eventGetOccurrences:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]]) {
            int num = [clevertap eventGetOccurrences:eventName];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:num];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
    
}

-(void)eventGetDetails:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *eventName = [command argumentAtIndex:0];
        if (eventName != nil && [eventName isKindOfClass:[NSString class]]) {
            CleverTapEventDetail *detail = [clevertap eventGetDetail:eventName];
            NSDictionary * res = [self _eventDetailToDict:detail];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:res];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

-(void)getEventHistory:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *history = [clevertap userGetEventHistory];
        
        NSMutableDictionary *_history = [NSMutableDictionary new];
        
        for (NSString *eventName in [history keyEnumerator]) {
            CleverTapEventDetail *detail = [history objectForKey:eventName];
            NSDictionary * _inner = [self _eventDetailToDict:detail];
            [_history setObject:_inner forKey:eventName];
        }
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:_history];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
   
}

#pragma mark Profile API

/**
 Note: the call to CleverTapSDK must be made on the main thread due to start the LocationManager, but thereafter the CleverTapSDK method itself is non-blocking.
*/

-(void)getLocation:(CDVInvokedUrlCommand *)command {
    [CleverTap getLocationWithSuccess:^(CLLocationCoordinate2D loc){
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"lat":@(loc.latitude), @"lon":@(loc.longitude)}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
    } andError:^(NSString *error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)setLocation:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        @try {
            double lat = [[command argumentAtIndex:0] doubleValue];
            double lon = [[command argumentAtIndex:1] doubleValue];
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat,lon);
            [CleverTap setLocation:coordinate];
        }
        @catch (NSException *exception) {
            NSLog(@"error setting location %@", exception.reason);
            return ;
        }
    }];
}

-(void)onUserLogin:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *profile = [command argumentAtIndex:0];
        if (profile != nil && [profile isKindOfClass:[NSDictionary class]]) {
            NSDictionary *_profile = [self formatProfile:profile];
            [clevertap onUserLogin:_profile];
        }
    }];
}

-(void)profileSet:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *profile = [command argumentAtIndex:0];
        if (profile != nil && [profile isKindOfClass:[NSDictionary class]]) {
            NSDictionary *_profile = [self formatProfile:profile];
            [clevertap profilePush:_profile];
        }
    }];
}

-(void)profileSetGraphUser:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *profile = [command argumentAtIndex:0];
        if (profile != nil && [profile isKindOfClass:[NSDictionary class]]) {
            [clevertap profilePushGraphUser:profile];
        }
    }];
}

-(void)profileSetGooglePlusUser:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSDictionary *profile = [command argumentAtIndex:0];
        if (profile != nil && [profile isKindOfClass:[NSDictionary class]]) {
            [clevertap profilePushGooglePlusUser:profile];
        }
    }];
}

-(void)profileGetProperty:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *propertyName = [command argumentAtIndex:0];
        CDVPluginResult *pluginResult;
        
        if (propertyName != nil && [propertyName isKindOfClass:[NSString class]]) {
            id prop = [clevertap profileGet:propertyName];
            
            if(prop == nil) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
            }
            
            else if([prop isKindOfClass:[NSString class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:prop];
            }
            
            else if([prop isKindOfClass:[NSDate class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[prop timeIntervalSince1970]];
            }
            
            else if([prop isKindOfClass:[NSNumber class]]) {
                BOOL isFloat = CFNumberIsFloatType((CFNumberRef)prop);
                
                if (isFloat) {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[prop doubleValue]];
                    
                }
                else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:[prop intValue]];
                };
            }
            
            else if([prop isKindOfClass:[NSDictionary class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:prop];
            }
            
            else if([prop isKindOfClass:[NSArray class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:prop];
            }
        }
        
        if(!pluginResult) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)profileGetCleverTapAttributionIdentifier:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        CDVPluginResult *pluginResult;
        
        NSString *attributionID = [clevertap profileGetCleverTapAttributionIdentifier];
        
        if(attributionID == nil) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
        }
        
        else  {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:attributionID];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)profileGetCleverTapID:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        CDVPluginResult *pluginResult;
        
        NSString *cleverTapID = [clevertap profileGetCleverTapID];
        
        if(cleverTapID == nil) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
        }
        
        else  {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:cleverTapID];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)profileRemoveValueForKey:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        if (key != nil && [key isKindOfClass:[NSString class]]) {
            [clevertap profileRemoveValueForKey:key];
        }
    }];
    
}

-(void)profileSetMultiValues:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        NSArray *values = [command argumentAtIndex:1];
        if (key != nil && [key isKindOfClass:[NSString class]] && values != nil && [values isKindOfClass:[NSArray class]]) {
            [clevertap profileSetMultiValues:values forKey:key];
        }
    }];
    
}

-(void)profileAddMultiValue:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        NSString *value = [command argumentAtIndex:1];
        if (key != nil && [key isKindOfClass:[NSString class]] && value != nil && [value isKindOfClass:[NSString class]]) {
            [clevertap profileAddMultiValue:value forKey:key];
        }
    }];
}

-(void)profileAddMultiValues:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        NSArray *values = [command argumentAtIndex:1];
        if (key != nil && [key isKindOfClass:[NSString class]] && values != nil && [values isKindOfClass:[NSArray class]]) {
            [clevertap profileAddMultiValues:values forKey:key];
        }
    }];
}

-(void)profileRemoveMultiValue:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        NSString *value = [command argumentAtIndex:1];
        if (key != nil && [key isKindOfClass:[NSString class]] && value != nil && [value isKindOfClass:[NSString class]]) {
            [clevertap profileRemoveMultiValue:value forKey:key];
        }
    }];
}

-(void)profileRemoveMultiValues:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *key = [command argumentAtIndex:0];
        NSArray *values = [command argumentAtIndex:1];
        if (key != nil && [key isKindOfClass:[NSString class]] && values != nil && [values isKindOfClass:[NSArray class]]) {
            [clevertap profileRemoveMultiValues:values forKey:key];
        }
    }];
}

#pragma mark Session API
-(void)sessionGetTimeElapsed:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSTimeInterval elapsed = [clevertap sessionGetTimeElapsed];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:elapsed];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)sessionGetTotalVisits:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        int total = [clevertap userGetTotalVisits];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:total];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)sessionGetScreenCount:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        int count = [clevertap userGetScreenCount];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:count];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)sessionGetPreviousVisitTime:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSTimeInterval previous = [clevertap userGetPreviousVisitTime];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:previous];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

-(void)sessionGetUTMDetails:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        CleverTapUTMDetail *detail = [clevertap sessionGetUTMDetails];
        NSDictionary * _detail = [self _utmDetailToDict:detail];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:_detail];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
    }];
}

-(void)pushInstallReferrer:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString *source = [command argumentAtIndex:0];
        NSString *medium = [command argumentAtIndex:1];
        NSString *campaign = [command argumentAtIndex:2];
        [clevertap pushInstallReferrerSource:source medium:medium campaign:campaign];
    }];
}

@end
