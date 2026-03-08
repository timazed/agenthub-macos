#import "ChromiumApplication.h"

#import <AppKit/AppKit.h>

#include "include/cef_application_mac.h"

@interface AHChromiumApplication : NSApplication <CefAppProtocol> {
 @private
  BOOL handlingSendEvent_;
}
@end

@implementation AHChromiumApplication

- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent scopedSendingEvent;
  [super sendEvent:event];
}

@end

extern "C" void AHChromiumInstallApplicationClass(void) {
  [AHChromiumApplication sharedApplication];
}
