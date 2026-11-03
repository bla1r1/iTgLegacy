#import "TGProfileTrackCell.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"

/// The duration column is one short "m:ss" at most.
static const CGFloat kTrackDurationWidth = TGMetricLineSubhead * 3.0f;

@interface TGProfileTrackCell ()
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UIImageView *discView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, assign) BOOL current;
@property (nonatomic, assign) BOOL playing;
@end

@implementation TGProfileTrackCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])){
		_artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_artworkView.backgroundColor = [[TGTheme shared] fileTileColour];
		_artworkView.contentMode = UIViewContentModeScaleAspectFill;
		[self.contentView addSubview:_artworkView];

		_discView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_discView.contentMode = UIViewContentModeScaleAspectFit;
		[self.contentView addSubview:_discView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = TGFontBodyStrong();
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[self.contentView addSubview:_titleLabel];

		_artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_artistLabel.font = TGFontCaption();
		_artistLabel.backgroundColor = [UIColor clearColor];
		_artistLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[self.contentView addSubview:_artistLabel];

		_durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_durationLabel.font = TGFontCaption();
		_durationLabel.textAlignment = NSTextAlignmentRight;
		_durationLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_durationLabel];
	}
	return self;
}

- (void)configureTitle:(NSString *)title
				artist:(NSString *)artist
			  duration:(NSString *)duration
			   current:(BOOL)current
			   playing:(BOOL)playing {
	self.current = current;
	self.playing = playing;
	TGTheme *theme = [TGTheme shared];
	self.titleLabel.text = title;
	self.titleLabel.textColor = current ? [theme accentColour] : [theme primaryTextColour];
	self.artistLabel.text = artist;
	self.artistLabel.textColor = [theme secondaryTextColour];
	self.durationLabel.text = duration;
	self.durationLabel.textColor = [theme secondaryTextColour];
	self.discView.image = [TGIcons mediaDiscOfSide:TGMetricTrackDisc
										   playing:(current && playing)];
	[self setNeedsLayout];
}

- (void)setArtworkImage:(UIImage *)image {
	if (image){
		self.artworkView.image = image;
		self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
		return;
	}
	// No cover yet: the row still says what it is instead of showing a blank.
	self.artworkView.image = [TGIcons glyphNamed:@"music"
										 colour:[[TGTheme shared] secondaryTextColour]
										   side:TGMetricMenuGlyph];
	self.artworkView.contentMode = UIViewContentModeCenter;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat height = self.contentView.bounds.size.height;
	CGFloat width = self.contentView.bounds.size.width;
	CGFloat artSide = TGMetricTrackArt;
	CGFloat artX = TGMetricPadMedium;
	CGFloat artY = TGCenteredOrigin(height, artSide);
	self.artworkView.frame = CGRectMake(artX, artY, artSide, artSide);

	CGFloat disc = TGMetricTrackDisc;
	self.discView.frame = CGRectMake(artX + TGCenteredOrigin(artSide, disc),
									 artY + TGCenteredOrigin(artSide, disc),
									 disc, disc);

	CGFloat textX = artX + artSide + TGMetricPad;
	CGFloat textW = width - textX - kTrackDurationWidth - TGMetricPadMedium - TGMetricPad;
	self.titleLabel.frame = CGRectMake(textX, TGMetricPad, textW, TGMetricLineBody);
	self.artistLabel.frame = CGRectMake(textX, TGMetricPad + TGMetricLineBody,
										textW, TGMetricLineCaption);
	CGFloat durationH = TGMetricLineCaption;
	self.durationLabel.frame = CGRectMake(width - TGMetricPadMedium - kTrackDurationWidth,
										  TGCenteredOrigin(height, durationH),
										  kTrackDurationWidth, durationH);
}

@end

// vim:ft=objc
