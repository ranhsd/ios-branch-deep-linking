//
//  BNCSpotlightService.m
//  Branch-SDK
//
//  Created by Parth Kalavadia on 8/10/17.
//  Copyright © 2017 Branch Metrics. All rights reserved.
//

#import "BNCSpotlightService.h"
#import "BNCSystemObserver.h"
#import "BNCError.h"
#import "Branch.h"
#import "BranchConstants.h"

static NSString* const kUTTypeGeneric = @"public.content";
static NSString* const kDomainIdentifier = @"com.branch.io";

@interface BNCSpotlightService()<NSUserActivityDelegate> {
    dispatch_queue_t    _workQueue;
}
@property (strong, nonatomic) NSMutableDictionary *userInfo;
@property (strong, readonly) dispatch_queue_t workQueue;
@end

@implementation BNCSpotlightService

- (void)indexPubliclyWithBranchUniversalObject:(BranchUniversalObject* _Nonnull)universalObject
                                linkProperties:(BranchLinkProperties* _Nullable)linkProperties
                                      callback:(void (^_Nullable)(BranchUniversalObject * _Nullable universalObject,
                                                                  NSString* _Nullable url,
                                                                  NSError * _Nullable error))completion {
    if ([BNCSystemObserver getOSVersion].integerValue < 9) {
        NSError *error = [NSError branchErrorWithCode:BNCSpotlightNotAvailableError];
        if (completion) {
            completion(universalObject,nil,error);
           // callback([BNCPreferenceHelper preferenceHelper].userUrl, error);
        }
        return;
    }
    
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED < 90000
    NSError *error = [NSError branchErrorWithCode:BNCSpotlightNotAvailableError];
    if (callback) {
        completion(branchShareLink,nil,error);
    }
    return;
#endif
    
    BOOL isIndexingAvailable = NO;
    Class CSSearchableIndexClass = NSClassFromString(@"CSSearchableIndex");
    SEL isIndexingAvailableSelector = NSSelectorFromString(@"isIndexingAvailable");
    isIndexingAvailable =
    ((BOOL (*)(id, SEL))[CSSearchableIndexClass methodForSelector:isIndexingAvailableSelector])
    (CSSearchableIndexClass, isIndexingAvailableSelector);
    
    if (!isIndexingAvailable) {
        NSError *error = [NSError branchErrorWithCode:BNCSpotlightNotAvailableError];
        if (completion) {
            completion(universalObject,[BNCPreferenceHelper preferenceHelper].userUrl, error);
        }
        return;
    }
    
    if (!universalObject.title) {
        NSError *error = [NSError branchErrorWithCode:BNCSpotlightTitleError];
        if (completion) {
            completion(universalObject,[BNCPreferenceHelper preferenceHelper].userUrl, error);
        }
        return;
    }
    
    // Type cannot be null
    NSString *typeOrDefault = universalObject.type ?: (NSString *)kUTTypeGeneric;

    BranchLinkProperties* spotlightLinkProperties;
    if (linkProperties == nil) {
        spotlightLinkProperties = [[BranchLinkProperties alloc] init];
    }
    [spotlightLinkProperties setFeature:@"spotlight"];


    // Include spotlight info in params
        
    NSURL* thumbnailUrl = [NSURL URLWithString:universalObject.imageUrl];
    BOOL thumbnailIsRemote = thumbnailUrl && ![thumbnailUrl isFileURL];
    
    [universalObject getShortUrlWithLinkProperties:spotlightLinkProperties
                                                       andCallback:^(NSString * _Nullable url, NSError * _Nullable error)
    {
        if (error) {
            if (completion) {
                completion(universalObject,[BNCPreferenceHelper preferenceHelper].userUrl, error);
            }
            return;
        }
        if (thumbnailIsRemote) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *thumbnailData = [NSData dataWithContentsOfURL:thumbnailUrl];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self indexContentWithUrl:url
                          spotlightIdentifier:url
                                  canonicalId:universalObject.canonicalIdentifier
                                        title:universalObject.title
                                  description:universalObject.description
                                         type:typeOrDefault
                                 thumbnailUrl:thumbnailUrl
                                thumbnailData:thumbnailData
                            publiclyIndexable:YES
                                     userInfo:universalObject.metadata
                                     keywords:[NSSet setWithArray:universalObject.keywords]
                               expirationDate:universalObject.expirationDate
                                     callback:^(NSString * _Nullable url, NSError * _Nullable error) {
                                         completion(universalObject, url, error);
                                     }];
                });
            });
        }
        else {
            [self indexContentWithUrl:url
                  spotlightIdentifier:url
                          canonicalId:universalObject.canonicalIdentifier
                                title:universalObject.title
                          description:universalObject.description
                                 type:typeOrDefault
                         thumbnailUrl:thumbnailUrl
                        thumbnailData:nil
                    publiclyIndexable:YES
                             userInfo:universalObject.metadata
                             keywords:[NSSet setWithArray:universalObject.keywords]
                       expirationDate:universalObject.expirationDate
                             callback:^(NSString * _Nullable url, NSError * _Nullable error) {
                                 completion(universalObject, url, error);
                             }];
        }
    }];
}

- (void)indexContentWithUrl:(NSString *)url
        spotlightIdentifier:(NSString *)spotlightIdentifier
                canonicalId:(NSString *)canonicalId
                      title:(NSString *)title
                description:(NSString *)description
                       type:(NSString *)type
               thumbnailUrl:(NSURL *)thumbnailUrl
              thumbnailData:(NSData *)thumbnailData
          publiclyIndexable:(BOOL)publiclyIndexable
                   userInfo:(NSDictionary *)userInfo
                   keywords:(NSSet *)keywords
             expirationDate:(NSDate *)expirationDate
                   callback:(void (^_Nullable)(NSString* _Nullable url, NSError * _Nullable error))completion {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    
    id attributes = [self getAttributeSetFromTitle:title
                               spotlightIdentifier:spotlightIdentifier
                                               URL:url
                                       CanonicalId:canonicalId
                                       description:description
                                              type:type
                                      thumbnailUrl:thumbnailUrl
                                     thumbnailData:thumbnailData
                                          userInfo:userInfo
                                          keywords:keywords];
    
    NSDictionary *indexingParams = @{@"title": title,
                                     @"url": url,
                                     @"spotlightId": spotlightIdentifier,
                                     @"userInfo": [userInfo mutableCopy],
                                     @"keywords": keywords,
                                     @"publiclyIndexable": [NSNumber numberWithBool:publiclyIndexable],
                                     @"attributeSet": attributes
                                     };
    
    if (publiclyIndexable) {
        [self indexUsingNSUserActivity:indexingParams];
        
        // Not handling error scenarios because they are already handled upstream by the caller
        if (url) {
            if (completion) {
                completion(url, nil);
            }
        }
    }else {
        
        [self indexUsingSearchableItem:indexingParams
                         thumbnailData:thumbnailData
                              callback:^(NSString * _Nullable url, NSError * _Nullable error) {
                                  completion(url,error);
                              }];
    }
#endif
}

-(id)getAttributeSetFromTitle:(NSString *)title
          spotlightIdentifier:(NSString*)spotlightIdentifier
                          URL:(NSString*)url
                  CanonicalId:(NSString *)canonicalId
                  description:(NSString *)description
                         type:(NSString *)type
                 thumbnailUrl:(NSURL *)thumbnailUrl
                thumbnailData:(NSData *)thumbnailData
                     userInfo:(NSDictionary *)userInfo
                     keywords:(NSSet *)keywords {
    
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    
    id CSSearchableItemAttributeSetClass = NSClassFromString(@"CSSearchableItemAttributeSet");
    if (![CSSearchableItemAttributeSetClass respondsToSelector:@selector(initWithItemContentType:)]) {
        return nil;
    }

    CSSearchableItemAttributeSet *attributes = [[CSSearchableItemAttributeSetClass alloc] initWithItemContentType:type];

    if ([attributes respondsToSelector:@selector(setTitle:)] && title) {
        [attributes setTitle:title];
    }
    if ([attributes respondsToSelector:@selector(setContentDescription:)]) {
        [attributes setContentDescription:description];
    }
    
    if ([attributes respondsToSelector:@selector(setThumbnailURL:)] && thumbnailUrl) {
        [attributes setThumbnailURL:thumbnailUrl];
    }
    
    if (thumbnailData && [attributes respondsToSelector:@selector(setThumbnailData:)]) {
        [attributes setThumbnailData:thumbnailData];
    }
    
    if ([attributes respondsToSelector:@selector(setContentURL:)]) {
        [attributes setContentURL:[NSURL URLWithString:url]];
    }

    SEL setWeakRelatedUniqueIdentifierSelector = NSSelectorFromString(@"setWeakRelatedUniqueIdentifier:");
    if (canonicalId && [attributes respondsToSelector:setWeakRelatedUniqueIdentifierSelector]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [attributes performSelector:setWeakRelatedUniqueIdentifierSelector withObject:canonicalId];
        #pragma clang diagnostic pop
    }
    return attributes;
#endif
    
    return nil;
}

- (void)indexPrivatelyWithBranchUniversalObject:(BranchUniversalObject* _Nonnull)universalObject
                                       callback:(void (^_Nullable)(BranchUniversalObject * _Nullable universalObject,
                                                                   NSString* _Nullable url,
                                                                   NSError * _Nullable error))completion {
    
    if ([BNCSystemObserver getOSVersion].integerValue < 9) {
        NSError *error = [NSError branchErrorWithCode:BNCSpotlightNotAvailableError];
        if (completion) {
            completion(universalObject,[BNCPreferenceHelper preferenceHelper].userUrl, error);
        }
        
        return;
    }
    
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    
    NSString *typeOrDefault = universalObject.type ?: kUTTypeGeneric;

    NSString* dynamicUrl = [[Branch getInstance] getLongURLWithParams:universalObject.metadata
                                                           andFeature:@"spotlight"];
    
    NSURL* thumbnailUrl = [NSURL URLWithString:universalObject.imageUrl];
    BOOL thumbnailIsRemote = thumbnailUrl && ![thumbnailUrl isFileURL];
    if (thumbnailIsRemote) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *thumbnailData = [NSData dataWithContentsOfURL:thumbnailUrl];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self indexContentWithUrl:dynamicUrl
                      spotlightIdentifier:dynamicUrl
                              canonicalId:universalObject.canonicalIdentifier
                                    title:universalObject.title
                              description:universalObject.description
                                     type:typeOrDefault
                             thumbnailUrl:thumbnailUrl
                            thumbnailData:thumbnailData
                        publiclyIndexable:NO
                                 userInfo:universalObject.metadata
                                 keywords:[NSSet setWithArray:universalObject.keywords]
                           expirationDate:universalObject.expirationDate callback:^(NSString * _Nullable url, NSError * _Nullable error) {
                               universalObject.spotlightIdentifier = url;
                               completion(universalObject,url,error);
                           }];
            });
        });
    }
    else {
        [self indexContentWithUrl:dynamicUrl
              spotlightIdentifier:dynamicUrl
                      canonicalId:universalObject.canonicalIdentifier
                            title:universalObject.title
                      description:universalObject.description
                             type:typeOrDefault
                     thumbnailUrl:thumbnailUrl
                    thumbnailData:nil
                publiclyIndexable:NO
                         userInfo:universalObject.metadata
                         keywords:[NSSet setWithArray:universalObject.keywords]
                   expirationDate:universalObject.expirationDate callback:^(NSString * _Nullable url, NSError * _Nullable error) {
                       universalObject.spotlightIdentifier = url;
                       completion(universalObject,url,error);
                   }];


    }
#endif
}

- (void)indexPrivatelyWithBranchUniversalObjects:(NSArray<BranchUniversalObject*>* _Nonnull)universalObjects
                                      completion:(void (^_Nullable) (NSArray<BranchUniversalObject *> * _Nullable universalObjects,
                                                                     NSError * _Nullable error))completion {
    if ([BNCSystemObserver getOSVersion].integerValue < 9) {
        NSError *error = [NSError branchErrorWithCode:BNCSpotlightNotAvailableError];
        
        completion(nil,error);
        return;
    }
    
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    dispatch_group_t workGroup = dispatch_group_create();
    
    NSMutableArray<CSSearchableItem *> *searchableItems = [[NSMutableArray alloc] init];
    NSMutableDictionary<NSString*,BranchUniversalObject*> *mapSpotlightIdentifier = [[NSMutableDictionary alloc] init];
    
    for (BranchUniversalObject* universalObject in universalObjects) {
        dispatch_group_async(workGroup, self.workQueue, ^{
            dispatch_semaphore_t indexingSema = dispatch_semaphore_create(0);
            
            NSString *typeOrDefault = universalObject.type ?: kUTTypeGeneric;
            
            NSString* dynamicUrl = [[Branch getInstance] getLongURLWithParams:universalObject.metadata
                                                                   andFeature:@"spotlight"];
            
            mapSpotlightIdentifier[dynamicUrl] = universalObject;
            NSURL* thumbnailUrl = [NSURL URLWithString:universalObject.imageUrl];
            BOOL thumbnailIsRemote = thumbnailUrl && ![thumbnailUrl isFileURL];
            if (thumbnailIsRemote) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSData *thumbnailData = [NSData dataWithContentsOfURL:thumbnailUrl];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        id attributes = [self getAttributeSetFromTitle:universalObject.title
                                                   spotlightIdentifier:dynamicUrl
                                                                   URL:dynamicUrl
                                                           CanonicalId:universalObject.canonicalIdentifier
                                                           description:universalObject.description
                                                                  type:typeOrDefault
                                                          thumbnailUrl:thumbnailUrl
                                                         thumbnailData:thumbnailData
                                                              userInfo:universalObject.metadata
                                                              keywords:[NSSet setWithArray:universalObject.keywords]];

                        CSSearchableItem *item = [[CSSearchableItem alloc]
                                                  initWithUniqueIdentifier:dynamicUrl
                                                  domainIdentifier:kDomainIdentifier
                                                  attributeSet:attributes];
                        
                        [searchableItems addObject:item];
                        dispatch_semaphore_signal(indexingSema);

                    });
                });
            }
            else {
                id attributes = [self getAttributeSetFromTitle:universalObject.title
                                           spotlightIdentifier:dynamicUrl
                                                           URL:dynamicUrl
                                                   CanonicalId:universalObject.canonicalIdentifier
                                                   description:universalObject.description
                                                          type:typeOrDefault
                                                  thumbnailUrl:thumbnailUrl
                                                 thumbnailData:nil
                                                      userInfo:universalObject.metadata
                                                      keywords:[NSSet setWithArray:universalObject.keywords]];
                
                CSSearchableItem *item = [[CSSearchableItem alloc]
                                          initWithUniqueIdentifier:dynamicUrl
                                          domainIdentifier:kDomainIdentifier
                                          attributeSet:attributes];
                
                [searchableItems addObject:item];
                
                dispatch_semaphore_signal(indexingSema);

            }
            
            dispatch_semaphore_wait(indexingSema, DISPATCH_TIME_FOREVER);
        });
    }
    
    dispatch_group_wait(workGroup, DISPATCH_TIME_FOREVER);
   
    CSSearchableIndex *index = [[CSSearchableIndex alloc] init];
    [index beginIndexBatch];
    [index indexSearchableItems:searchableItems completionHandler:^(NSError * _Nullable error) {
        
        if (!error) {
            for (NSString* dynamicUrl in mapSpotlightIdentifier) {
                BranchUniversalObject *universalObject = mapSpotlightIdentifier[dynamicUrl];
                universalObject.spotlightIdentifier    = dynamicUrl;
            }
            completion(universalObjects,nil);
        }else {
            completion(nil,error);
        }
        
    }];
    
#endif
}

- (dispatch_queue_t) workQueue {
    @synchronized (self) {
        if (!_workQueue)
            _workQueue = dispatch_queue_create("io.branch.sdk.spotlight.indexing", DISPATCH_QUEUE_CONCURRENT);
        return _workQueue;
    }
}

- (void)indexUsingNSUserActivity:(NSDictionary *)params {
    self.userInfo = params[@"userInfo"];
    self.userInfo[CSSearchableItemActivityIdentifier] = params[@"spotlightId"];
    
    UIViewController *activeViewController = [self getActiveViewController];
    
    if (!activeViewController) {
        // if no view controller, don't index. Current use case: iMessage extensions
        return;
    }
    NSString *uniqueIdentifier = [NSString stringWithFormat:@"io.branch.%@", [[NSBundle mainBundle] bundleIdentifier]];
    // Can't create any weak references here to the userActivity, otherwise it will not index.
    activeViewController.userActivity = [[NSUserActivity alloc] initWithActivityType:uniqueIdentifier];
    activeViewController.userActivity.delegate = self;
    activeViewController.userActivity.title = params[@"title"];
    activeViewController.userActivity.webpageURL = [NSURL URLWithString:params[@"url"]];
    activeViewController.userActivity.eligibleForSearch = YES;
   // activeViewController.userActivity.eligibleForPublicIndexing = [params[@"publiclyIndexable"] boolValue];
    activeViewController.userActivity.eligibleForPublicIndexing = YES;

    activeViewController.userActivity.userInfo = self.userInfo; // This alone doesn't pass userInfo through
    activeViewController.userActivity.requiredUserInfoKeys = [NSSet setWithArray:self.userInfo.allKeys]; // This along with the delegate method userActivityWillSave, however, seem to force the userInfo to come through.
    activeViewController.userActivity.keywords = params[@"keywords"];
    SEL setContentAttributeSetSelector = NSSelectorFromString(@"setContentAttributeSet:");
    ((void (*)(id, SEL, id))[activeViewController.userActivity methodForSelector:setContentAttributeSetSelector])(activeViewController.userActivity, setContentAttributeSetSelector, params[@"attributeSet"]);
    
    [activeViewController.userActivity becomeCurrent];
}

- (void)indexUsingSearchableItem:(NSDictionary*)indexingParam
                   thumbnailData:(NSData*)thumbnailData
                        callback:(void (^_Nullable)(NSString* _Nullable url, NSError * _Nullable error))completion {
    
    if([CSSearchableIndex isIndexingAvailable]) {
        NSString *dynamicUrl = indexingParam[@"url"];
        CSSearchableItem *item = [[CSSearchableItem alloc]
                                  initWithUniqueIdentifier:indexingParam[@"url"]
                                  domainIdentifier:kDomainIdentifier
                                  attributeSet:indexingParam[@"attributeSet"]];

        [[CSSearchableIndex defaultSearchableIndex] indexSearchableItems:@[item]
                                                       completionHandler: ^(NSError * __nullable error) {
                                                           NSString *url = error == nil?dynamicUrl:nil;
                                                           if (completion) {
                                                               completion(url, error);
                                                           }
                                                       }];
    } else {
        NSError* error = [NSError errorWithDomain:BNCErrorDomain code:BNCSpotlightNotAvailableError userInfo:nil];
        if (completion) {
            completion(nil, error);
        }
    }    
}

#pragma mark Helper Methods

- (UIViewController *)getActiveViewController {
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    UIViewController *rootViewController = [UIApplicationClass sharedApplication].keyWindow.rootViewController;
    UIViewController *activeController;
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        activeController = ((UINavigationController *)rootViewController).topViewController;
    } else if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        activeController = ((UITabBarController *)rootViewController).selectedViewController;
    } else {
        activeController = rootViewController;
    }
    return activeController;
}

#pragma mark userActivity Delegate Methods

- (void)userActivityWillSave:(NSUserActivity *)userActivity {
    [userActivity addUserInfoEntriesFromDictionary:self.userInfo];
}

#pragma remove private content from spotlight indexed using Searchable Item

- (void)removeSearchableItemsWithIdentifier:(NSString * _Nonnull)identifier
                                   callback:(void (^_Nullable)(NSError * _Nullable error))completion {
    [self removeSearchableItemsWithIdentifiers:@[identifier] callback:^(NSError * _Nullable error) {
        completion(error);
    }];
}

- (void)removeSearchableItemsWithIdentifiers:(NSArray<NSString *> *_Nonnull)identifiers
                                    callback:(void (^_Nullable)(NSError * _Nullable error))completion {
    if ([CSSearchableIndex isIndexingAvailable]) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithIdentifiers:identifiers completionHandler:^(NSError * _Nullable error) {
            completion(error);
        }];
    }else {
        NSError* error = [NSError errorWithDomain:BNCErrorDomain code:BNCSpotlightNotAvailableError userInfo:nil];
        completion(error);
    }
}

- (void)removeSearchableItemsByBranchSpotlightDomainWithCallback:(void (^_Nullable)(NSError * _Nullable error))completion {
    if ([CSSearchableIndex isIndexingAvailable]) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithDomainIdentifiers:@[kDomainIdentifier] completionHandler:^(NSError * _Nullable error) {
            completion(error);
        }];
    }else {
        NSError* error = [NSError errorWithDomain:BNCErrorDomain code:BNCSpotlightNotAvailableError userInfo:nil];
        completion(error);
    }
}

@end