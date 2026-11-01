#import "TGProfileViewController+Tier2.h"
#import "TGProfileViewControllerInternal.h"
#import "TGDMTopicsViewController.h"
#import "TGDiceViewController.h"
#import "TGEmojiStatusViewController.h"
#import "TGProfileAudioViewController.h"

@implementation TGProfileViewController (Tier2)

- (NSArray *)tier2MoreItems {
	NSMutableArray *items = [NSMutableArray array];
	BOOL own = self.userId &&
			self.userId == [[TGClient shared].me[@"id"] longLongValue];
	if (self.userId){
		[items addObject:@{@"title" : @"Emoji Status", @"icon" : @"star"}];
		[items addObject:@{@"title" : own ? @"Profile Audio" : @"Their Profile Audio",
						   @"icon" : @"music"}];
	} else {
		[items addObject:@{@"title" : @"Chat Emoji Status", @"icon" : @"star"}];
		[items addObject:@{@"title" : @"Direct Messages", @"icon" : @"chat"}];
		[items addObject:@{@"title" : @"Stake Dice", @"icon" : @"star"}];
	}
	return items;
}

- (BOOL)runTier2Action:(NSString *)title {
	if ([title isEqualToString:@"Emoji Status"] ||
		[title isEqualToString:@"Chat Emoji Status"]){
		TGEmojiStatusViewController *status =
				[[TGEmojiStatusViewController alloc] init];
		if ([title isEqualToString:@"Chat Emoji Status"]){
			status.target = TGEmojiStatusTargetChat;
			status.chatId = self.chatId;
			status.subjectTitle = self.name.length ? self.name : @"Chat Emoji Status";
		} else {
			BOOL own = self.userId == [[TGClient shared].me[@"id"] longLongValue];
			status.target = own ? TGEmojiStatusTargetSelf : TGEmojiStatusTargetUser;
			status.userId = self.userId;
			status.subjectTitle = self.name.length ? self.name : @"Emoji Status";
		}
		status.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:status animated:YES];
		return YES;
	}
	if ([title isEqualToString:@"Profile Audio"] ||
		[title isEqualToString:@"Their Profile Audio"]){
		TGProfileAudioViewController *audio =
				[[TGProfileAudioViewController alloc] init];
		audio.userId = self.userId;
		audio.subjectTitle = self.name.length ? self.name : @"Profile Audio";
		audio.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:audio animated:YES];
		return YES;
	}
	if ([title isEqualToString:@"Direct Messages"]){
		TGDMTopicsViewController *topics = [[TGDMTopicsViewController alloc] init];
		topics.chatId = self.chatId;
		topics.chatTitle = self.name;
		topics.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:topics animated:YES];
		return YES;
	}
	if ([title isEqualToString:@"Stake Dice"]){
		TGDiceViewController *dice = [[TGDiceViewController alloc] init];
		dice.chatId = self.chatId;
		dice.chatTitle = self.name;
		dice.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:dice animated:YES];
		return YES;
	}
	return NO;
}

@end
