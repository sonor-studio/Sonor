#import "SonorWrapper.h"
#import "sonor.h"

@interface SonorWrapper () {
    struct sonor_context * ctx;
}
@end

@implementation SonorWrapper

- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        NSLog(@"[SonorWrapper] Inicjalizacja z modelem: %@", modelPath);
        struct sonor_context_params cparams = sonor_context_default_params();
        cparams.use_gpu = true; // Włączamy GPU ponownie
        
        ctx = sonor_init_from_file_with_params([modelPath UTF8String], cparams);
        if (!ctx) {
            NSLog(@"[SonorWrapper] ❌ BŁĄD: sonor_init_from_file_with_params zwrócił NULL dla ścieżki: %@", modelPath);
            return nil;
        }
        NSLog(@"[SonorWrapper] ✅ Kontekst zainicjalizowany pomyślnie");
    }
    return self;
}

- (void)dealloc {
    if (ctx) {
        sonor_free(ctx);
    }
}

- (NSString *)transcribeAudioBuffer:(float *)samples count:(int)count {
    if (!ctx) return @"";
    
    struct sonor_full_params params = sonor_full_default_params(SONOR_SAMPLING_GREEDY);
    params.print_progress   = false;
    params.print_special    = false;
    params.print_realtime   = false;
    params.print_timestamps = false;
    params.translate        = false;
    params.language         = "pl";
    params.n_threads        = 4;
    params.offset_ms        = 0;
    
    int ret = sonor_full(ctx, params, samples, count);
    if (ret != 0) {
        NSLog(@"Failed to process audio");
        return @"";
    }
    
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
