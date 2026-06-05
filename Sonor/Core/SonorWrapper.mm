#import "SonorWrapper.h"
#import "sonor.h"
#import <Metal/Metal.h>

@interface SonorWrapper () {
    struct sonor_context * ctx;
}
@end
#define S_LOG(fmt, ...) \
    do { \
        NSString *msg = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; \
        NSLog(@"%@", msg); \
    } while (0)

@implementation SonorWrapper

+ (void)initialize {
    if (self == [SonorWrapper class]) {
        S_LOG(@"[SonorWrapper] +initialize called!");
    }
}

- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        S_LOG(@"[SonorWrapper] Initializing with model: %@", modelPath);
        
        S_LOG(@"[SonorWrapper] Checking for Metal device...");
        bool use_gpu = true;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        S_LOG(@"[SonorWrapper] MTLCreateSystemDefaultDevice returned.");
        
        if (!device) {
            use_gpu = false;
            S_LOG(@"[SonorWrapper] ⚠️ No Metal device found, falling back to CPU.");
        } else {
            NSString *name = [device.name lowercaseString];
            S_LOG(@"[SonorWrapper] Detected Metal device: %@", device.name);
            if ([name containsString:@"software"] || [name containsString:@"llvm"] || [name containsString:@"paravirtual"]) {
                use_gpu = false;
                S_LOG(@"[SonorWrapper] ⚠️ Virtual/Software Metal renderer detected, falling back to CPU.");
            }
        }
        
        struct sonor_context_params cparams = sonor_context_default_params();
        cparams.use_gpu = use_gpu;
        
        S_LOG(@"[SonorWrapper] Calling sonor_init_from_file_with_params (GPU: %@)...", use_gpu ? @"YES" : @"NO");
        ctx = sonor_init_from_file_with_params([modelPath UTF8String], cparams);
        if (!ctx) {
            S_LOG(@"[SonorWrapper] ❌ ERROR: sonor_init_from_file_with_params returned NULL for path: %@", modelPath);
            return nil;
        }
        S_LOG(@"[SonorWrapper] ✅ Context initialized successfully!");
    }
    return self;
}

- (void)dealloc {
    if (ctx) {
        sonor_free(ctx);
    }
}

- (NSString *)transcribeAudioBuffer:(float *)samples count:(int)count language:(NSString *)language {
    if (!ctx) return @"";
    
    struct sonor_full_params params = sonor_full_default_params(SONOR_SAMPLING_GREEDY);
    params.print_progress   = false;
    params.print_special    = false;
    params.print_realtime   = false;
    params.print_timestamps = false;
    params.translate        = false;
    
    // Set language from parameter, defaulting to "auto" if not provided
    if (language && [language length] > 0) {
        params.language = [language UTF8String];
    } else {
        params.language = "auto";
    }
    
    params.n_threads        = 4;
    params.offset_ms        = 0;
    params.no_context       = true;
    
    int ret = sonor_full(ctx, params, samples, count);
    if (ret != 0) {
        NSLog(@"Failed to process audio");
        return @"";
    }
    
    int lang_id = sonor_full_lang_id(ctx);
    S_LOG(@"[SonorWrapper] Transcription completed. Detected language ID: %d", lang_id);
    
    const int n_segments = sonor_full_n_segments(ctx);
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < n_segments; ++i) {
        const char *text = sonor_full_get_segment_text(ctx, i);
        if (text) {
            NSString *segmentText = [NSString stringWithUTF8String:text];
            if (segmentText) {
                [result appendString:segmentText];
            }
        }
    }
    
    return [result copy];
}

@end
