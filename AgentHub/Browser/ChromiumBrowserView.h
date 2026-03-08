#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AHChromiumBrowserView;

typedef void (^AHChromiumEvaluationCompletion)(NSString* _Nullable valueJSON,
                                               NSString* _Nullable errorMessage);
typedef void (^AHChromiumSnapshotCompletion)(NSData* _Nullable pngData,
                                             NSString* _Nullable errorMessage);

@protocol AHChromiumBrowserViewDelegate <NSObject>
- (void)browserViewDidUpdateState:(AHChromiumBrowserView*)browserView;
- (void)browserView:(AHChromiumBrowserView*)browserView didLogMessage:(NSString*)message;
- (void)browserView:(AHChromiumBrowserView*)browserView
    didFailWithErrorMessage:(NSString*)errorMessage;
@end

@interface AHChromiumBrowserView : NSView

@property(nonatomic, weak, nullable) id<AHChromiumBrowserViewDelegate> delegate;
@property(nonatomic, copy, readonly, nullable) NSString* pageTitle;
@property(nonatomic, copy, readonly, nullable) NSString* currentURL;
@property(nonatomic, copy, readonly, nullable) NSString* lastErrorMessage;
@property(nonatomic, assign, readonly) BOOL isLoading;
@property(nonatomic, assign, readonly) BOOL canGoBack;
@property(nonatomic, assign, readonly) BOOL canGoForward;
@property(nonatomic, assign, readonly, getter=isRuntimeReady) BOOL runtimeReady;

- (void)loadURLString:(NSString*)urlString;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)stopLoading;
- (void)evaluateJavaScript:(NSString*)script
                completion:(AHChromiumEvaluationCompletion)completion;
- (void)capturePNGSnapshot:(AHChromiumSnapshotCompletion)completion;

@end

NS_ASSUME_NONNULL_END
