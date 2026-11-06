#import "TGEmojiData.h"
#import "TGCapabilities.h"
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import "TGStyle.h"
#import "TGMessageLayout.h"

// One string per category, separated by spaces. Listed generously, newer
// Unicode included: TGCapabilities drops whatever the device font lacks, so
// an iOS 6 phone sees the Unicode 6 set and a newer one sees more.
static NSString *const kSmileys =
	@"😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🤩 🥳 "
	@"😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 "
	@"🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 "
	@"👹 👺 🤡 💩 👻 💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾 "
	@"👋 🤚 🖐 ✋ 🖖 👌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 "
	@"✍️ 💅 🤳 💪 👂 👃 🧠 👀 👁 👅 👄 💋 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 "
	@"🙇 🤦 🤷 👮 🕵 💂 👷 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🤱 👼 🎅 🤶 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 💆 💇 "
	@"🚶 🏃 💃 🕺 👯 🧖 🧗 👫 👬 👭 💏 💑 👪 🗣 👤 👥 👣 "
	@"👓 🕶 🥽 👔 👕 👖 🧣 🧤 🧥 🧦 👗 👘 👙 👚 👛 👜 👝 🎒 👞 👟 🥾 👠 👡 👢 👑 👒 🎩 🎓 🧢 💄 💍 💼";

static NSString *const kNature =
	@"🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 "
	@"🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🦟 🦗 🕷 🕸 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 "
	@"🐋 🦈 🐊 🐅 🐆 🦓 🦍 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🐈 🐓 🦃 🦚 "
	@"🦜 🦢 🕊 🐇 🦝 🦡 🐁 🐀 🐿 🦔 🐾 🐉 🐲 🌵 🎄 🌲 🌳 🌴 🌱 🌿 ☘️ 🍀 🎍 🎋 🍃 🍂 🍁 🍄 🐚 🌾 "
	@"💐 🌷 🌹 🥀 🌺 🌸 🌼 🌻 🌞 🌝 🌛 🌜 🌚 🌕 🌖 🌗 🌘 🌑 🌒 🌓 🌔 🌙 🌎 🌍 🌏 🪐 💫 ⭐️ 🌟 ✨ "
	@"⚡️ ☄️ 💥 🔥 🌪 🌈 ☀️ 🌤 ⛅️ 🌥 ☁️ 🌦 🌧 ⛈ 🌩 🌨 ❄️ ☃️ ⛄️ 🌬 💨 💧 💦 ☔️ ☂️ 🌊 🌫";

static NSString *const kFood =
	@"🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶 🌽 🥕 🧄 🧅 🥔 🍠 🥐 "
	@"🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🥙 🧆 🌮 🌯 🥗 🥘 🥫 🍝 🍜 🍲 🍛 "
	@"🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 "
	@"🍼 ☕️ 🍵 🧃 🥤 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽 🥣 🥡 🥢 🧂";

static NSString *const kActivity =
	@"⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛷 ⛸ 🥌 "
	@"🎿 ⛷ 🏂 🏋 🤼 🤸 ⛹ 🤺 🤾 🏌 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖 🏵 🎗 🎫 🎟 🎪 "
	@"🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🪕 🎻 🎲 ♟ 🎯 🎳 🎮 🎰 🧩";

static NSString *const kTravel =
	@"🚗 🚕 🚙 🚌 🚎 🏎 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🦯 🦽 🦼 🛴 🚲 🛵 🏍 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 "
	@"🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩 💺 🛰 🚀 🛸 🚁 🛶 ⛵️ 🚤 🛥 🛳 ⛴ 🚢 ⚓️ ⛽️ 🚧 "
	@"🚦 🚥 🚏 🗺 🗿 🗽 🗼 🏰 🏯 🏟 🎡 🎢 🎠 ⛲️ ⛱ 🏖 🏝 🏜 🌋 ⛰ 🏔 🗻 🏕 ⛺️ 🏠 🏡 🏘 🏚 🏗 🏭 "
	@"🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛 ⛪️ 🕌 🕍 🛕 🕋 ⛩ 🛤 🛣 🗾 🎑 🏞 🌅 🌄 🌠 🎇 🎆 🌇 🌆 "
	@"🏙 🌃 🌌 🌉 🌁";

static NSString *const kObjects =
	@"⌚️ 📱 📲 💻 ⌨️ 🖥 🖨 🖱 🖲 🕹 🗜 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽 🎞 📞 ☎️ 📟 📠 📺 📻 🎙 🎚 "
	@"🎛 🧭 ⏱ ⏲ ⏰ 🕰 ⌛️ ⏳ 📡 🔋 🔌 💡 🔦 🕯 🪔 🧯 🛢 💸 💵 💴 💶 💷 💰 💳 💎 ⚖️ 🧰 🔧 🔨 ⚒ "
	@"🛠 ⛏ 🔩 ⚙️ 🧱 ⛓ 🧲 🔫 💣 🧨 🪓 🔪 🗡 ⚔️ 🛡 🚬 ⚰️ ⚱️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🕳 🩹 🩺 💊 "
	@"💉 🩸 🧬 🦠 🧫 🧪 🌡 🧹 🧺 🧻 🚽 🚰 🚿 🛁 🛀 🧼 🪒 🧽 🧴 🛎 🔑 🗝 🚪 🪑 🛋 🛏 🛌 🧸 🖼 🛍 "
	@"🛒 🎁 🎈 🎏 🎀 🎊 🎉 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 "
	@"🧾 📊 📈 📉 🗒 🗓 📆 📅 🗑 📇 🗃 🗳 🗄 📋 📁 📂 🗂 🗞 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 "
	@"🔗 📎 🖇 📐 📏 🧮 📌 📍 ✂️ 🖊 🖋 ✒️ 🖌 🖍 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓";

static NSString *const kSymbols =
	@"❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉 ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 "
	@"⛎ ♈️ ♉️ ♊️ ♋️ ♌️ ♍️ ♎️ ♏️ ♐️ ♑️ ♒️ ♓️ 🆔 ⚛️ 🉑 ☢️ ☣️ 📴 📳 🈶 🈚️ 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 ㊙️ "
	@"㊗️ 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕️ 🛑 ⛔️ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗️ ❕ ❓ "
	@"❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯️ 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿️ 🅿️ 🈳 🈂️ 🛂 "
	@"🛃 🛄 🛅 🚹 🚺 🚼 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ "
	@"8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ▶️ ⏸ ⏯ ⏹ ⏺ ⏭ ⏮ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ "
	@"↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ ♾ 💲 💱 ™️ ©️ ®️ 〰️ ➰ ➿ 🔚 🔙 🔛 🔝 🔜 ✔️ "
	@"☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫️ ⚪️ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ ◾️ ◽️ ◼️ ◻️ ⬛️ ⬜️ 🔈 🔇 🔉 "
	@"🔊 🔔 🔕 📣 📢 💬 💭 🗯 ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄️ 🕐 🕑 🕒 🕓 🕔 🕕 🕖 🕗 🕘 🕙 🕚 🕛";

static NSString *const kFlags =
	@"🏁 🚩 🎌 🏴 🏳️ 🇷🇺 🇺🇦 🇧🇾 🇰🇿 🇺🇸 🇬🇧 🇩🇪 🇫🇷 🇮🇹 🇪🇸 🇵🇹 🇵🇱 🇨🇿 🇳🇱 🇧🇪 🇨🇭 🇦🇹 🇸🇪 🇳🇴 🇫🇮 🇩🇰 🇮🇪 🇬🇷 🇹🇷 🇮🇱 "
	@"🇬🇪 🇦🇲 🇦🇿 🇺🇿 🇰🇬 🇹🇯 🇹🇲 🇲🇩 🇱🇹 🇱🇻 🇪🇪 🇷🇴 🇧🇬 🇷🇸 🇭🇷 🇭🇺 🇸🇰 🇸🇮 🇨🇳 🇯🇵 🇰🇷 🇮🇳 🇹🇭 🇻🇳 🇮🇩 🇨🇦 🇲🇽 🇧🇷 🇦🇷 🇦🇺";

static NSArray *TGDrawable(NSString *list) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *emoji in [list componentsSeparatedByString:@" "]){
		if (emoji.length && [TGCapabilities canDrawEmoji:emoji])
			[out addObject:emoji];
	}
	return out;
}

NSArray *TGEmojiCategories(void) {
	// Built once, from whichever thread asks first; a second caller waits
	// for that build rather than starting its own.
	static NSArray *categories = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSArray *raw = @[
			@[@"Smileys & People", @"😀", kSmileys],
			@[@"Animals & Nature", @"🐻", kNature],
			@[@"Food & Drink",     @"🍔", kFood],
			@[@"Activity",         @"⚽️", kActivity],
			@[@"Travel & Places",  @"🚗", kTravel],
			@[@"Objects",          @"💡", kObjects],
			@[@"Symbols",          @"❤️", kSymbols],
			@[@"Flags",            @"🏁", kFlags],
		];
		NSMutableArray *out = [NSMutableArray array];
		for (NSArray *row in raw){
			NSArray *emoji = TGDrawable(row[2]);
			if (!emoji.count)
				continue;
			[out addObject:@{@"name" : row[0], @"icon" : row[1], @"emoji" : emoji}];
		}
		categories = out;
	});
	return categories;
}

void TGWarmEmojiData(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// DEFAULT, not LOW: the low queues starve for 15-30 s on one core
		// while the app is busy, and the panel can be opened before then.
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			// The first UIKit string that needs a fallback font makes CoreText
			// build its fallback list from every font on disk, once per
			// process: 0.4-1.8 s on a 4S, and it landed on the main thread in
			// the middle of the panel's first layout. Shaping such a string in
			// the system font here pays it off the main thread.
			UIFont *system = TGFontBody();
			CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)system.fontName,
					system.pointSize, NULL);
			if (font){
				NSAttributedString *text = [[NSAttributedString alloc]
						initWithString:@"A\U0001F600\u4E2D\u0436\u2665"
						attributes:@{(__bridge NSString *)kCTFontAttributeName : (__bridge id)font}];
				CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
				if (line)
					CFRelease(line);
				CFRelease(font);
			}
			// The fallback fonts the title filter asks are created here too.
			TGStripUndrawableScalars(@"\u1D0D");
			TGEmojiCategories();
		});
	});
}

static NSString *const kRecentKey = @"TGRecentEmoji";
static const NSUInteger kRecentLimit = 32;

NSArray *TGRecentEmoji(void) {
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentKey];
	if (!saved.count){
		// What their client starts a fresh install with.
		saved = @[@"😂", @"😘", @"❤️", @"😍", @"😊", @"😁", @"👍", @"☺️", @"😔",
				  @"😄", @"😭", @"💋", @"😒", @"😳", @"😜", @"🙈", @"😉", @"😃",
				  @"😢", @"😝", @"😱", @"😡", @"😏", @"😞", @"😅", @"😚", @"🙊",
				  @"😌", @"😀", @"😋", @"😆", @"👌"];
	}
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *emoji in saved){
		if ([emoji isKindOfClass:NSString.class] && [TGCapabilities canDrawEmoji:emoji])
			[out addObject:emoji];
	}
	return out;
}

void TGNoteEmojiUsed(NSString *emoji) {
	if (!emoji.length)
		return;
	NSMutableArray *recent = [TGRecentEmoji() mutableCopy];
	[recent removeObject:emoji];
	[recent insertObject:emoji atIndex:0];
	while (recent.count > kRecentLimit)
		[recent removeLastObject];
	[[NSUserDefaults standardUserDefaults] setObject:recent forKey:kRecentKey];
}
