//
//  JSONAPIResource.m
//  JSONAPI
//
//  Created by Josh Holtz on 12/24/13.
//  Copyright (c) 2013 Josh Holtz. All rights reserved.
//

#import "JSONAPIResource.h"

#import "JSONAPIResourceFormatter.h"
#import "JSONAPIResourceLinker.h"

#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - JSONAPIResource

@interface JSONAPIResource()

@property (nonatomic, strong) NSDictionary *__dictionary;
@property (nonatomic, strong) NSMutableDictionary *__resourceLinks;

@end

@implementation JSONAPIResource

#pragma mark -
#pragma mark - Class Methods

+ (NSArray*)jsonAPIResources:(NSArray*)array withLinked:(NSDictionary*)linked {
    return [JSONAPIResource jsonAPIResources:array withLinked:linked withClass:[self class]];
}

+ (NSArray*)jsonAPIResources:(NSArray*)array withLinked:(NSDictionary*)linked withClass:(Class)resourceObjectClass {
    if (resourceObjectClass == nil) {
        resourceObjectClass = [self class];
    }

    NSMutableArray *mutableArray = [[NSMutableArray alloc] init];
    for (NSDictionary *dict in array) {
        [mutableArray addObject:[[resourceObjectClass alloc] initWithDictionary:dict withLinked:linked]];
    }

    return mutableArray;
}

+ (id)jsonAPIResource:(NSDictionary*)dictionary withLinked:(NSDictionary*)linked {
    return [JSONAPIResource jsonAPIResource:dictionary withLinked:linked withClass:[self class]];
}

+ (id)jsonAPIResource:(NSDictionary*)dictionary withLinked:(NSDictionary*)linked withClass:(Class)resourceObjectClass {
    if (resourceObjectClass == nil) {
        resourceObjectClass = [self class];
    }

    return [[resourceObjectClass alloc] initWithDictionary:dictionary withLinked:linked];
}

#pragma mark -
#pragma mark - Instance Methods

- (id)init {
    self = [super init];
    if (self) {
        self.__resourceLinks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)initWithDictionary:(NSDictionary*)dict withLinked:(NSDictionary*)linked {
    self = [self init];
    if (self) {
        [self setWithDictionary:dict];
        [self linkLinks:linked];

    }
    return self;
}

- (id)objectForKey:(NSString*)key {
    return [self.__dictionary objectForKey:key];
}

- (id)linkedResourceForKey:(NSString *)key {
    return [self.__resourceLinks objectForKey:key];
}

- (NSDictionary *)mapKeysToProperties {
    return [[NSDictionary alloc] init];
}

- (void)setWithDictionary:(NSDictionary*)dict {
    self.__dictionary = dict;

    // Loops through all keys to map to propertiess
    NSDictionary *userMap = [self mapKeysToProperties];

    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithDictionary:userMap];
    [map addEntriesFromDictionary:@{
                                         @"id" : @"ID",
                                         @"href" : @"href",
                                         @"links" : @"links"
                                         }];

    for (NSString *key in [map allKeys]) {

        id value = [dict objectForKey:key];
        if (value == [NSNull null]) {
            value = nil;
        }

        NSString *property = [map objectForKey:key];

        NSRange inflateRange = [property rangeOfString:@"."];
        NSRange formatRange = [property rangeOfString:@":"];

        @try {
            if (inflateRange.location != NSNotFound) {

            } else if (formatRange.location != NSNotFound) {
                NSString *formatFunction = [property substringToIndex:formatRange.location];
                property = [property substringFromIndex:(formatRange.location+1)];

                [self setValue:[JSONAPIResourceFormatter performFormatBlock:value withName:formatFunction] forKey:property ];
            } else {
                [self setValue:value forKey:property ];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"JSONAPIResource Warning - %@", [exception description]);
        }
    }
}

- (void)revert {
    [self setWithDictionary: self.__dictionary];
    [self setLinks];
}

- (void)copyFrom:(JSONAPIResource*)other {
    [self setWithDictionary: other.__dictionary];

    // Copy NSObject subclasses
    [self set__resourceLinks:[other.__resourceLinks copyWithZone: NULL]];
    [self setLinks];
}

- (void)linkLinks:(NSDictionary*)linked {
    // Loops through links of resources
    for (NSString *linkTypeUnmapped in self.links.allKeys) {

        NSString *linkType = [JSONAPIResourceLinker linkedType:linkTypeUnmapped];
        if (linkType == nil) {
            linkType = linkTypeUnmapped;
        }

        // Gets linked objects for the resource
        id linksTo = [self.links objectForKey:linkTypeUnmapped];
        if ([linksTo isKindOfClass:[NSNumber class]] == YES || [linksTo isKindOfClass:[NSString class]] == YES) {

            JSONAPIResource *linkedResource = [[linked objectForKey:linkType] objectForKey:linksTo];

            if (linkedResource != nil) {
                [self.__resourceLinks setObject:linkedResource forKey:linkTypeUnmapped];
            }

        } else if ([linksTo isKindOfClass:[NSArray class]] == YES) {
            NSMutableArray *linkedResources = [NSMutableArray array];
            [self.__resourceLinks setObject:linkedResources forKey:linkTypeUnmapped];
            for (id linkedId in linksTo) {
                JSONAPIResource *linkedResource = [[linked objectForKey:linkType] objectForKey:linkedId];
                if (linkedResource != nil) {
                    [linkedResources addObject:linkedResource];
                }
            }

        }
    }
    [self setLinks];
}

- (void) setLinks {
    // Link links for mapped key to properties
    for (NSString *key in [self mapKeysToProperties]) {
        if ([key hasPrefix:@"links."] == YES) {

            NSString *propertyName = [[self mapKeysToProperties] objectForKey:key];
            NSString *linkedResource = [key stringByReplacingOccurrencesOfString:@"links." withString:@""];

            id resource = [self linkedResourceForKey:linkedResource];
            if (resource != nil) {

                @try {
                    [self setValue:resource forKey:propertyName];
                }
                @catch (NSException *exception) {
                    NSLog(@"JSONAPIResource Warning - %@", [exception description]);
                }
            }

        }
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    id copy = [[[self class] alloc] initWithDictionary:[self.__dictionary copyWithZone:zone] withLinked:nil];

    if (copy) {
        // Copy NSObject subclasses
        NSLog(@"__resourceLinks - %@", self.__resourceLinks);
        [copy set__resourceLinks:[self.__resourceLinks copyWithZone:zone]];

        // Link links for mapped key to properties
        for (NSString *key in [copy __resourceLinks]) {
            @try {
                [copy setValue:[[copy __resourceLinks] objectForKey:key] forKey:key];
            }
            @catch (NSException *exception) {
                NSLog(@"JSONAPIResource Warning - %@", [exception description]);
            }
        }

    }

    return copy;
}

#pragma mark - NSCoding

- (NSArray *)propertyKeys
{
    NSMutableArray *array = [NSMutableArray array];
    Class class = [self class];
    while (class != [NSObject class])
    {
        unsigned int propertyCount;
        objc_property_t *properties = class_copyPropertyList(class, &propertyCount);
        for (int i = 0; i < propertyCount; i++)
        {
            //get property
            objc_property_t property = properties[i];
            const char *propertyName = property_getName(property);
            NSString *key = [NSString stringWithCString:propertyName encoding:NSUTF8StringEncoding];

            //check if read-only
            BOOL readonly = NO;
            const char *attributes = property_getAttributes(property);
            NSString *encoding = [NSString stringWithCString:attributes encoding:NSUTF8StringEncoding];
            if ([[encoding componentsSeparatedByString:@","] containsObject:@"R"])
            {
                readonly = YES;

                //see if there is a backing ivar with a KVC-compliant name
                NSRange iVarRange = [encoding rangeOfString:@",V"];
                if (iVarRange.location != NSNotFound)
                {
                    NSString *iVarName = [encoding substringFromIndex:iVarRange.location + 2];
                    if ([iVarName isEqualToString:key] ||
                        [iVarName isEqualToString:[@"_" stringByAppendingString:key]])
                    {
                        //setValue:forKey: will still work
                        readonly = NO;
                    }
                }
            }

            if (!readonly)
            {
                //exclude read-only properties
                [array addObject:key];
            }
        }
        free(properties);
        class = [class superclass];
    }
    return array;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [self init]))
    {
        for (NSString *key in [self propertyKeys])
        {
            id value = [aDecoder decodeObjectForKey:key];
            [self setValue:value forKey:key];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    for (NSString *key in [self propertyKeys])
    {
        id value = [self valueForKey:key];
        [aCoder encodeObject:value forKey:key];
    }
}

@end
