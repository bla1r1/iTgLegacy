//
// TGClient+GroupCalls.h - group calls and video chats on the wire.
//
// A group call is one record Telegram keeps updating (groupCall), a set of
// participants that arrive as updates, and the requests a call screen sends
// about them. A video chat is the same call bound to a chat; the setup screen
// creates it, schedules it, and manages recordings, invite links and RTMP.
//
// The screens read one flat dictionary per call, participant, message and
// stream. Flattening lives in the implementation so the call screen, the
// participant list and the message bar all read the same keys.
//
#import "TGClient+Base.h"

/// Posted on the main queue when updateGroupCall changes a call.
/// userInfo carries TGGroupCallIdKey and TGGroupCallValueKey.
FOUNDATION_EXPORT NSString * const TGGroupCallChangedNotification;
/// Posted when one participant changes or leaves (TGGroupCallValueKey is the
/// participant; it is absent when the participant list was removed).
FOUNDATION_EXPORT NSString * const TGGroupCallParticipantsChangedNotification;
/// Posted when a call message is added, deleted or fails to send.
FOUNDATION_EXPORT NSString * const TGGroupCallMessagesChangedNotification;

FOUNDATION_EXPORT NSString * const TGGroupCallIdKey;
FOUNDATION_EXPORT NSString * const TGGroupCallValueKey;
FOUNDATION_EXPORT NSString * const TGGroupCallErrorKey;

/// The join parameters TDLib takes for joinGroupCall and joinVideoChat.
/// A nil payload is an empty one; -muted answers is_muted.
FOUNDATION_EXPORT NSDictionary *TGGroupCallJoinParameters(int32_t audioSourceId,
		NSString *payload, BOOL muted, BOOL videoEnabled);

/// An inputGroupCall for the calls createGroupCall makes. Chat-bound video
/// chats are named by id alone; TDLib uses this object for the chatless ones.
FOUNDATION_EXPORT NSDictionary *TGGroupCallInput(int32_t groupCallId,
		int64_t accessHash);

@interface TGClient (GroupCalls)

#pragma mark - calls and participation

/// getGroupCall. The answer is flattened: "callId", "title", "participantCount",
/// "isActive", "isJoined", "isVideoChat", "isRtmpStream", "scheduledStartDate",
/// "duration", the can_* rights and the two self-video flags.
- (void)groupCall:(int32_t)groupCallId
	   completion:(void (^)(NSDictionary *call, NSString *error))completion;

/// createVideoChat. `startDate` 0 starts it now; TDLib requires 10 seconds to
/// 8 days otherwise. A channel or supergroup with can_manage_video_chats is
/// the only place Telegram accepts it.
- (void)createVideoChatInChat:(int64_t)chatId
						title:(NSString *)title
					startDate:(int32_t)startDate
					   isRtmp:(BOOL)isRtmp
				   completion:(void (^)(int32_t groupCallId, NSString *error))completion;

/// createGroupCall, for a call that is not bound to a chat. Answers the id
/// and the join payload; the payload is what tgcalls would carry.
- (void)createGroupCallWithParameters:(NSDictionary *)parameters
						   completion:(void (^)(NSDictionary *info, NSString *error))completion;

/// joinGroupCall for a chatless call, or joinVideoChat for a video chat.
/// `participant` is a MessageSender or nil to join as self.
- (void)joinGroupCallWithInput:(NSDictionary *)input
					parameters:(NSDictionary *)parameters
					completion:(void (^)(NSDictionary *info, NSString *error))completion;
- (void)joinVideoChat:(int32_t)groupCallId
		  participant:(NSDictionary *)participant
		   parameters:(NSDictionary *)parameters
		   inviteHash:(NSString *)inviteHash
		   completion:(void (^)(NSString *payload, NSString *error))completion;

- (void)leaveGroupCall:(int32_t)groupCallId
			completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)endGroupCall:(int32_t)groupCallId
		  completion:(void (^)(BOOL ok, NSString *error))completion;

/// startScheduledVideoChat. Also clears Telegram's scheduled state, so the
/// call screen refreshes the record afterwards.
- (void)startScheduledVideoChat:(int32_t)groupCallId
					 completion:(void (^)(BOOL ok, NSString *error))completion;

/// getGroupCallParticipants for a chatless call that is not joined.
/// Answers "total" and "senders" (MessageSender dictionaries).
- (void)groupCallParticipantsWithInput:(NSDictionary *)input
								 limit:(NSInteger)limit
							completion:(void (^)(NSDictionary *answer, NSString *error))completion;

/// loadGroupCallParticipants. The rows arrive through updates; `completion`
/// says only whether Telegram accepted the request.
- (void)loadGroupCallParticipants:(int32_t)groupCallId
							limit:(NSInteger)limit
					   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - participants

- (void)toggleGroupCallParticipant:(NSDictionary *)participant
							inCall:(int32_t)groupCallId
							isMuted:(BOOL)muted
						completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setGroupCallParticipant:(NSDictionary *)participant
						 inCall:(int32_t)groupCallId
					volumeLevel:(NSInteger)volumeLevel
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleGroupCallParticipant:(NSDictionary *)participant
							inCall:(int32_t)groupCallId
					  isHandRaised:(BOOL)raised
						completion:(void (^)(BOOL ok, NSString *error))completion;

/// setGroupCallParticipantIsSpeaking. `audioSource` 0 means this account;
/// the answer names the participant when Telegram found one, nil otherwise.
- (void)setGroupCallParticipantSpeaking:(int32_t)audioSource
								 inCall:(int32_t)groupCallId
							  isSpeaking:(BOOL)speaking
							  completion:(void (^)(NSDictionary *participant, NSString *error))completion;

- (void)inviteGroupCallParticipant:(int64_t)userId
							toCall:(int32_t)groupCallId
							isVideo:(BOOL)isVideo
						 completion:(void (^)(NSDictionary *answer, NSString *error))completion;

- (void)inviteVideoChatParticipants:(NSArray *)userIds
							 toCall:(int32_t)groupCallId
						 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)banGroupCallParticipants:(NSArray *)userIds
						  inCall:(int32_t)groupCallId
					  completion:(void (^)(BOOL ok, NSString *error))completion;

/// declineGroupCallInvitation, named by the service message it came with.
- (void)declineGroupCallInvitationInChat:(int64_t)chatId
							   messageId:(int64_t)messageId
							  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - the call's own settings

- (void)setVideoChatTitle:(NSString *)title
				   inCall:(int32_t)groupCallId
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleVideoChatMuteNewParticipants:(int32_t)groupCallId
									muted:(BOOL)muted
							   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleGroupCallMessagesAllowed:(int32_t)groupCallId
							   allowed:(BOOL)allowed
							completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleVideoChatStartNotification:(int32_t)groupCallId
								   enabled:(BOOL)enabled
								completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleGroupCallMyVideoEnabled:(int32_t)groupCallId
							  enabled:(BOOL)enabled
						   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleGroupCallMyVideoPaused:(int32_t)groupCallId
							  paused:(BOOL)paused
						  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - recording and screen sharing

- (void)startGroupCallRecording:(int32_t)groupCallId
						  title:(NSString *)title
					 recordVideo:(BOOL)recordVideo
					   portrait:(BOOL)portrait
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)endGroupCallRecording:(int32_t)groupCallId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// startGroupCallScreenSharing takes the payload tgcalls handed back at join
/// time and the audio source it allocated. There is no media engine here, so
/// the screen passes what it has and shows Telegram's answer.
- (void)startGroupCallScreenSharing:(int32_t)groupCallId
					 audioSourceId:(int32_t)audioSourceId
						   payload:(NSString *)payload
						completion:(void (^)(NSString *answer, NSString *error))completion;

- (void)toggleGroupCallScreenSharingPaused:(int32_t)groupCallId
									paused:(BOOL)paused
								completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)endGroupCallScreenSharing:(int32_t)groupCallId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - invite links and RTMP

- (void)videoChatInviteLink:(int32_t)groupCallId
			 canSelfUnmute:(BOOL)canSelfUnmute
				completion:(void (^)(NSString *link, NSString *error))completion;

- (void)revokeGroupCallInviteLink:(int32_t)groupCallId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// getVideoChatRtmpUrl / replaceVideoChatRtmpUrl. Both answer "url" and
/// "streamKey"; the chat is the name because the RTMP half exists before a
/// call does.
- (void)videoChatRtmpUrlForChat:(int64_t)chatId
					 completion:(void (^)(NSDictionary *answer, NSString *error))completion;
- (void)replaceVideoChatRtmpUrlForChat:(int64_t)chatId
							completion:(void (^)(NSDictionary *answer, NSString *error))completion;

#pragma mark - who a video chat is joined as

/// getVideoChatAvailableParticipants. Answers "total" and "senders", the
/// MessageSender records Telegram accepts for this chat.
- (void)videoChatAvailableParticipantsForChat:(int64_t)chatId
								   completion:(void (^)(NSDictionary *answer, NSString *error))completion;

- (void)setVideoChatDefaultParticipant:(NSDictionary *)participant
							   forChat:(int64_t)chatId
							completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - messages in a call

/// sendGroupCallMessage. The message itself arrives as updateGroupCallMessage
/// when Telegram accepts it; the completion only reports acceptance.
- (void)sendGroupCallMessage:(NSString *)text
					  inCall:(int32_t)groupCallId
			   paidStarCount:(int64_t)paidStarCount
				  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteGroupCallMessages:(NSArray *)messageIds
						 inCall:(int32_t)groupCallId
					 reportSpam:(BOOL)reportSpam
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteGroupCallMessagesBySender:(NSDictionary *)sender
								 inCall:(int32_t)groupCallId
							 reportSpam:(BOOL)reportSpam
							 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - streams and the data channel

/// getGroupCallStreams. Answers "streams", one dictionary per channel:
/// "channelId", "scale" and "timeOffset".
- (void)groupCallStreams:(int32_t)groupCallId
			  completion:(void (^)(NSArray *streams, NSString *error))completion;

/// getGroupCallStreamSegment. `quality` is "thumbnail", "medium", "full" or
/// nil for the worst available. The answer is the file TDLib generated.
- (void)groupCallStreamSegment:(int32_t)groupCallId
					timeOffset:(int64_t)timeOffset
						 scale:(NSInteger)scale
					 channelId:(NSInteger)channelId
					   quality:(NSString *)quality
					completion:(void (^)(NSData *data, NSString *error))completion;

/// encryptGroupCallData / decryptGroupCallData. `channel` is "main" or
/// "screenSharing"; nil means main (and, for decrypt, unknown).
- (void)encryptGroupCallData:(NSData *)data
					  inCall:(int32_t)groupCallId
					 channel:(NSString *)channel
		 unencryptedPrefixSize:(NSInteger)prefixSize
				  completion:(void (^)(NSData *encrypted, NSString *error))completion;

- (void)decryptGroupCallData:(NSData *)data
			  fromParticipant:(NSDictionary *)participant
					  inCall:(int32_t)groupCallId
					 channel:(NSString *)channel
				  completion:(void (^)(NSData *decrypted, NSString *error))completion;

#pragma mark - state the screens read

/// The last flattened call updateGroupCall / getGroupCall left, or nil.
- (NSDictionary *)groupCallSnapshot:(int32_t)groupCallId;
/// Participants in the order Telegram gave (highest order first), or empty.
- (NSArray *)groupCallParticipantSnapshot:(int32_t)groupCallId;
/// Call messages, oldest first. Empty when none arrived.
- (NSArray *)groupCallMessageSnapshot:(int32_t)groupCallId;

/// The participant row for this account in a call, or nil.
- (NSDictionary *)currentGroupCallParticipant:(int32_t)groupCallId;

@end

// vim:ft=objc
