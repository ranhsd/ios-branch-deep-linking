//
//  BNCSpotlightService.h
//  Branch-SDK
//
//  Created by Parth Kalavadia on 8/10/17.
//  Copyright © 2017 Branch Metrics. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BranchUniversalObject.h"

@interface BNCSpotlightService : NSObject

- (void)indexContentUsingUserActivityWithTitle:(NSString *)title
                                   description:(NSString *)description
                                   canonicalId:(NSString *)canonicalId
                                          type:(NSString *)type
                                  thumbnailUrl:(NSURL *)thumbnailUrl
                                      keywords:(NSSet *)keywords
                                      userInfo:(NSDictionary *)userInfo
                                expirationDate:(NSDate *)expirationDate
                                      callback:(callbackWithUrl)callback
                             spotlightCallback:(callbackWithUrlAndSpotlightIdentifier)spotlightCallback;

- (void)indexContentUsingCSSearchableItemWithTitle:(NSString *)title
                                       CanonicalId:(NSString *)canonicalId
                                       description:(NSString *)description
                                              type:(NSString *)type
                                      thumbnailUrl:(NSURL *)thumbnailUrl
                                          userInfo:(NSDictionary *)userInfo
                                          keywords:(NSSet *)keywords
                                          callback:(callbackWithUrl)callback
                                 spotlightCallback:(callbackWithUrlAndSpotlightIdentifier)spotlightCallback;

- (void)removePrivateContentWithSpotlightIdentifier:(NSString *)spotLightIdentifier completionHandler:(completion)completion;

- (void)removeMultiplePrivateContentOfSpotlightIdentifiers:(NSArray<NSString *> *)identifiers completionHandler:(completion)completion;

- (void)removeAllPrivateContentByBranchWithcompletionHandler:(completion)completion;
@end
