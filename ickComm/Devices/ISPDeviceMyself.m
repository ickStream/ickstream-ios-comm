//
//  ISPDeviceMyself.m
//  ickStreamProto
//
//  Created by Jörg Schwieder on 11.05.12.
//  Copyright (c) 2012 Du!Business GmbH. All rights reserved.
//


#import "ISPDeviceMyself.h"
#import "ISPRHttpRequest.h"
#import "ISPRequest.h"
#import "ISPSpinner.h"

#import "ISPUserViewController.h"
#import "WebsiteController.h"

@interface ISPDeviceMyself()

- (void)startPlayer;
- (void)didAcquireToken:(NSNotification *)notification;

@end

static __strong NSString * _myselfToken = nil;
static __strong NSString * _myselfUUID = nil;
static __strong NSString * _myselfApplicationId = nil;
static __strong NSString * _authorizationString = nil;

static NSMutableDictionary * _deviceCache = nil;

@implementation ISPDeviceMyself

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - ID handling

// deprecated to just use UUID but we can refine this later....
+ (NSString *)myselfHardwareId {
    if ([UIDevice currentDevice].isIOS6) {
        return [[NSString stringWithFormat:@"com.ickstream.device%@", [UIDevice currentDevice].identifierForVendor.UUIDString] getSHA1Hash];
    }
    return [[UIDevice currentDevice] uniqueGlobalDeviceIdentifier];
    //return [[NSString stringWithFormat:@"test%@", [[UIDevice currentDevice] uniqueIdentifier]] getSHA1Hash];
}

+ (void)setApplicationId:(NSString *)newId {
    _myselfApplicationId = newId;
}

+ (NSString *)myselfApplicationId {
    return _myselfApplicationId;
}

- (NSString *)hardwareId {
    return [ISPDeviceMyself myselfHardwareId];
}

- (NSString *)defaultName {
    return [UIDevice currentDevice].name;
}

+ (NSString *)deviceAuthorization {
    if (!_authorizationString) {
        NSString * myToken = [self myselfToken];
        if (!myToken)
            return nil;
        _authorizationString = [NSString stringWithFormat:@"Bearer %@", [ISPDeviceMyself myselfToken]];
    }
    return _authorizationString;
}

- (NSString *)deviceAuthorization {
    return [ISPDeviceMyself deviceAuthorization];
}

static __strong NSString * _userToken = nil;

+ (NSString *)myselfUserToken {
    return _userToken;
    //    return @"A36738B7-0267-477C-AD11-148383456049";
}

+ (void)clearMyselfUserToken {
    _userToken = nil;
}



#define HARDWARE_VERIFICATION_RANGE { 3, 10 }
#define HARDWARE_VERIFICATION_MASK @"%@andverifywith%@"

+ (NSString *)generateMyselfUUID {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef cfUUID = CFUUIDCreateString(NULL, uuid);
    NSString * sUuid = [NSString stringWithFormat:@"%@", cfUUID];
    CFRelease(cfUUID);
    CFRelease(uuid);
    
    NSString * sshvalue = [[NSString stringWithFormat:HARDWARE_VERIFICATION_MASK, sUuid, [self myselfHardwareId]] getSHA1Hash];
    NSRange range = HARDWARE_VERIFICATION_RANGE;
    if ([sshvalue length] < (range.length + range.location))
        return nil;
    sshvalue = [sshvalue substringWithRange:range];

    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"myselfToken"];
    [defaults setObject:sUuid forKey:@"myselfUUID"];
    [defaults setObject:sshvalue forKey:@"myselfVerifier"];
    [defaults synchronize];

    return sUuid;
}

+ (void)clearMyselfToken {
    _myselfToken = nil;
    _authorizationString = nil;
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"myselfToken"];
    [defaults synchronize];    
}


#pragma mark - token authentication

// token has been entered
static ISPUserViewController * _tokenVC = nil;
static WebsiteController * _tokenWebView = nil;

static BOOL SSL_authenticated = NO;
static NSURLConnection * _urlConnection = nil;

#define REDIRECT_URL_AUTH1 @"token://auth"

+ (void)hasEnteredToken:(NSString *)token {
    _userToken = token;
    _tokenVC = nil;
    _tokenWebView = nil;
    [self registerDevice];
}

+ (void)registerDevice {
    static BOOL _useAlert = NO;
    
    if (!_userToken) {
        if (_tokenVC || _tokenWebView)
            return;
        [ISPSpinner hideSpinnerAnimated:YES];
        
        //        _tokenVC = [[ISPUserViewController alloc] initWithDelegate:(id<ISPUserTokenDelegateProtocol>)self];
        dispatch_sync_safe(dispatch_get_main_queue(), ^{
            if (_tokenWebView)
                return;
            _tokenWebView = [[WebsiteController alloc] initWithCapabilities:kWebsiteNavigation
                                                                 andCommand:[NSString stringWithFormat:@"https://api.ickstream.com/ickstream-cloud-core/oauth?redirect_uri=%@&client_id=%@", REDIRECT_URL_AUTH1, [ISPDeviceMyself myselfApplicationId]]];
            [_tokenWebView addLinkCheckBlock:^BOOL(IPWebView *webView, NSURLRequest *request, UIWebViewNavigationType navigationType) {
                if (!SSL_authenticated) {
                    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
                    [_urlConnection start];
                    return NO;
                }
                
                NSString * urlString = [request.URL absoluteString];
                NSArray * arr = nil;
                NSString * token = nil;
                if ([urlString hasPrefix:REDIRECT_URL_AUTH1]) {
                    arr = [urlString componentsSeparatedByString:@"?code="];
                    if (arr.count == 2) {
                        token = arr[1];
                        
                        NSURLRequest * aRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.ickstream.com/ickstream-cloud-core/oauth/token?redirect_uri=%@&code=%@", REDIRECT_URL_AUTH1, token]]];
                        [NSURLConnection sendAsynchronousRequest:aRequest
                                                           queue:[NSOperationQueue mainQueue]
                                               completionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
                                                    // TODO: ERROR HANDLING!!!!!
                                                   NSDictionary * reply = [NSJSONSerialization JSONObjectWithData:data
                                                                                                          options:0
                                                                                                            error:nil];
                                                   if (![reply isKindOfClass:[NSDictionary class]])
                                                       return; // TODO: ERROR HANDLING!!!!!
                                                   id atoken = reply[@"access_token"];
                                                   if (![atoken isKindOfClass:[NSString class]])
                                                       return; // TODO: ERROR HANDLING!!!!!
                                                   [_tokenWebView dismissViewControllerAnimated:YES completion:nil];
                                                   [ISPDeviceMyself hasEnteredToken:atoken];
                                               }];
                    }
                    return NO;
                }
                return YES;
            }];
            __strong UINavigationController * navC = [[UINavigationController alloc] initWithRootViewController:_tokenWebView];

            NSObject *tmp=[UIApplication sharedApplication].keyWindow;
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:navC animated:YES completion:nil];
        });
        
        
/*        [[UIApplication sharedApplication].keyWindow.rootViewController presentModalViewController:_tokenVC animated:YES];
        if (_useAlert)
            [_tokenVC showAlert];*/
        return;
    }
    
    [ISPSpinner showSpinnerAnimated:YES];
    
    NSString * sUuid = [self myselfUUID];
    static ISPRequest * _rdRequest = nil;
    if (_rdRequest.busy)
        return;
    
    ISPDeviceMyself * aMyself = [ISPDeviceMyself findMyselfOfType:ICKP2P_SERVICE_ANY];
    
    // registration failed
    if (!aMyself)
        return;
    
    _rdRequest = [ISPRequest automaticRequestWithDevice:aMyself 
                                   service:nil
                                    method:@"addDeviceWithHardwareId"
                                    params:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            sUuid, @"id",
                                            @"ickStreamDevice", @"model",
                                            aMyself.name, @"name",
                                            @"127.0.0.1", @"address",
                                            [self myselfHardwareId], @"hardwareId",
                                            [self myselfApplicationId], @"applicationId",
                                            nil]
                             withResponder:^(NSDictionary *result, ISPRequest *request) {
                                 [ISPSpinner hideSpinnerAnimated:YES];
                                 NSString * token = [result stringForKey:@"accessToken"];
                                 NSLog(@"New access Token: %@", token);
                                 NSString * theId = [result stringForKey:@"id"];
                                 if ([theId isEqualToString:[self myselfUUID]]) {
                                     NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
                                     [defaults setObject:token forKey:@"myselfToken"];
                                     [defaults synchronize];
                                     [[NSNotificationCenter defaultCenter] postNotificationName:@"ISPAccessTokenAcquiredNotification" object:aMyself userInfo:nil];
                                 }
                                 _rdRequest = nil;
                             } withErrorResponder:^(NSString *errorString, ISPRequest *request) {
                                 [ISPSpinner hideSpinnerAnimated:YES];
                                 NSLog(@"%@", errorString);
                                 _rdRequest = nil;
                                 _useAlert = YES;
                                 _userToken = nil;
                             }];
    
    //        [defaults setObject:state forKey:(NSString *)key];
    //        if (store)
    //            [defaults synchronize];
}


+ (BOOL)validateTokens {
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSString * token = [defaults objectForKey:@"myselfUUID"];
    if (!token) 
        return NO;
    NSString * verifier = [defaults objectForKey:@"myselfVerifier"];
    if (!verifier)
        return NO;
    NSString * sshvalue = [[NSString stringWithFormat:HARDWARE_VERIFICATION_MASK, token, [self myselfHardwareId]] getSHA1Hash];
    NSRange range = HARDWARE_VERIFICATION_RANGE;
    if ([sshvalue length] < (range.length + range.location))
        return NO;
    sshvalue = [sshvalue substringWithRange:range];
    if (![sshvalue isEqualToString:verifier])
        return NO;
    return YES;
}

+ (NSString *)myselfUUID {
    if (!_myselfUUID) {
        if ([self validateTokens]) {
            NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
            _myselfUUID = [defaults objectForKey:@"myselfUUID"];            
        }
        else {
            _myselfUUID = [self generateMyselfUUID];
            [self registerDevice];
        }
    }
    return _myselfUUID;
}

+ (NSString *)myselfToken {
    if (!_myselfToken) {
        if ([self validateTokens]) {
            NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
            _myselfToken = [defaults objectForKey:@"myselfToken"];            
        }
        else
            [self generateMyselfUUID];
        if (!_myselfToken)
            [self registerDevice];
    }
    return _myselfToken;    
}

#pragma mark - NURLConnection delegate

+ (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSLog(@"WebController Got auth challange via NSURLConnection");
    if ([challenge previousFailureCount] == 0)
    {
        SSL_authenticated = YES;
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    } else
    {
        [[challenge sender] cancelAuthenticationChallenge:challenge];
    }
}

+ (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    //    NSLog(@"WebController received response via NSURLConnection");
    // remake a webview call now that authentication has passed ok.
    SSL_authenticated = YES;
    // Cancel the URL connection otherwise we double up (webview + url connection, same url = no good!)
    [_urlConnection cancel];
    [_tokenWebView refresh:YES];
}

// We use this method is to accept an untrusted site which unfortunately we need to do, as our PVM servers are self signed.
+ (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}



#pragma mark - implementation


+ (ISPDeviceMyself *)findMyselfOfType:(ickP2pServicetype_t)type {
    // let's store the device here, too.
    // yes, it's redundant, but it's also much faster than creating the hash string all the time and we wil have to do this a loooot
    static dispatch_once_t pred = 0;
    dispatch_once(&pred, ^{
        _deviceCache = [[NSMutableDictionary alloc] initWithCapacity:3];
    });
    
    ISPDeviceMyself * my = nil;
    if ((type == ICKP2P_SERVICE_ANY) && [_deviceCache count]) {
        my = _deviceCache[_deviceCache.allKeys[0]];
    } else
        my = _deviceCache[@(type)];
    //    if (my)
    return my;
    
    // we don't create any "myself" object for "ANY", we create a controller instead....
    // TODO better start initializing with something we know we are...
    // forget that... we don't communicate without a ready-made myselfDevice
/*    if (type == ICKDEVICE_ANY)
        type = ICKDEVICE_CONTROLLER;
    my = (ISPDeviceMyself *)[super findDeviceWithUUID:[self myselfUUID] andType:type];
    if (my)
        [_deviceCache setObject:my forKey:[NSNumber numberWithInt:type]];

    return my;*/
}

// myselfDevices are not target devices but source devices, they should be registered in a separate list and they are only identified by type, we know our UUID.
// TBD: This is of course not true for the myself player... however, that one will be registered by the callback as a second device.
+ (void)registerInDeviceList:(ISPDevice *)newDevice {
    if (!newDevice)
        return;
    NSLog(@"MyselfDevice registerInDeviceList");
    [_deviceCache setObject:newDevice forKey:@(newDevice.ickType)];
}

+ (void)removeFromDeviceList:(ISPDevice *)oldDevice {
    if (!oldDevice)
        return;
    [_deviceCache removeObjectForKey:@(oldDevice.ickType)];
}

- (void)removeFromDeviceList {
    [[self class] removeFromDeviceList:self];
}

- (id)initWithType:(ickP2pServicetype_t)type {
    id tmp = [ISPDeviceMyself findMyselfOfType:type];
    if (tmp) {
        self = nil;
        self = tmp;
        return self;
    }
    
    // let's make sure we don't use illegal devices here
/*    if ((type != ICKDEVICE_PLAYER) && (type != ICKDEVICE_CONTROLLER) && (type != ICKDEVICE_DEBUG)) {
        self = nil;
        return nil;
    }*/

    self = [super init];
    if (self) {
        self.ickType = type;
        self.uuid = [ISPDeviceMyself myselfUUID];
        [[self class] registerInDeviceList:self];
        //ickDiscoveryAddService(type);
        
        if (type & ICKP2P_SERVICE_PLAYER) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(didAcquireToken:)
                                                         name:@"ISPAccessTokenAcquiredNotification"
                                                       object:nil];

            if ([ISPDeviceMyself myselfToken]) {
                   [self startPlayer];
            }
        }
    }
    return self;
}


#pragma mark - user authorization

- (NSString *)userAuthorization {
    return [NSString stringWithFormat:@"Bearer %@", [ISPDeviceMyself myselfUserToken]];
}


- (NSURL *)url {
    return [NSURL URLWithString:@"http://api.ickstream.com/ickstream-cloud-core/jsonrpc"];
}

- (NSObject<ISPAtomicRequestProtocol> *)atomicRequestForService:(NSString *)aServiceId owner:(ISPRequest *)owner {
    NSMutableURLRequest<ISPAtomicRequestProtocol> * request = [[ISPRHttpRequest alloc] initWithOwner:owner andDevice:self];
    [request addValue:[[ISPDeviceMyself findMyselfOfType:ICKP2P_SERVICE_ANY] userAuthorization] forHTTPHeaderField:@"Authorization"];
    return request;
}


#pragma mark - player authorization

- (void)startPlayer {
}

- (void)didAcquireToken:(NSNotification *)notification {
    [self startPlayer];
}

- (NSString *)UUID {
    return [ISPDeviceMyself myselfUUID];
}

- (void)setUUID:(NSString *)UUID {
    
}

- (NSString *)authentication {
    return [ISPDeviceMyself myselfToken];
}

- (void)setAuthentication:(NSString *)authentication {
    
}
//@property (nonatomic, readonly) NSString * hardwareId;

#pragma mark player life cycle

- (ickErrcode_t) ickInitDiscoveryWithInterface:(NSString*)interface {
    return ICKERR_SUCCESS;
}
- (void) ickEndDiscovery:(NSInteger) wait {
    
}






@end
