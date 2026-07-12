#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges to the private DFRFoundation framework + private NSTouchBar SPI that
/// Pock/MTMR-style apps use to put a persistent item in the Control Strip.
/// Everything is resolved at runtime (dlopen/dlsym + selectors), so the app
/// links only against public frameworks and degrades gracefully on Macs
/// without a Touch Bar.

/// YES when the private SPI required for the Control Strip item is present.
BOOL TBPIsAvailable(void);

/// Show/hide a previously added system tray item in the Control Strip.
void TBPSetControlStripPresence(NSString *identifier, BOOL present);

/// Ask the system to render its own close box while a system-modal bar is up.
void TBPSetShowsCloseBoxWhenFrontMost(BOOL show);

/// Add/remove an NSTouchBarItem to the system tray (Control Strip area).
void TBPAddSystemTrayItem(NSTouchBarItem *item);
void TBPRemoveSystemTrayItem(NSTouchBarItem *item);

/// Present/dismiss a full-width system modal touch bar.
void TBPPresentSystemModal(NSTouchBar *touchBar, NSString *systemTrayItemIdentifier);
void TBPDismissSystemModal(NSTouchBar *touchBar);
void TBPMinimizeSystemModal(NSTouchBar *touchBar);

NS_ASSUME_NONNULL_END
