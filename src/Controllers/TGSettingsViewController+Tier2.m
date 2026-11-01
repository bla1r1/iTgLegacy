//
// TGSettingsViewController+Tier2.m - the Settings rows added after the root
// page was first drawn: Telegram Business, the web proxy carrier, the
// communities/AI hub, and the profile extras.
//
// The rows live in a category so the root list gains calls, not branches:
// a later screen that wants one of them can ask for the same row too.
//
#import "TGSettingsViewController+Tier2.h"
#import "TGSettingsViewControllerInternal.h"
#import "TGBusinessViewController.h"
#import "TGWebProxyCarrierViewController.h"
#import "TGTier2HubViewController.h"
#import "TGEmojiStatusViewController.h"
#import "TGProfileAudioViewController.h"
#import "TGTextStylesViewController.h"
#import "TGDiceViewController.h"

@implementation TGSettingsViewController (Tier2)

- (NSDictionary *)tier2BusinessRow {
	__weak typeof(self) weakSelf = self;
	return TGIconRow(@"Telegram Business", @"briefcase", TGIconTileAzure(), ^{
		TGBusinessViewController *business = [[TGBusinessViewController alloc] init];
		business.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:business animated:YES];
	});
}

- (NSDictionary *)tier2ProxyCarrierRow {
	__weak typeof(self) weakSelf = self;
	return TGIconTapRow(@"Web Proxy Carrier",
			@"Carrier messages and errors",
			@"data", TGIconTileSlate(), ^{
		TGWebProxyCarrierViewController *carrier =
				[[TGWebProxyCarrierViewController alloc] init];
		carrier.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:carrier animated:YES];
	});
}

- (NSDictionary *)tier2ToolsRow {
	__weak typeof(self) weakSelf = self;
	return TGIconRow(@"Communities and Replies", @"folder", TGIconTileViolet(), ^{
		TGTier2HubViewController *screen = [[TGTier2HubViewController alloc] init];
		screen.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:screen animated:YES];
	});
}

- (NSArray *)tier2Sections {
	__weak typeof(self) weakSelf = self;
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	return @[
		TGSection(@"Profile Extras", @"Emoji status, profile audio and text "
				@"composition styles come from Telegram; the screens show its "
				@"refusal when an account is not Premium.", @[
			TGIconRow(@"Emoji Status", @"star", TGIconTileGold(), ^{
				TGEmojiStatusViewController *status =
						[[TGEmojiStatusViewController alloc] init];
				status.target = TGEmojiStatusTargetSelf;
				status.userId = myId;
				status.subjectTitle = @"Emoji Status";
				status.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:status animated:YES];
			}),
			TGIconRow(@"Profile Audio", @"music", TGIconTileViolet(), ^{
				TGProfileAudioViewController *audio =
						[[TGProfileAudioViewController alloc] init];
				audio.userId = myId;
				audio.subjectTitle = @"Profile Audio";
				audio.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:audio animated:YES];
			}),
			TGIconTapRow(@"Text Styles", @"Composer",
						 @"edit", TGIconTileSky(), ^{
				TGTextStylesViewController *styles =
						[[TGTextStylesViewController alloc] init];
				styles.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:styles animated:YES];
			}),
			TGIconTapRow(@"Stake Dice", @"State and prize table",
						 @"star", TGIconTileAmber(), ^{
				TGDiceViewController *dice = [[TGDiceViewController alloc] init];
				dice.chatTitle = @"Stake Dice";
				dice.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:dice animated:YES];
			}),
		]),
	];
}

@end

// vim:ft=objc
