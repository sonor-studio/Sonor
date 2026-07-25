//
// sonor-encoder-impl.m
//
// This file was automatically generated and should not be edited.
//

#if !__has_feature(objc_arc)
#error This file must be compiled with automatic reference counting enabled (-fobjc-arc)
#endif

#import "sonor-compat.h"
#import "sonor-encoder-impl.h"

@implementation sonor_encoder_implInput

- (instancetype)initWithLogmel_data:(MLMultiArray *)logmel_data {
    self = [super init];
    if (self) {
        _logmel_data = logmel_data;
    }
    return self;
}

- (NSSet<NSString *> *)featureNames {
    return [NSSet setWithArray:@[@"logmel_data"]];
}

- (nullable MLFeatureValue *)featureValueForName:(NSString *)featureName {
    if ([featureName isEqualToString:@"logmel_data"]) {
        return [MLFeatureValue featureValueWithMultiArray:self.logmel_data];
    }
    return nil;
}

@end

@implementation sonor_encoder_implOutput

- (instancetype)initWithOutput:(MLMultiArray *)output {
    self = [super init];
    if (self) {
        _output = output;
    }
    return self;
}

- (NSSet<NSString *> *)featureNames {
    return [NSSet setWithArray:@[@"output"]];
}

- (nullable MLFeatureValue *)featureValueForName:(NSString *)featureName {
    if ([featureName isEqualToString:@"output"]) {
        return [MLFeatureValue featureValueWithMultiArray:self.output];
    }
    return nil;
}

@end

@implementation sonor_encoder_impl


/**
    URL of the underlying .mlmodelc directory.
*/
+ (nullable NSURL *)URLOfModelInThisBundle {
    NSString *assetPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"sonor_encoder_impl" ofType:@"mlmodelc"];
    if (nil == assetPath) { os_log_error(OS_LOG_DEFAULT, "Could not load sonor-encoder-impl.mlmodelc in the bundle resource"); return nil; }
    return [NSURL fileURLWithPath:assetPath];
}


/**
    Initialize sonor_encoder_impl instance from an existing MLModel object.

    Usually the application does not use this initializer unless it makes a subclass of sonor_encoder_impl.
    Such application may want to use `-[MLModel initWithContentsOfURL:configuration:error:]` and `+URLOfModelInThisBundle` to create a MLModel object to pass-in.
*/
- (instancetype)initWithMLModel:(MLModel *)model {
    if (model == nil) {
        return nil;
    }
    self = [super init];
    if (self != nil) {
        _model = model;
    }
    return self;
}


/**
    Initialize sonor_encoder_impl instance with the model in this bundle.
*/
- (nullable instancetype)init {
    return [self initWithContentsOfURL:(NSURL * _Nonnull)self.class.URLOfModelInThisBundle error:nil];
}


/**
    Initialize sonor_encoder_impl instance with the model in this bundle.

    @param configuration The model configuration object
    @param error If an error occurs, upon return contains an NSError object that describes the problem. If you are not interested in possible errors, pass in NULL.
*/
- (nullable instancetype)initWithConfiguration:(MLModelConfiguration *)configuration error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    return [self initWithContentsOfURL:(NSURL * _Nonnull)self.class.URLOfModelInThisBundle configuration:configuration error:error];
}


/**
    Initialize sonor_encoder_impl instance from the model URL.

    @param modelURL URL to the .mlmodelc directory for sonor_encoder_impl.
    @param error If an error occurs, upon return contains an NSError object that describes the problem. If you are not interested in possible errors, pass in NULL.
*/
- (nullable instancetype)initWithContentsOfURL:(NSURL *)modelURL error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    MLModel *model = [MLModel modelWithContentsOfURL:modelURL error:error];
    if (model == nil) { return nil; }
    return [self initWithMLModel:model];
}


/**
    Initialize sonor_encoder_impl instance from the model URL.

    @param modelURL URL to the .mlmodelc directory for sonor_encoder_impl.
    @param configuration The model configuration object
    @param error If an error occurs, upon return contains an NSError object that describes the problem. If you are not interested in possible errors, pass in NULL.
*/
- (nullable instancetype)initWithContentsOfURL:(NSURL *)modelURL configuration:(MLModelConfiguration *)configuration error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    MLModel *model = [MLModel modelWithContentsOfURL:modelURL configuration:configuration error:error];
    if (model == nil) { return nil; }
    return [self initWithMLModel:model];
}


/**
    Construct sonor_encoder_impl instance asynchronously with configuration.
    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

    @param configuration The model configuration
    @param handler When the model load completes successfully or unsuccessfully, the completion handler is invoked with a valid sonor_encoder_impl instance or NSError object.
*/
+ (void)loadWithConfiguration:(MLModelConfiguration *)configuration completionHandler:(void (^)(sonor_encoder_impl * _Nullable model, NSError * _Nullable error))handler {
    [self loadContentsOfURL:(NSURL * _Nonnull)[self URLOfModelInThisBundle]
              configuration:configuration
          completionHandler:handler];
}


/**
    Construct sonor_encoder_impl instance asynchronously with URL of .mlmodelc directory and optional configuration.

    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

    @param modelURL The model URL.
    @param configuration The model configuration
    @param handler When the model load completes successfully or unsuccessfully, the completion handler is invoked with a valid sonor_encoder_impl instance or NSError object.
*/
+ (void)loadContentsOfURL:(NSURL *)modelURL configuration:(MLModelConfiguration *)configuration completionHandler:(void (^)(sonor_encoder_impl * _Nullable model, NSError * _Nullable error))handler {
    [MLModel loadContentsOfURL:modelURL
                 configuration:configuration
             completionHandler:^(MLModel *model, NSError *error) {
        if (model != nil) {
            sonor_encoder_impl *typedModel = [[sonor_encoder_impl alloc] initWithMLModel:model];
            handler(typedModel, nil);
        } else {
            handler(nil, error);
        }
    }];
}

- (nullable sonor_encoder_implOutput *)predictionFromFeatures:(sonor_encoder_implInput *)input error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    return [self predictionFromFeatures:input options:[[MLPredictionOptions alloc] init] error:error];
}

- (nullable sonor_encoder_implOutput *)predictionFromFeatures:(sonor_encoder_implInput *)input options:(MLPredictionOptions *)options error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    id<MLFeatureProvider> outFeatures = [self.model predictionFromFeatures:input options:options error:error];
    if (!outFeatures) { return nil; }
    return [[sonor_encoder_implOutput alloc] initWithOutput:(MLMultiArray *)[outFeatures featureValueForName:@"output"].multiArrayValue];
}

- (void)predictionFromFeatures:(sonor_encoder_implInput *)input completionHandler:(void (^)(sonor_encoder_implOutput * _Nullable output, NSError * _Nullable error))completionHandler {
    [self.model predictionFromFeatures:input completionHandler:^(id<MLFeatureProvider> prediction, NSError *predictionError) {
        if (prediction != nil) {
            sonor_encoder_implOutput *output = [[sonor_encoder_implOutput alloc] initWithOutput:(MLMultiArray *)[prediction featureValueForName:@"output"].multiArrayValue];
            completionHandler(output, predictionError);
        } else {
            completionHandler(nil, predictionError);
        }
    }];
}

- (void)predictionFromFeatures:(sonor_encoder_implInput *)input options:(MLPredictionOptions *)options completionHandler:(void (^)(sonor_encoder_implOutput * _Nullable output, NSError * _Nullable error))completionHandler {
    [self.model predictionFromFeatures:input options:options completionHandler:^(id<MLFeatureProvider> prediction, NSError *predictionError) {
        if (prediction != nil) {
            sonor_encoder_implOutput *output = [[sonor_encoder_implOutput alloc] initWithOutput:(MLMultiArray *)[prediction featureValueForName:@"output"].multiArrayValue];
            completionHandler(output, predictionError);
        } else {
            completionHandler(nil, predictionError);
        }
    }];
}

- (nullable sonor_encoder_implOutput *)predictionFromLogmel_data:(MLMultiArray *)logmel_data error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    sonor_encoder_implInput *input_ = [[sonor_encoder_implInput alloc] initWithLogmel_data:logmel_data];
    return [self predictionFromFeatures:input_ error:error];
}

- (nullable NSArray<sonor_encoder_implOutput *> *)predictionsFromInputs:(NSArray<sonor_encoder_implInput*> *)inputArray options:(MLPredictionOptions *)options error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    id<MLBatchProvider> inBatch = [[MLArrayBatchProvider alloc] initWithFeatureProviderArray:inputArray];
    id<MLBatchProvider> outBatch = [self.model predictionsFromBatch:inBatch options:options error:error];
    if (!outBatch) { return nil; }
    NSMutableArray<sonor_encoder_implOutput*> *results = [NSMutableArray arrayWithCapacity:(NSUInteger)outBatch.count];
    for (NSInteger i = 0; i < outBatch.count; i++) {
        id<MLFeatureProvider> resultProvider = [outBatch featuresAtIndex:i];
        sonor_encoder_implOutput * result = [[sonor_encoder_implOutput alloc] initWithOutput:(MLMultiArray *)[resultProvider featureValueForName:@"output"].multiArrayValue];
        [results addObject:result];
    }
    return results;
}

@end
