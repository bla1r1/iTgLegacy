//
// TGFlattenedMessage.hpp - one message as a POD, parsed straight from TDLib
// JSON.
//
// A message reaches the app as a TDLib object of thirty-five keys nested four
// deep, becomes an NSDictionary tree of that shape, and is then flattened
// into a second dictionary of forty-odd keys - every scalar in it a separate
// NSNumber on the heap. That is around 2 KB and fifty allocations per
// message, and an open chat holds fifty of them.
//
// This is the same scalars in 88 bytes with no allocation and no pointers:
// trivially copyable, contiguous in a std::vector, and readable without
// touching the Objective-C runtime. Parsing comes off the JSON directly
// (TGJsonReader), so the dictionary tree is never needed to get at them.
//
// Text, captions and entities are deliberately absent: they are variable
// length and the UI needs them as NSStrings anyway. This is the scalar half -
// ids, dates, flags, media geometry - which is what sorting, de-duplication,
// bounds and layout read.
//
#ifndef TGFLATTENEDMESSAGE_HPP
#define TGFLATTENEDMESSAGE_HPP

#include "TGJsonReader.hpp"
#include <cstdint>
#include <cstring>

enum TGMessageKind : uint8_t {
	TGMessageKindUnknown = 0,
	TGMessageKindText,
	TGMessageKindPhoto,
	TGMessageKindVideo,
	TGMessageKindAnimation,
	TGMessageKindSticker,
	TGMessageKindVoiceNote,
	TGMessageKindVideoNote,
	TGMessageKindAudio,
	TGMessageKindDocument,
	TGMessageKindLocation,
	TGMessageKindVenue,
	TGMessageKindContact,
	TGMessageKindPoll,
	TGMessageKindCall,
	TGMessageKindService
};

enum TGMessageFlag : uint16_t {
	TGMessageFlagOutgoing   = 1 << 0,
	TGMessageFlagEdited     = 1 << 1,
	TGMessageFlagService    = 1 << 2,
	TGMessageFlagFailed     = 1 << 3,
	TGMessageFlagUnplayed   = 1 << 4,  // voice not listened / round not viewed
	TGMessageFlagHasCaption = 1 << 5,
	TGMessageFlagMissedCall = 1 << 6,
	TGMessageFlagLiveLocation = 1 << 7
};

struct TGFlattenedMessage {
	int64_t  messageId;
	int64_t  chatId;
	int64_t  senderId;
	int64_t  replyToMessageId;
	int64_t  albumId;
	int32_t  date;
	int32_t  editDate;
	int32_t  photoFileId;
	int32_t  docFileId;
	int32_t  thumbFileId;
	int32_t  docSize;
	int32_t  duration;
	int16_t  mediaWidth;
	int16_t  mediaHeight;
	uint16_t flags;
	uint8_t  kind;
	uint8_t  reserved;
	float    latitude;
	float    longitude;

	bool has(TGMessageFlag flag) const { return (flags & flag) != 0; }
	void set(TGMessageFlag flag, bool on) {
		if (on) flags |= flag; else flags = (uint16_t)(flags & ~flag);
	}
};

/// A message of one byte per field would still have to be addressable, so the
/// ceiling is what matters: the roadmap's budget is 128 bytes.
static_assert(sizeof(TGFlattenedMessage) <= 128,
			  "TGFlattenedMessage must stay inside its 128-byte budget");

inline void TGFlattenedMessageClear(TGFlattenedMessage &out) {
	std::memset(&out, 0, sizeof(out));
}

/// Maps TDLib's content "@type" onto the kind the UI branches on.
inline uint8_t TGMessageKindFromTypeName(const char *ctype) {
	if (!ctype || !*ctype)
		return TGMessageKindUnknown;
	struct Entry { const char *name; uint8_t kind; };
	static const Entry kTable[] = {
		{ "messageText",       TGMessageKindText      },
		{ "messagePhoto",      TGMessageKindPhoto     },
		{ "messageVideo",      TGMessageKindVideo     },
		{ "messageAnimation",  TGMessageKindAnimation },
		{ "messageSticker",    TGMessageKindSticker   },
		{ "messageVoiceNote",  TGMessageKindVoiceNote },
		{ "messageVideoNote",  TGMessageKindVideoNote },
		{ "messageAudio",      TGMessageKindAudio     },
		{ "messageDocument",   TGMessageKindDocument  },
		{ "messageLocation",   TGMessageKindLocation  },
		{ "messageVenue",      TGMessageKindVenue     },
		{ "messageContact",    TGMessageKindContact   },
		{ "messagePoll",       TGMessageKindPoll      },
		{ "messageCall",       TGMessageKindCall      },
	};
	for (size_t i = 0; i < sizeof(kTable) / sizeof(kTable[0]); i++) {
		if (std::strcmp(ctype, kTable[i].name) == 0)
			return kTable[i].kind;
	}
	// Everything else TDLib calls a message is one of the ~60 service
	// notices - somebody joined, the photo changed, the call ended.
	return TGMessageKindService;
}

/// Fills `out` from one TDLib `message` object. Returns false when the value
/// is not a message at all.
inline bool TGFlattenedMessageParse(const TGJsonVal &m, TGFlattenedMessage &out) {
	TGFlattenedMessageClear(out);
	if (!m.is_obj())
		return false;

	out.messageId = m.get_int64("id");
	out.chatId    = m.get_int64("chat_id");
	out.date      = (int32_t)m.get_int64("date");
	out.editDate  = (int32_t)m.get_int64("edit_date");
	out.senderId  = m.get("sender_id").get_int64("user_id");
	out.albumId   = m.get_int64("media_album_id");

	// TDLib moved this from a bare id to a messageReplyToMessage object;
	// both spellings are still in the wild.
	out.replyToMessageId = m.get_int64("reply_to_message_id");
	if (!out.replyToMessageId)
		out.replyToMessageId = m.get("reply_to").get_int64("message_id");

	out.set(TGMessageFlagOutgoing, m.get_bool("is_outgoing"));
	out.set(TGMessageFlagEdited, out.editDate > 0);
	out.set(TGMessageFlagFailed,
			std::strcmp(m.get("sending_state").get_str("@type"),
						"messageSendingStateFailed") == 0);

	TGJsonVal content = m.get("content");
	const char *ctype = content.get_str("@type");
	out.kind = TGMessageKindFromTypeName(ctype);
	out.set(TGMessageFlagService, out.kind == TGMessageKindService);
	out.set(TGMessageFlagHasCaption,
			content.get("caption").get("text").str_len() > 0);

	switch (out.kind) {
		case TGMessageKindPhoto: {
			// The sizes come smallest first; the last one is the full frame.
			TGJsonVal sizes = content.get("photo").get("sizes");
			size_t count = sizes.arr_size();
			if (count) {
				TGJsonVal biggest = sizes.arr_at(count - 1);
				out.photoFileId = biggest.get("photo").get_int32("id");
				out.mediaWidth  = (int16_t)biggest.get_int32("width");
				out.mediaHeight = (int16_t)biggest.get_int32("height");
				out.thumbFileId = sizes.arr_at(0).get("photo").get_int32("id");
			}
			break;
		}
		case TGMessageKindVideo: {
			TGJsonVal video = content.get("video");
			out.docFileId   = video.get("video").get_int32("id");
			out.docSize     = video.get("video").get("size").as_int32();
			out.duration    = video.get_int32("duration");
			out.mediaWidth  = (int16_t)video.get_int32("width");
			out.mediaHeight = (int16_t)video.get_int32("height");
			out.thumbFileId = video.get("thumbnail").get("file").get_int32("id");
			break;
		}
		case TGMessageKindAnimation: {
			TGJsonVal animation = content.get("animation");
			out.docFileId   = animation.get("animation").get_int32("id");
			out.duration    = animation.get_int32("duration");
			out.mediaWidth  = (int16_t)animation.get_int32("width");
			out.mediaHeight = (int16_t)animation.get_int32("height");
			out.thumbFileId = animation.get("thumbnail").get("file").get_int32("id");
			break;
		}
		case TGMessageKindSticker: {
			TGJsonVal sticker = content.get("sticker");
			out.docFileId   = sticker.get("sticker").get_int32("id");
			out.mediaWidth  = (int16_t)sticker.get_int32("width");
			out.mediaHeight = (int16_t)sticker.get_int32("height");
			out.thumbFileId = sticker.get("thumbnail").get("file").get_int32("id");
			break;
		}
		case TGMessageKindVoiceNote: {
			TGJsonVal voice = content.get("voice_note");
			out.docFileId = voice.get("voice").get_int32("id");
			out.duration  = voice.get_int32("duration");
			out.set(TGMessageFlagUnplayed, !content.get_bool("is_listened"));
			break;
		}
		case TGMessageKindVideoNote: {
			TGJsonVal note = content.get("video_note");
			out.docFileId   = note.get("video").get_int32("id");
			out.duration    = note.get_int32("duration");
			out.mediaWidth  = (int16_t)note.get_int32("length");
			out.mediaHeight = out.mediaWidth;
			out.thumbFileId = note.get("thumbnail").get("file").get_int32("id");
			out.set(TGMessageFlagUnplayed, !content.get_bool("is_viewed"));
			break;
		}
		case TGMessageKindAudio: {
			TGJsonVal audio = content.get("audio");
			out.docFileId   = audio.get("audio").get_int32("id");
			out.duration    = audio.get_int32("duration");
			out.thumbFileId = audio.get("album_cover_thumbnail")
								   .get("file").get_int32("id");
			break;
		}
		case TGMessageKindDocument: {
			TGJsonVal document = content.get("document");
			out.docFileId   = document.get("document").get_int32("id");
			out.docSize     = document.get("document").get("size").as_int32();
			out.thumbFileId = document.get("thumbnail").get("file").get_int32("id");
			break;
		}
		case TGMessageKindLocation: {
			TGJsonVal location = content.get("location");
			out.latitude  = (float)location.get("latitude").as_double();
			out.longitude = (float)location.get("longitude").as_double();
			out.set(TGMessageFlagLiveLocation, content.get_int64("live_period") > 0);
			break;
		}
		case TGMessageKindVenue: {
			TGJsonVal location = content.get("venue").get("location");
			out.latitude  = (float)location.get("latitude").as_double();
			out.longitude = (float)location.get("longitude").as_double();
			break;
		}
		case TGMessageKindCall: {
			out.duration = content.get_int32("duration");
			const char *reason = content.get("discard_reason").get_str("@type");
			out.set(TGMessageFlagMissedCall,
					std::strcmp(reason, "callDiscardReasonMissed") == 0 ||
					std::strcmp(reason, "callDiscardReasonDeclined") == 0);
			break;
		}
		default:
			break;
	}
	return true;
}

/// Parses one TDLib message straight from its JSON text.
inline bool TGFlattenedMessageParseJson(const char *utf8, size_t len,
										TGFlattenedMessage &out) {
	TGJsonDoc doc(utf8, len);
	if (!doc.is_valid()) {
		TGFlattenedMessageClear(out);
		return false;
	}
	return TGFlattenedMessageParse(doc.root(), out);
}

#endif // TGFLATTENEDMESSAGE_HPP
