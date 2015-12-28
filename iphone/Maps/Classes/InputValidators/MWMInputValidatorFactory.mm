#import "MWMInputEmailValidator.h"
#import "MWMInputLoginValidator.h"
#import "MWMInputPasswordValidator.h"
#import "MWMInputValidator.h"
#import "MWMInputValidatorFactory.h"

@implementation MWMInputValidatorFactory

+ (MWMInputValidator *)validator:(NSString *)validator
{
  if ([validator isEqualToString:[MWMInputLoginValidator className]])
    return [[MWMInputLoginValidator alloc] init];
  if ([validator isEqualToString:[MWMInputPasswordValidator className]])
    return [[MWMInputPasswordValidator alloc] init];
  if ([validator isEqualToString:[MWMInputEmailValidator className]])
    return [[MWMInputEmailValidator alloc] init];
  return [[MWMInputValidator alloc] init];
}

@end
