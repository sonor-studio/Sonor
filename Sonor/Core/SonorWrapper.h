#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SonorWrapper : NSObject

- (instancetype)initWithModelPath:(NSString *)modelPath;
- (NSString *)transcribeAudioBuffer:(float *)samples count:(int)count;

@end

NS_ASSUME_NONNULL_END
