#import "include/TBPrivate.h"
#import <dlfcn.h>
#import <objc/message.h>

typedef void (*TBPPresenceFn)(NSString *identifier, BOOL present);
typedef void (*TBPCloseBoxFn)(BOOL show);

static void *TBPDFRHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    });
    return handle;
}

BOOL TBPIsAvailable(void) {
    if (TBPDFRHandle() == NULL) {
        return NO;
    }
    return [NSTouchBarItem respondsToSelector:NSSelectorFromString(@"addSystemTrayItem:")];
}

void TBPSetControlStripPresence(NSString *identifier, BOOL present) {
    void *handle = TBPDFRHandle();
    if (handle == NULL) {
        return;
    }
    TBPPresenceFn fn = (TBPPresenceFn)dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier");
    if (fn != NULL) {
        fn(identifier, present);
    }
}

void TBPSetShowsCloseBoxWhenFrontMost(BOOL show) {
    void *handle = TBPDFRHandle();
    if (handle == NULL) {
        return;
    }
    TBPCloseBoxFn fn = (TBPCloseBoxFn)dlsym(handle, "DFRSystemModalShowCloseBoxWhenFrontMost");
    if (fn != NULL) {
        fn(show);
    }
}

void TBPAddSystemTrayItem(NSTouchBarItem *item) {
    SEL sel = NSSelectorFromString(@"addSystemTrayItem:");
    if ([NSTouchBarItem respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBarItem class], sel, item);
    }
}

void TBPRemoveSystemTrayItem(NSTouchBarItem *item) {
    SEL sel = NSSelectorFromString(@"removeSystemTrayItem:");
    if ([NSTouchBarItem respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBarItem class], sel, item);
    }
}

void TBPPresentSystemModal(NSTouchBar *touchBar, NSString *systemTrayItemIdentifier) {
    SEL sel = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if ([NSTouchBar respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)([NSTouchBar class], sel, touchBar, systemTrayItemIdentifier);
        return;
    }
    // Fallback for older SPI naming (pre-10.14).
    SEL old = NSSelectorFromString(@"presentSystemModalFunctionBar:systemTrayItemIdentifier:");
    if ([NSTouchBar respondsToSelector:old]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)([NSTouchBar class], old, touchBar, systemTrayItemIdentifier);
    }
}

void TBPDismissSystemModal(NSTouchBar *touchBar) {
    SEL sel = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if ([NSTouchBar respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBar class], sel, touchBar);
        return;
    }
    SEL old = NSSelectorFromString(@"dismissSystemModalFunctionBar:");
    if ([NSTouchBar respondsToSelector:old]) {
        ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBar class], old, touchBar);
    }
}

void TBPMinimizeSystemModal(NSTouchBar *touchBar) {
    SEL sel = NSSelectorFromString(@"minimizeSystemModalTouchBar:");
    if ([NSTouchBar respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)([NSTouchBar class], sel, touchBar);
    }
}
