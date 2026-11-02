//
// TGStylePalette.h
// Fixed non-theme palette roles and decorative tile hues.
//
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - colour that is not the theme's

UIColor *TGColourLink(void);
UIColor *TGColourCodeBackground(void);
UIColor *TGColourCodeBlockBackground(void);
/// Telegram's colour for a sender's name, which no theme overrides.
UIColor *TGColourPeerName(int64_t colourId, BOOL dark);

#pragma mark - icon tile hues

UIColor *TGIconTileViolet(void);
UIColor *TGIconTilePurple(void);
UIColor *TGIconTileOrchid(void);
UIColor *TGIconTileSky(void);
UIColor *TGIconTileAzure(void);
UIColor *TGIconTileCyan(void);
UIColor *TGIconTileGreen(void);
UIColor *TGIconTileAmber(void);
UIColor *TGIconTileGold(void);
UIColor *TGIconTileCoral(void);
UIColor *TGIconTileRed(void);
UIColor *TGIconTileGrey(void);
UIColor *TGIconTileSlate(void);

#ifdef __cplusplus
}
#endif
