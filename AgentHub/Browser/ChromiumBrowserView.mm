#import "ChromiumBrowserView.h"

#import <crt_externs.h>

#include <cstring>
#include <string>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"
#include "include/cef_request_context.h"
#include "include/internal/cef_types_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

static NSString* AHJSONStringFromObject(id object) {
  if (!object || object == [NSNull null]) {
    return @"null";
  }

  if ([object isKindOfClass:[NSString class]]) {
    return object;
  }

  if (![NSJSONSerialization isValidJSONObject:object]) {
    return [[object description] copy];
  }

  NSError* error = nil;
  NSData* data =
      [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
  if (!data || error) {
    return [[object description] copy];
  }

  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSDictionary* AHJSONDictionaryFromString(NSString* string) {
  NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) {
    return nil;
  }

  NSError* error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![object isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  return object;
}

static NSString* AHTrimmedString(NSString* value) {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString* AHNormalizedURLString(NSString* input) {
  NSString* trimmed = AHTrimmedString(input);
  if (trimmed.length == 0) {
    return @"about:blank";
  }

  if ([trimmed containsString:@"://"]) {
    return trimmed;
  }

  return [@"https://" stringByAppendingString:trimmed];
}

static NSString* AHNSStringFromCefString(const CefString& value) {
  const std::u16string& wide = value.ToString16();
  if (wide.empty()) {
    return @"";
  }

  return [[NSString alloc] initWithCharacters:(const unichar*)wide.data()
                                       length:wide.size()] ?: @"";
}

static NSString* AHNSStringFromUTF8Bytes(const void* bytes, size_t size) {
  if (!bytes || size == 0) {
    return @"{}";
  }

  return [[NSString alloc] initWithBytes:bytes
                                  length:size
                                encoding:NSUTF8StringEncoding] ?: @"{}";
}

static std::string AHUTF8String(NSString* value) {
  const char* utf8 = value.UTF8String ?: "";
  return std::string(utf8);
}

static NSNotificationName const AHChromiumContextInitializedNotification =
    @"AHChromiumContextInitializedNotification";

@class AHChromiumBrowserView;

@interface AHChromiumRuntime : NSObject
+ (instancetype)sharedRuntime;
- (BOOL)ensureInitialized:(NSString* _Nullable __autoreleasing*)errorMessage;
- (BOOL)isContextInitialized;
- (void)scheduleMessagePumpWorkAfterDelay:(NSTimeInterval)delay;
- (void)contextDidInitialize;
@end

@interface AHChromiumBrowserView ()
- (void)didCreateBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)browserWillClose:(CefRefPtr<CefBrowser>)browser;
- (void)didReceiveTitle:(NSString*)title;
- (void)didReceiveMainFrameURL:(NSString*)urlString;
- (void)didReceiveLoadingState:(BOOL)isLoading
                    canGoBack:(BOOL)canGoBack
                 canGoForward:(BOOL)canGoForward;
- (void)didReceiveLoadErrorForURL:(NSString*)urlString message:(NSString*)message;
- (void)didReceiveDevToolsMessageWithID:(int)messageID
                                success:(BOOL)success
                            payloadJSON:(NSString*)payloadJSON;
- (void)pollBrowserState:(NSTimer*)timer;
@end

static void AHDispatchToOwner(__weak AHChromiumBrowserView* owner,
                              void (^block)(AHChromiumBrowserView* owner)) {
  dispatch_async(dispatch_get_main_queue(), ^{
    AHChromiumBrowserView* strongOwner = owner;
    if (!strongOwner) {
      return;
    }
    block(strongOwner);
  });
}

class AHChromiumApp : public CefApp {
 public:
  AHChromiumApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return browser_process_handler_;
  }

 private:
  class BrowserProcessHandler : public CefBrowserProcessHandler {
   public:
    BrowserProcessHandler() = default;

    void OnContextInitialized() override {
      dispatch_async(dispatch_get_main_queue(), ^{
        [[AHChromiumRuntime sharedRuntime] contextDidInitialize];
      });
    }

    void OnScheduleMessagePumpWork(int64_t delay_ms) override {
      NSTimeInterval delay =
          delay_ms > 0 ? static_cast<NSTimeInterval>(delay_ms) / 1000.0 : 0.0;
      [[AHChromiumRuntime sharedRuntime] scheduleMessagePumpWorkAfterDelay:delay];
    }

   private:
    IMPLEMENT_REFCOUNTING(BrowserProcessHandler);
    DISALLOW_COPY_AND_ASSIGN(BrowserProcessHandler);
  };

  CefRefPtr<BrowserProcessHandler> browser_process_handler_ =
      new BrowserProcessHandler();

  IMPLEMENT_REFCOUNTING(AHChromiumApp);
  DISALLOW_COPY_AND_ASSIGN(AHChromiumApp);
};

class AHChromiumClient : public CefClient,
                         public CefDisplayHandler,
                         public CefLifeSpanHandler,
                         public CefLoadHandler {
 public:
  explicit AHChromiumClient(AHChromiumBrowserView* owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (!frame || !frame->IsMain()) {
      return;
    }
    NSString* urlString = AHNSStringFromCefString(url);
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didReceiveMainFrameURL:urlString];
    });
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    NSString* titleString = AHNSStringFromCefString(title);
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didReceiveTitle:titleString];
    });
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didCreateBrowser:browser];
    });
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner browserWillClose:browser];
    });
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didReceiveLoadingState:isLoading
                          canGoBack:canGoBack
                       canGoForward:canGoForward];
    });
  }

  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    if (!frame || !frame->IsMain()) {
      return;
    }

    NSString* url = AHNSStringFromCefString(failedUrl);
    NSString* message = [NSString stringWithFormat:@"Failed to load %@ (%d): %@",
                                                   url.length > 0 ? url : @"page",
                                                   static_cast<int>(errorCode),
                                                   AHNSStringFromCefString(errorText)];
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didReceiveLoadErrorForURL:url message:message];
    });
  }

 private:
  __weak AHChromiumBrowserView* owner_;

  IMPLEMENT_REFCOUNTING(AHChromiumClient);
  DISALLOW_COPY_AND_ASSIGN(AHChromiumClient);
};

class AHChromiumDevToolsObserver : public CefDevToolsMessageObserver {
 public:
  explicit AHChromiumDevToolsObserver(AHChromiumBrowserView* owner)
      : owner_(owner) {}

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override {
    NSString* payloadJSON = AHNSStringFromUTF8Bytes(result, result_size);
    AHDispatchToOwner(owner_, ^(AHChromiumBrowserView* owner) {
      [owner didReceiveDevToolsMessageWithID:message_id
                                     success:success
                                 payloadJSON:payloadJSON];
    });
  }

 private:
  __weak AHChromiumBrowserView* owner_;

  IMPLEMENT_REFCOUNTING(AHChromiumDevToolsObserver);
  DISALLOW_COPY_AND_ASSIGN(AHChromiumDevToolsObserver);
};

@implementation AHChromiumRuntime {
  BOOL _initialized;
  BOOL _isPumping;
  NSString* _initializationError;
  CefScopedLibraryLoader* _libraryLoader;
  CefRefPtr<CefApp> _app;
  BOOL _contextInitialized;
  NSUInteger _scheduledPumpGeneration;
  dispatch_source_t _fallbackPumpTimer;
}

+ (instancetype)sharedRuntime {
  static AHChromiumRuntime* runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[AHChromiumRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (!self) {
    return nil;
  }

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(applicationWillTerminate:)
                                               name:NSApplicationWillTerminateNotification
                                             object:nil];
  return self;
}

- (void)dealloc {
  if (_fallbackPumpTimer) {
    dispatch_source_cancel(_fallbackPumpTimer);
    _fallbackPumpTimer = nil;
  }
  if (_libraryLoader) {
    delete _libraryLoader;
    _libraryLoader = nullptr;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)ensureInitialized:(NSString* _Nullable __autoreleasing*)errorMessage {
  if (_initialized) {
    return YES;
  }

  if (_initializationError) {
    if (errorMessage) {
      *errorMessage = _initializationError;
    }
    return NO;
  }

  NSString* frameworkPath = [NSBundle.mainBundle.privateFrameworksPath
      stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
  NSString* resourcesPath = NSBundle.mainBundle.resourcePath;
  NSString* localesPath = [resourcesPath stringByAppendingPathComponent:@"locales"];

  if (frameworkPath.length == 0) {
    _initializationError = @"Chromium runtime bundle paths are missing.";
    if (errorMessage) {
      *errorMessage = _initializationError;
    }
    return NO;
  }

  NSString* supportRoot = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
  NSString* cacheDirectory = [supportRoot
      stringByAppendingPathComponent:@"AgentHub/ChromiumPrototype/Profile"];
  [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

  if (!_libraryLoader) {
    _libraryLoader = new CefScopedLibraryLoader();
  }

  if (!_libraryLoader->LoadInMain()) {
    _initializationError = @"Failed to dynamically load the Chromium framework.";
    if (errorMessage) {
      *errorMessage = _initializationError;
    }
    return NO;
  }

  CefMainArgs mainArgs(*_NSGetArgc(), *_NSGetArgv());
  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.log_severity = LOGSEVERITY_INFO;
  CefString(&settings.framework_dir_path) = AHUTF8String(frameworkPath);
  CefString(&settings.main_bundle_path) = AHUTF8String(NSBundle.mainBundle.bundlePath);
  CefString(&settings.resources_dir_path) = AHUTF8String(resourcesPath);
  CefString(&settings.locales_dir_path) = AHUTF8String(localesPath);
  CefString(&settings.cache_path) = AHUTF8String(cacheDirectory);

  _app = new AHChromiumApp();
  if (!CefInitialize(mainArgs, settings, _app, nullptr)) {
    _app = nullptr;
    _initializationError = @"CEF failed to initialize.";
    if (errorMessage) {
      *errorMessage = _initializationError;
    }
    return NO;
  }

  _initialized = YES;
  [self startFallbackPumpTimer];
  [self scheduleMessagePumpWorkAfterDelay:0];
  return YES;
}

- (BOOL)isContextInitialized {
  return _contextInitialized;
}

- (void)contextDidInitialize {
  if (_contextInitialized) {
    return;
  }

  _contextInitialized = YES;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:AHChromiumContextInitializedNotification
                    object:self];
}

- (void)pumpCEF {
  if (!_initialized || _isPumping) {
    return;
  }

  _isPumping = YES;
  CefDoMessageLoopWork();
  _isPumping = NO;
}

- (void)scheduleMessagePumpWorkAfterDelay:(NSTimeInterval)delay {
  if (!_initialized) {
    return;
  }

  _scheduledPumpGeneration += 1;
  NSUInteger generation = _scheduledPumpGeneration;
  dispatch_time_t when =
      delay <= 0 ? DISPATCH_TIME_NOW
                 : dispatch_time(DISPATCH_TIME_NOW,
                                 static_cast<int64_t>(delay * NSEC_PER_SEC));
  dispatch_after(when, dispatch_get_main_queue(), ^{
    if (!self->_initialized || generation != self->_scheduledPumpGeneration) {
      return;
    }
    [self pumpCEF];
  });
}

- (void)startFallbackPumpTimer {
  if (_fallbackPumpTimer) {
    return;
  }

  dispatch_queue_t queue = dispatch_get_main_queue();
  _fallbackPumpTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
  if (!_fallbackPumpTimer) {
    return;
  }

  dispatch_source_set_timer(_fallbackPumpTimer,
                            dispatch_time(DISPATCH_TIME_NOW, 0),
                            static_cast<uint64_t>(NSEC_PER_SEC / 60),
                            static_cast<uint64_t>(NSEC_PER_SEC / 240));
  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(_fallbackPumpTimer, ^{
    AHChromiumRuntime* strongSelf = weakSelf;
    if (!strongSelf || !strongSelf->_initialized) {
      return;
    }
    [strongSelf pumpCEF];
  });
  dispatch_resume(_fallbackPumpTimer);
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  if (!_initialized) {
    return;
  }

  if (_fallbackPumpTimer) {
    dispatch_source_cancel(_fallbackPumpTimer);
    _fallbackPumpTimer = nil;
  }
  _scheduledPumpGeneration += 1;
  CefShutdown();
  _app = nullptr;
  _initialized = NO;
  _contextInitialized = NO;

  if (_libraryLoader) {
    delete _libraryLoader;
    _libraryLoader = nullptr;
  }
}

@end

@implementation AHChromiumBrowserView {
  CefRefPtr<AHChromiumClient> _client;
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<AHChromiumDevToolsObserver> _devToolsObserver;
  CefRefPtr<CefRegistration> _devToolsRegistration;
  NSMutableDictionary<NSNumber*, id>* _pendingCompletions;
  NSString* _queuedURLString;
  BOOL _browserCreationRequested;
  NSString* _pageTitle;
  NSString* _currentURL;
  NSString* _lastErrorMessage;
  BOOL _isLoading;
  BOOL _canGoBack;
  BOOL _canGoForward;
  BOOL _runtimeReady;
  NSTimer* _statePollTimer;
}

@synthesize pageTitle = _pageTitle;
@synthesize currentURL = _currentURL;
@synthesize lastErrorMessage = _lastErrorMessage;
@synthesize isLoading = _isLoading;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize runtimeReady = _runtimeReady;

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (!self) {
    return nil;
  }

  _pendingCompletions = [NSMutableDictionary dictionary];
  _pageTitle = @"Chromium Prototype";
  _currentURL = @"about:blank";
  self.wantsLayer = YES;
  self.layer.backgroundColor = NSColor.blackColor.CGColor;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(contextInitialized:)
                                               name:AHChromiumContextInitializedNotification
                                             object:[AHChromiumRuntime sharedRuntime]];
  return self;
}

- (void)dealloc {
  [_statePollTimer invalidate];
  _statePollTimer = nil;
  [_pendingCompletions removeAllObjects];
  _devToolsRegistration = nullptr;
  _devToolsObserver = nullptr;
  _browser = nullptr;
  _client = nullptr;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self ensureBrowserCreated];
}

- (void)contextInitialized:(NSNotification*)notification {
  [self.delegate browserView:self didLogMessage:@"CEF browser context initialized."];
  [self ensureBrowserCreated];
}

- (void)layout {
  [super layout];
  [self ensureBrowserCreated];

  if (_browser) {
    CefRefPtr<CefBrowserHost> host = _browser->GetHost();
    if (host) {
      host->WasResized();
    }
  }
}

- (void)loadURLString:(NSString*)urlString {
  NSString* normalized = AHNormalizedURLString(urlString);
  _queuedURLString = normalized;
  if (!_browser) {
    _queuedURLString = normalized;
    [self.delegate browserView:self
             didLogMessage:[NSString stringWithFormat:@"Queueing %@", normalized]];
    [self ensureBrowserCreated];
    return;
  }

  CefRefPtr<CefFrame> frame = _browser->GetMainFrame();
  if (!frame) {
    [self.delegate browserView:self
             didLogMessage:[NSString stringWithFormat:@"Deferring navigation until main frame is ready for %@",
                                                    normalized]];
    return;
  }

  [self.delegate browserView:self
           didLogMessage:[NSString stringWithFormat:@"Loading %@", normalized]];
  frame->LoadURL(AHUTF8String(normalized));
}

- (void)goBack {
  if (_browser && _browser->CanGoBack()) {
    _browser->GoBack();
  }
}

- (void)goForward {
  if (_browser && _browser->CanGoForward()) {
    _browser->GoForward();
  }
}

- (void)reloadPage {
  if (_browser) {
    _browser->Reload();
  }
}

- (void)stopLoading {
  if (_browser) {
    _browser->StopLoad();
  }
}

- (void)evaluateJavaScript:(NSString*)script
                completion:(AHChromiumEvaluationCompletion)completion {
  if (!_browser) {
    if (completion) {
      completion(nil, @"Chromium browser is not ready yet.");
    }
    return;
  }

  NSString* wrappedScript = [NSString
      stringWithFormat:
          @"(() => { try { const __agenthubValue = (() => { %@ })(); "
           "return JSON.stringify({ ok: true, value: __agenthubValue }); } "
           "catch (error) { return JSON.stringify({ ok: false, error: "
           "String(error) }); } })()",
          script];

  CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
  params->SetString("expression", AHUTF8String(wrappedScript));
  params->SetBool("awaitPromise", true);
  params->SetBool("returnByValue", true);
  params->SetBool("userGesture", true);

  CefRefPtr<CefBrowserHost> host = _browser->GetHost();
  int messageID =
      host ? host->ExecuteDevToolsMethod(0, "Runtime.evaluate", params) : 0;
  if (messageID == 0) {
    if (completion) {
      completion(nil, @"Failed to send a DevTools runtime evaluation request.");
    }
    return;
  }

  if (completion) {
    _pendingCompletions[@(messageID)] = [completion copy];
  }
}

- (void)capturePNGSnapshot:(AHChromiumSnapshotCompletion)completion {
  if (!completion) {
    return;
  }

  NSRect bounds = self.bounds;
  if (NSWidth(bounds) < 2 || NSHeight(bounds) < 2) {
    completion(nil, @"Browser surface is too small to capture.");
    return;
  }

  NSBitmapImageRep* bitmap = [self bitmapImageRepForCachingDisplayInRect:bounds];
  if (!bitmap) {
    completion(nil, @"Failed to allocate a snapshot buffer.");
    return;
  }

  [self cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
  NSData* pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  if (!pngData) {
    completion(nil, @"Failed to encode the browser snapshot.");
    return;
  }

  completion(pngData, nil);
}

- (void)ensureBrowserCreated {
  if (_browser || _browserCreationRequested || self.window == nil) {
    return;
  }

  if (self.bounds.size.width < 2 || self.bounds.size.height < 2) {
    return;
  }

  NSString* initializationError = nil;
  if (![[AHChromiumRuntime sharedRuntime] ensureInitialized:&initializationError]) {
    _lastErrorMessage = initializationError;
    _runtimeReady = NO;
    [self.delegate browserViewDidUpdateState:self];
    [self.delegate browserView:self
         didFailWithErrorMessage:initializationError ?: @"Failed to initialize Chromium."];
    return;
  }

  _runtimeReady = YES;
  [self.delegate browserViewDidUpdateState:self];
  if (![[AHChromiumRuntime sharedRuntime] isContextInitialized]) {
    [self.delegate browserView:self
             didLogMessage:@"Waiting for CEF browser context initialization."];
    return;
  }

  _browserCreationRequested = YES;
  if (!_client) {
    _client = new AHChromiumClient(self);
  }
  if (!_devToolsObserver) {
    _devToolsObserver = new AHChromiumDevToolsObserver(self);
  }

  NSString* initialURLString =
      _queuedURLString.length > 0 ? _queuedURLString : @"about:blank";

  CefWindowInfo windowInfo;
  windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self),
                        CefRect(0, 0, static_cast<int>(NSWidth(self.bounds)),
                                static_cast<int>(NSHeight(self.bounds))));
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

  CefBrowserSettings browserSettings;
  [self.delegate browserView:self
           didLogMessage:[NSString stringWithFormat:@"Creating Chromium browser for %@",
                                                    initialURLString]];
  CefRefPtr<CefBrowser> browser = CefBrowserHost::CreateBrowserSync(
      windowInfo, _client, AHUTF8String(initialURLString), browserSettings,
      nullptr, CefRequestContext::GetGlobalContext());

  if (!browser) {
    _browserCreationRequested = NO;
    _lastErrorMessage = @"CEF did not create the embedded browser view.";
    [self.delegate browserViewDidUpdateState:self];
    [self.delegate browserView:self didFailWithErrorMessage:_lastErrorMessage];
    return;
  }

  [self.delegate browserView:self didLogMessage:@"CEF created browser synchronously."];
  [self didCreateBrowser:browser];
}

- (void)didCreateBrowser:(CefRefPtr<CefBrowser>)browser {
  if (_browser) {
    return;
  }

  _browser = browser;
  _browserCreationRequested = NO;
  _lastErrorMessage = nil;

  CefRefPtr<CefBrowserHost> host = _browser ? _browser->GetHost() : nullptr;
  if (host && _devToolsObserver && !_devToolsRegistration) {
    _devToolsRegistration = host->AddDevToolsMessageObserver(_devToolsObserver);
    host->NotifyMoveOrResizeStarted();
    host->SetFocus(true);
  }

  [_statePollTimer invalidate];
  _statePollTimer = [NSTimer timerWithTimeInterval:0.35
                                            target:self
                                          selector:@selector(pollBrowserState:)
                                          userInfo:nil
                                           repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:_statePollTimer forMode:NSRunLoopCommonModes];
  [self pollBrowserState:_statePollTimer];

  if (_queuedURLString.length > 0) {
    NSString* queuedURL = _queuedURLString;
    [self.delegate browserView:self
             didLogMessage:[NSString stringWithFormat:@"Loading queued URL after browser creation: %@",
                                                    queuedURL]];
    [self loadURLString:queuedURL];
  }

  [self.delegate browserView:self didLogMessage:@"Chromium browser created."];
  [self.delegate browserViewDidUpdateState:self];
}

- (void)browserWillClose:(CefRefPtr<CefBrowser>)browser {
  if (_browser && !_browser->IsSame(browser)) {
    return;
  }

  [_statePollTimer invalidate];
  _statePollTimer = nil;
  _devToolsRegistration = nullptr;
  _browser = nullptr;
  [self.delegate browserViewDidUpdateState:self];
}

- (void)didReceiveTitle:(NSString*)title {
  _pageTitle = title.length > 0 ? title : _pageTitle;
  [self.delegate browserView:self
           didLogMessage:[NSString stringWithFormat:@"Title changed to %@", _pageTitle]];
  [self.delegate browserViewDidUpdateState:self];
}

- (void)didReceiveMainFrameURL:(NSString*)urlString {
  _currentURL = urlString.length > 0 ? urlString : _currentURL;
  [self.delegate browserView:self
           didLogMessage:[NSString stringWithFormat:@"Main frame URL is now %@", _currentURL]];
  if (_queuedURLString.length > 0 && [_queuedURLString isEqualToString:_currentURL]) {
    _queuedURLString = nil;
  }
  [self.delegate browserViewDidUpdateState:self];
}

- (void)didReceiveLoadingState:(BOOL)isLoading
                    canGoBack:(BOOL)canGoBack
                 canGoForward:(BOOL)canGoForward {
  _isLoading = isLoading;
  _canGoBack = canGoBack;
  _canGoForward = canGoForward;
  [self.delegate browserView:self
           didLogMessage:[NSString stringWithFormat:@"Loading state changed: loading=%@ back=%@ forward=%@",
                                                    isLoading ? @"YES" : @"NO",
                                                    canGoBack ? @"YES" : @"NO",
                                                    canGoForward ? @"YES" : @"NO"]];
  [self.delegate browserViewDidUpdateState:self];
}

- (void)didReceiveLoadErrorForURL:(NSString*)urlString message:(NSString*)message {
  if ([urlString hasPrefix:@"about:"]) {
    return;
  }

  _lastErrorMessage = message;
  [self.delegate browserView:self didFailWithErrorMessage:message];
}

- (void)didReceiveDevToolsMessageWithID:(int)messageID
                                success:(BOOL)success
                            payloadJSON:(NSString*)payloadJSON {
  AHChromiumEvaluationCompletion completion = _pendingCompletions[@(messageID)];
  if (!completion) {
    return;
  }
  [_pendingCompletions removeObjectForKey:@(messageID)];

  NSDictionary* payload = AHJSONDictionaryFromString(payloadJSON ?: @"{}");
  if (!success) {
    NSString* errorMessage =
        payload[@"message"] ?: payload[@"error"] ?: @"DevTools method failed.";
    completion(nil, errorMessage);
    return;
  }

  NSDictionary* exceptionDetails = payload[@"exceptionDetails"];
  if (exceptionDetails != nil) {
    NSString* errorMessage = exceptionDetails[@"text"] ?: @"JavaScript execution failed.";
    completion(nil, errorMessage);
    return;
  }

  NSDictionary* result = payload[@"result"];
  NSString* resultValue = result[@"value"];
  if (resultValue.length == 0) {
    completion(nil, @"JavaScript returned an empty DevTools result.");
    return;
  }

  NSDictionary* wrappedValue = AHJSONDictionaryFromString(resultValue);
  if (![wrappedValue isKindOfClass:[NSDictionary class]]) {
    completion(resultValue, nil);
    return;
  }

  if (![wrappedValue[@"ok"] boolValue]) {
    completion(nil, wrappedValue[@"error"] ?: @"JavaScript evaluation failed.");
    return;
  }

  completion(AHJSONStringFromObject(wrappedValue[@"value"]), nil);
}

- (void)pollBrowserState:(NSTimer*)timer {
  if (!_browser || !_browser->IsValid()) {
    return;
  }

  CefRefPtr<CefFrame> mainFrame = _browser->GetMainFrame();
  if (mainFrame) {
    NSString* frameURL = AHNSStringFromCefString(mainFrame->GetURL());
    if (frameURL.length > 0) {
      _currentURL = frameURL;
    }
  }

  _isLoading = _browser->IsLoading();
  _canGoBack = _browser->CanGoBack();
  _canGoForward = _browser->CanGoForward();
  [self.delegate browserViewDidUpdateState:self];
}

@end
