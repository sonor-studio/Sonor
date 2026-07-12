#import "SonorWrapper.h"
#import "sonor.h"
#import <Metal/Metal.h>

@interface SonorWrapper () {
    struct sonor_context * ctx;
}
@end

@implementation SonorWrapper


- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        bool use_gpu = true;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        
        if (!device) {
            use_gpu = false;
        } else {
            NSString *name = [device.name lowercaseString];
            if ([name containsString:@"software"] || [name containsString:@"llvm"] || [name containsString:@"paravirtual"]) {
                use_gpu = false;
            }
        }
        
        struct sonor_context_params cparams = sonor_context_default_params();
        cparams.use_gpu = use_gpu;
        
        ctx = sonor_init_from_file_with_params([modelPath UTF8String], cparams);
        if (!ctx) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (ctx) {
        sonor_free(ctx);
    }
}

- (NSString *)transcribeAudioBuffer:(float *)samples count:(int)count language:(NSString *)language initialPrompt:(NSString *)initialPrompt {
    if (!ctx) return @"";
    
    struct sonor_full_params params = sonor_full_default_params(SONOR_SAMPLING_GREEDY);
    params.print_progress   = false;
    params.print_special    = false;
    params.print_realtime   = false;
    params.print_timestamps = false;
    
    // Set language from parameter, defaulting to "auto" if not provided
    if (language && [language length] > 0) {
        params.language = strdup([language UTF8String]);
    } else {
        params.language = strdup("auto");
    }
    
    if (initialPrompt && [initialPrompt length] > 0) {
        params.initial_prompt = strdup([initialPrompt UTF8String]);
    }
    
    params.n_threads        = 4;
    params.offset_ms        = 0;
    params.no_context       = true;
    
    int ret = sonor_full(ctx, params, samples, count);
    
    if (params.language) {
        free((void *)params.language);
    }
    
    if (params.initial_prompt) {
        free((void *)params.initial_prompt);
    }
    
    if (ret != 0) {
        return @"";
    }
    
    int lang_id = sonor_full_lang_id(ctx);
    
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
