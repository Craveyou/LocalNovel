//
//  RDToastView.h
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "MBProgressHUD.h"
#define kAnimateDelay 1.5

@interface RDToastView : MBProgressHUD
+(void)showText:(NSString *)text delay:(NSTimeInterval)delay inView:(UIView *)view;


+(void)showText:(NSString *)text delay:(NSTimeInterval)delay inView:(UIView *)view dismiss:(void(^)(void))dismiss;
@end

