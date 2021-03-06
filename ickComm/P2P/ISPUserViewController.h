//
//  ISPUserViewController.h
//  ickComm
//
//  Created by Jörg Schwieder on 03.06.12.
//  Copyright (c) 2014 ickStream GmbH. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol ISPUserTokenDelegateProtocol

- (void)hasEnteredToken:(NSString *)token;

@end



@interface ISPUserViewController : UIViewController<UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UITextField * tokenEntry;
@property (strong, nonatomic) IBOutlet UILabel * alert;

- (id)initWithDelegate:(id<ISPUserTokenDelegateProtocol>)aDelegate;
- (void)showAlert;

@end
