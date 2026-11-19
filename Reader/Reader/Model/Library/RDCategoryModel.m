//
//  RDCategoryModel.m
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDCategoryModel.h"

@implementation RDCategoryModel
+ (NSDictionary *)modelCustomPropertyMapper
{
    return @{
        @"name":@"categoryName",
        @"type":@"categoryId"
    };
}

@end
