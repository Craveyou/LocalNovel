//
//  RDHttpModel.m
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDHttpModel.h"

@implementation RDHttpModel
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
            @"code": @"result.code",
            @"msg": @"result.msg",
            @"data": @"data",
    };
}
@end
