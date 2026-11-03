//
// TGDevShowcase.h - Test harness providing placeholder fixtures for all TDLib message types.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#if TG_DEV

#define kDevChatId -7777777LL
#define kDevDurovChatId -7777778LL
#define kDevBotChatId -7777779LL

@interface TGDevShowcase : NSObject

+ (BOOL)isDevChatId:(int64_t)chatId;
+ (NSDictionary *)devChatInfo;
+ (NSArray *)allShowcaseChats;
+ (NSArray *)allShowcaseContacts;
+ (NSArray *)messagesForChatId:(int64_t)chatId;
+ (NSArray *)allShowcaseMessages;
+ (NSArray *)pavelDurovMessages;
+ (NSArray *)devBotMessages;
/// Dev Bot's reply keyboard; nil for any other chat.
+ (NSDictionary *)replyKeyboardForChatId:(int64_t)chatId;
+ (NSString *)devStickerPath;
+ (NSString *)devWebMPath;
+ (UIImage *)imageForPhotoId:(int64_t)photoId;
+ (UIImage *)avatarForUserId:(int64_t)userId;
+ (UIImage *)trackArtwork;

@end

#define TGIsDevChat(chatId) [TGDevShowcase isDevChatId:(chatId)]
#else
#define TGIsDevChat(chatId) NO
#endif
