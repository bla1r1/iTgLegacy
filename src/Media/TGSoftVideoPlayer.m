//
// TGSoftVideoPlayer.m - FFmpeg decode, AudioQueue sound, GLES2 picture.
//
// One serial thread owns the demuxer and both decoders. It copies at most
// four decoded frames into reusable buffers and hands each to the main thread
// for upload; the audio queue's clock, not the decode speed, decides when a
// frame is due.
//
#import "TGSoftVideoPlayer.h"

#if __arm__

#import "TGSoftVideoClock.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/imgutils.h>
#include <libavutil/samplefmt.h>

// Four frames is 1.4 MB at 480x480 and 3.1 MB at 720x720. The iPod has 256 MB
// and the app already runs at about 30 MB, so the ceiling stays small.
static const int kTGSoftFrameCount = 4;
static const int kTGSoftAudioBuffers = 3;
static const int kTGSoftAudioBufferFrames = 4096;
// Two seconds of PCM is enough to survive a slow packet and still small.
static const int kTGSoftAudioRingSeconds = 2;
// A frame this far ahead of the audio is not shown yet.
static const double kTGSoftLeadSeconds = 0.040;
// The A4 cannot decode and draw a 60 fps stream on one core. Half the frames
// go before the GPU sees them; 30 fps is the device's comfortable rate.
static const double kTGSoftDisplayInterval = 1.0 / 30.0;
// Enough audio before the queue starts that the first video frame's wait for
// the clock does not drain it.
static const double kTGSoftAudioPrefillSeconds = 0.15;
// A frame this far behind the audio has missed its slot even after the
// decoder's quality ladder has been stepped down.
static const double kTGSoftLateSeconds = 0.30;

typedef struct {
	uint8_t *y;
	uint8_t *u;
	uint8_t *v;
	size_t ySize;
	size_t uvSize;
	int width;
	int height;
	double pts;
	BOOL busy;
	unsigned generation;
} TGSoftFrameSlot;

@class TGSoftVideoPlayer;

@interface TGSoftVideoView : UIView
@property (nonatomic, assign) BOOL suspended;
- (void)displayY:(const uint8_t *)y u:(const uint8_t *)u v:(const uint8_t *)v
		   width:(int)width height:(int)height yStride:(int)yStride cStride:(int)cStride
		   bt709:(BOOL)bt709 fullRange:(BOOL)fullRange;
@end

@interface TGSoftVideoPlayer () {
	pthread_t _thread;
	BOOL _threadStarted;
	NSCondition *_lock;
	NSString *_path;

	AVFormatContext *_format;
	AVCodecContext *_videoCtx;
	AVCodecContext *_audioCtx;
	AVPacket *_packet;
	AVFrame *_videoFrame;
	AVFrame *_audioFrame;
	int _videoIndex;
	int _audioIndex;
	BOOL _hasAudio;
	double _duration;
	double _frameDuration;
	BOOL _highFrameRate;
	BOOL _useBT709;
	BOOL _fullRange;

	TGSoftFrameSlot _slots[kTGSoftFrameCount];
	unsigned _displayGeneration;
	double _lastDisplayedPts;
	double _lastVideoPts;
	double _dropBefore;

	AudioQueueRef _audioQueue;
	AudioQueueBufferRef _audioBuffers[kTGSoftAudioBuffers];
	AudioStreamBasicDescription _audioFormat;
	int _audioSampleRate;
	int _audioChannels;
	int16_t *_pcm;
	int _pcmCapacity;
	int _pcmRead;
	int _pcmWrite;
	int _pcmCount;
	int _audioBuffersInFlight;
	BOOL _audioStarted;
	BOOL _audioDone;

	BOOL _opened;
	BOOL _playing;
	BOOL _stopped;
	BOOL _seekPending;
	double _seekTarget;
	BOOL _eof;
	BOOL _atEnd;
	BOOL _failedReported;
	BOOL _resumeAfterBackground;
	TGSoftVideoQuality _quality;

	double _clockBase;
	double _hostStart;
	BOOL _hostRunning;
}
@property (nonatomic, strong) TGSoftVideoView *view;
- (void)runDecodeLoop;
- (void)handleAudioBuffer:(AudioQueueBufferRef)buffer;
@end

// ─── YUV to RGB ───────────────────────────────────────────────────────────────
// GLES2 has no matrix uniforms on some very old drivers in fixed point, but
// mat3 is core ES2 and the A4's SGX535 handles it.

static GLuint TGCompileShader(GLenum type, const char *source) {
	GLuint shader = glCreateShader(type);
	if (!shader)
		return 0;
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	GLint ok = GL_FALSE;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
	if (!ok){
		GLint logLength = 0;
		glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
		if (logLength > 1){
			char *log = malloc((size_t)logLength);
			glGetShaderInfoLog(shader, logLength, NULL, log);
			NSLog(@"TGSoftVideoPlayer: shader: %s", log);
			free(log);
		}
		glDeleteShader(shader);
		return 0;
	}
	return shader;
}

static const char *kTGVertexShader =
	"attribute vec4 a_position;\n"
	"attribute vec2 a_texCoord;\n"
	"uniform vec2 u_scale;\n"
	"varying vec2 v_texCoord;\n"
	"void main(){ gl_Position = vec4(a_position.xy * u_scale, 0.0, 1.0);"
	" v_texCoord = a_texCoord; }\n";

static const char *kTGFragmentShader =
	"precision mediump float;\n"
	"varying vec2 v_texCoord;\n"
	"uniform sampler2D u_y;\n"
	"uniform sampler2D u_u;\n"
	"uniform sampler2D u_v;\n"
	"uniform mat3 u_matrix;\n"
	"uniform vec3 u_offset;\n"
	"void main(){\n"
	" float y = texture2D(u_y, v_texCoord).r;\n"
	" float u = texture2D(u_u, v_texCoord).r - 0.5;\n"
	" float v = texture2D(u_v, v_texCoord).r - 0.5;\n"
	" vec3 rgb = u_matrix * vec3(y, u, v) + u_offset;\n"
	" gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);\n"
	"}\n";

@implementation TGSoftVideoView {
	EAGLContext *_context;
	GLuint _framebuffer;
	GLuint _renderbuffer;
	GLuint _program;
	GLuint _textures[3];
	GLint _positionSlot;
	GLint _texCoordSlot;
	GLint _scaleUniform;
	GLint _yUniform;
	GLint _uUniform;
	GLint _vUniform;
	GLint _matrixUniform;
	GLint _offsetUniform;
	GLsizei _backingWidth;
	GLsizei _backingHeight;
	int _videoWidth;
	int _videoHeight;
}

+ (Class)layerClass {
	return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])){
		self.opaque = YES;
		self.backgroundColor = [UIColor blackColor];
		self.userInteractionEnabled = NO;
		CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
		layer.opaque = YES;
		// One pixel per point: 960x640 of video fill is already 614k pixels
		// on a device with one GPU core, and the picture is being scaled up
		// from 480 anyway.
		layer.contentsScale = 1.0;
		layer.drawableProperties = @{
			kEAGLDrawablePropertyRetainedBacking : @NO,
			kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGB565
		};
	}
	return self;
}

- (BOOL)setupGL {
	if (_context)
		return YES;
	_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
	if (!_context || ![EAGLContext setCurrentContext:_context])
		return NO;

	glGenFramebuffers(1, &_framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
	glGenRenderbuffers(1, &_renderbuffer);
	glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
							  GL_RENDERBUFFER, _renderbuffer);
	[self resizeDrawable];

	GLuint vs = TGCompileShader(GL_VERTEX_SHADER, kTGVertexShader);
	GLuint fs = TGCompileShader(GL_FRAGMENT_SHADER, kTGFragmentShader);
	if (!vs || !fs){
		if (vs) glDeleteShader(vs);
		if (fs) glDeleteShader(fs);
		return NO;
	}
	_program = glCreateProgram();
	glAttachShader(_program, vs);
	glAttachShader(_program, fs);
	glLinkProgram(_program);
	glDeleteShader(vs);
	glDeleteShader(fs);
	GLint linked = GL_FALSE;
	glGetProgramiv(_program, GL_LINK_STATUS, &linked);
	if (!linked){
		NSLog(@"TGSoftVideoPlayer: program did not link");
		glDeleteProgram(_program);
		_program = 0;
		return NO;
	}
	_positionSlot = glGetAttribLocation(_program, "a_position");
	_texCoordSlot = glGetAttribLocation(_program, "a_texCoord");
	_scaleUniform = glGetUniformLocation(_program, "u_scale");
	_yUniform = glGetUniformLocation(_program, "u_y");
	_uUniform = glGetUniformLocation(_program, "u_u");
	_vUniform = glGetUniformLocation(_program, "u_v");
	_matrixUniform = glGetUniformLocation(_program, "u_matrix");
	_offsetUniform = glGetUniformLocation(_program, "u_offset");

	glGenTextures(3, _textures);
	for (int i = 0; i < 3; i++){
		glActiveTexture(GL_TEXTURE0 + i);
		glBindTexture(GL_TEXTURE_2D, _textures[i]);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glDisable(GL_DEPTH_TEST);
	return YES;
}

- (void)resizeDrawable {
	if (!_context)
		return;
	CGSize size = self.bounds.size;
	GLsizei width = (GLsizei)size.width;
	GLsizei height = (GLsizei)size.height;
	if (width <= 0 || height <= 0 || (width == _backingWidth && height == _backingHeight))
		return;
	[EAGLContext setCurrentContext:_context];
	glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
	// Storage has to come from the layer: glRenderbufferStorage makes a buffer
	// presentRenderbuffer has nowhere to show, and the page stays black. The
	// colour format is the layer's RGB565, set in initWithFrame.
	if (![_context renderbufferStorage:GL_RENDERBUFFER
						  fromDrawable:(CAEAGLLayer *)self.layer]){
		NSLog(@"TGSoftVideoPlayer: the layer gave no storage");
		return;
	}
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
	_backingWidth = width;
	_backingHeight = height;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self resizeDrawable];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
	[center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
	if (self.window){
		[center addObserver:self selector:@selector(appWillResignActive)
					   name:UIApplicationWillResignActiveNotification object:nil];
		[center addObserver:self selector:@selector(appDidBecomeActive)
					   name:UIApplicationDidBecomeActiveNotification object:nil];
	}
}

- (void)appWillResignActive {
	_suspended = YES;
}

- (void)appDidBecomeActive {
	_suspended = NO;
}

/// This must run on the main thread with the view still in the hierarchy.
/// The caller's slot is released only after the upload, so the buffer cannot
/// be overwritten while GL is reading it.
- (void)displayY:(const uint8_t *)y u:(const uint8_t *)u v:(const uint8_t *)v
		   width:(int)width height:(int)height yStride:(int)yStride cStride:(int)cStride
		   bt709:(BOOL)bt709 fullRange:(BOOL)fullRange {
	if (_suspended || width <= 0 || height <= 0)
		return;
	if (![self setupGL])
		return;
	[EAGLContext setCurrentContext:_context];
	[self resizeDrawable];
	if (_backingWidth <= 0 || _backingHeight <= 0)
		return;

	glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
	glViewport(0, 0, _backingWidth, _backingHeight);
	glClearColor(0, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);

	int chromaWidth = (width + 1) / 2;
	int chromaHeight = (height + 1) / 2;
	if (_videoWidth != width || _videoHeight != height){
		_videoWidth = width;
		_videoHeight = height;
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, _textures[0]);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, width, height, 0,
					 GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, _textures[1]);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, chromaWidth, chromaHeight, 0,
					 GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, _textures[2]);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, chromaWidth, chromaHeight, 0,
					 GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
	}

	// ES2 has no GL_UNPACK_ROW_LENGTH. The player packs its copies tight, so
	// this is one call per plane; the row loop only covers a driver that
	// handed us a padded frame anyway.
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, _textures[0]);
	if (yStride == width)
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height,
						GL_LUMINANCE, GL_UNSIGNED_BYTE, y);
	else
		for (int row = 0; row < height; row++)
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, row, width, 1,
							GL_LUMINANCE, GL_UNSIGNED_BYTE, y + (size_t)row * yStride);

	glActiveTexture(GL_TEXTURE1);
	glBindTexture(GL_TEXTURE_2D, _textures[1]);
	if (cStride == chromaWidth)
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, chromaWidth, chromaHeight,
						GL_LUMINANCE, GL_UNSIGNED_BYTE, u);
	else
		for (int row = 0; row < chromaHeight; row++)
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, row, chromaWidth, 1,
							GL_LUMINANCE, GL_UNSIGNED_BYTE, u + (size_t)row * cStride);

	glActiveTexture(GL_TEXTURE2);
	glBindTexture(GL_TEXTURE_2D, _textures[2]);
	if (cStride == chromaWidth)
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, chromaWidth, chromaHeight,
						GL_LUMINANCE, GL_UNSIGNED_BYTE, v);
	else
		for (int row = 0; row < chromaHeight; row++)
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, row, chromaWidth, 1,
							GL_LUMINANCE, GL_UNSIGNED_BYTE, v + (size_t)row * cStride);

	// BT.709 for HD and for files that do not say; BT.601 only when the
	// stream names it. The matrix is column-major for glUniformMatrix3fv.
	GLfloat matrix[9];
	GLfloat offset[3] = {0, 0, 0};
	if (fullRange){
		matrix[0] = 1.0f;  matrix[1] = 1.0f;  matrix[2] = 1.0f;
	} else {
		const GLfloat scale = 1.164f;
		matrix[0] = scale; matrix[1] = scale; matrix[2] = scale;
		offset[0] = offset[1] = offset[2] = -scale * (16.0f / 255.0f);
	}
	if (bt709){
		matrix[3] = 0.0f;     matrix[4] = -0.213f; matrix[5] = 2.112f;
		matrix[6] = 1.793f;   matrix[7] = -0.533f; matrix[8] = 0.0f;
	} else {
		matrix[3] = 0.0f;     matrix[4] = -0.391f; matrix[5] = 2.018f;
		matrix[6] = 1.596f;   matrix[7] = -0.813f; matrix[8] = 0.0f;
	}

	// Keep the picture's aspect inside the page, as AVLayerVideoGravityResizeAspect.
	GLfloat sx = 1.0f, sy = 1.0f;
	GLfloat viewAspect = (GLfloat)_backingWidth / (GLfloat)_backingHeight;
	GLfloat videoAspect = (GLfloat)width / (GLfloat)height;
	if (videoAspect > viewAspect)
		sy = viewAspect / videoAspect;
	else
		sx = videoAspect / viewAspect;

	static const GLfloat vertices[] = {
		-1, -1,  1, -1,  -1, 1,  1, 1
	};
	static const GLfloat coords[] = {
		0, 1,  1, 1,  0, 0,  1, 0
	};

	glUseProgram(_program);
	glUniform2f(_scaleUniform, sx, sy);
	glUniformMatrix3fv(_matrixUniform, 1, GL_FALSE, matrix);
	glUniform3fv(_offsetUniform, 1, offset);
	glUniform1i(_yUniform, 0);
	glUniform1i(_uUniform, 1);
	glUniform1i(_vUniform, 2);

	glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, GL_FALSE, 0, vertices);
	glEnableVertexAttribArray(_positionSlot);
	glVertexAttribPointer(_texCoordSlot, 2, GL_FLOAT, GL_FALSE, 0, coords);
	glEnableVertexAttribArray(_texCoordSlot);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
	[_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)dealloc {
	if (!_context)
		return;
	if ([NSThread isMainThread]){
		[EAGLContext setCurrentContext:_context];
		if (_program) glDeleteProgram(_program);
		glDeleteTextures(3, _textures);
		if (_framebuffer) glDeleteFramebuffers(1, &_framebuffer);
		if (_renderbuffer) glDeleteRenderbuffers(1, &_renderbuffer);
		[EAGLContext setCurrentContext:nil];
	}
}

@end

// ─── player ──────────────────────────────────────────────────────────────────

static void *TGSoftVideoThreadMain(void *raw) {
	@autoreleasepool {
		TGSoftVideoPlayer *player = (__bridge TGSoftVideoPlayer *)raw;
		[player runDecodeLoop];
		CFRelease((__bridge CFTypeRef)player);
	}
	return NULL;
}

static void TGSoftVideoAudioCallback(void *userData, AudioQueueRef queue,
									 AudioQueueBufferRef buffer) {
	TGSoftVideoPlayer *player = (__bridge TGSoftVideoPlayer *)userData;
	[player handleAudioBuffer:buffer];
}

static void TGSoftCopyPlane(uint8_t *dst, const uint8_t *src, int stride,
							int width, int height) {
	if (stride == width){
		memcpy(dst, src, (size_t)width * (size_t)height);
		return;
	}
	for (int row = 0; row < height; row++)
		memcpy(dst + (size_t)row * width, src + (ptrdiff_t)row * stride, (size_t)width);
}

@implementation TGSoftVideoPlayer

- (instancetype)initWithPath:(NSString *)path {
	if (!path.length)
		return nil;
	if ((self = [super init])){
		_lock = [[NSCondition alloc] init];
		_path = [path copy];
		_lastDisplayedPts = -1;
		_lastVideoPts = -1;
		_dropBefore = -1;
		_quality = TGSoftVideoQualityFull;
		_hostRunning = NO;
		_view = [[TGSoftVideoView alloc] initWithFrame:CGRectZero];
		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(appWillResignActive)
					name:UIApplicationWillResignActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(appDidBecomeActive)
					name:UIApplicationDidBecomeActiveNotification object:nil];
		CFRetain((__bridge CFTypeRef)self);
		if (pthread_create(&_thread, NULL, TGSoftVideoThreadMain,
						   (__bridge void *)self) != 0){
			CFRelease((__bridge CFTypeRef)self);
			[[NSNotificationCenter defaultCenter] removeObserver:self];
			[self closeMedia];
			return nil;
		}
		_threadStarted = YES;
	}
	return self;
}

- (void)dealloc {
	[self stop];
	for (int i = 0; i < kTGSoftFrameCount; i++){
		free(_slots[i].y);
		free(_slots[i].u);
		free(_slots[i].v);
	}
}

- (BOOL)openMedia {
	if (avformat_open_input(&_format, _path.fileSystemRepresentation, NULL, NULL) < 0)
		return NO;
	// A local MP4 does not need the full probe; a few packets find the
	// streams and keep a 256 MB device from reading half the file here.
	_format->probesize = 512 * 1024;
	if (avformat_find_stream_info(_format, NULL) < 0)
		return NO;

	const AVCodec *videoCodec = NULL;
	_videoIndex = av_find_best_stream(_format, AVMEDIA_TYPE_VIDEO, -1, -1, &videoCodec, 0);
	if (_videoIndex < 0 || !videoCodec)
		return NO;
	AVStream *videoStream = _format->streams[_videoIndex];
	_videoCtx = avcodec_alloc_context3(videoCodec);
	if (!_videoCtx)
		return NO;
	if (avcodec_parameters_to_context(_videoCtx, videoStream->codecpar) < 0)
		return NO;
	// One decode thread on one core; FFmpeg's own threading only adds copies.
	_videoCtx->thread_count = 1;
	_videoCtx->flags2 |= AV_CODEC_FLAG2_FAST;
	_videoCtx->skip_loop_filter = AVDISCARD_DEFAULT;
	_videoCtx->skip_frame = AVDISCARD_DEFAULT;
	if (avcodec_open2(_videoCtx, videoCodec, NULL) < 0)
		return NO;

	AVRational frameRate = videoStream->avg_frame_rate;
	if (frameRate.num <= 0 || frameRate.den <= 0)
		frameRate = videoStream->r_frame_rate;
	double fps = av_q2d(frameRate);
	if (!(fps > 0.0) || fps > 240.0)
		fps = 25.0;
	_frameDuration = 1.0 / fps;
	// Only 30 fps reach the screen, so decoding the rest of a 60 fps clip buys
	// nothing. Non-reference frames are about half of it: 128 fps against 106
	// measured, and the difference is what drawing has to live on.
	_highFrameRate = fps > 45.0;
	if (_highFrameRate)
		_videoCtx->skip_frame = AVDISCARD_NONREF;

	enum AVColorSpace space = _videoCtx->colorspace;
	_useBT709 = space == AVCOL_SPC_BT709 || space == AVCOL_SPC_UNSPECIFIED;
	_fullRange = _videoCtx->color_range == AVCOL_RANGE_JPEG;

	double duration = 0;
	if (_format->duration != AV_NOPTS_VALUE)
		duration = _format->duration / (double)AV_TIME_BASE;
	else if (videoStream->duration != AV_NOPTS_VALUE)
		duration = videoStream->duration * av_q2d(videoStream->time_base);
	[_lock lock];
	_duration = duration;
	[_lock unlock];

	const AVCodec *audioCodec = NULL;
	_audioIndex = av_find_best_stream(_format, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0);
	if (_audioIndex >= 0 && audioCodec){
		_audioCtx = avcodec_alloc_context3(audioCodec);
		if (_audioCtx &&
			avcodec_parameters_to_context(_audioCtx,
										  _format->streams[_audioIndex]->codecpar) == 0){
			_audioCtx->thread_count = 1;
			_audioCtx->flags2 |= AV_CODEC_FLAG2_FAST;
			if (avcodec_open2(_audioCtx, audioCodec, NULL) == 0){
				_hasAudio = [self setupAudio];
			}
		}
		if (!_hasAudio){
			avcodec_free_context(&_audioCtx);
			_audioIndex = -1;
		}
	}

	_packet = av_packet_alloc();
	_videoFrame = av_frame_alloc();
	if (!_packet || !_videoFrame)
		return NO;
	if (_hasAudio){
		_audioFrame = av_frame_alloc();
		if (!_audioFrame)
			return NO;
	}
	return YES;
}

- (BOOL)allocateFrameBuffers {
	int width = _videoCtx->width;
	int height = _videoCtx->height;
	if (width <= 0 || height <= 0)
		return NO;
	size_t ySize = (size_t)width * (size_t)height;
	size_t uvSize = (size_t)((width + 1) / 2) * (size_t)((height + 1) / 2);
	for (int i = 0; i < kTGSoftFrameCount; i++){
		_slots[i].width = width;
		_slots[i].height = height;
		_slots[i].ySize = ySize;
		_slots[i].uvSize = uvSize;
		_slots[i].y = malloc(ySize);
		_slots[i].u = malloc(uvSize);
		_slots[i].v = malloc(uvSize);
		if (!_slots[i].y || !_slots[i].u || !_slots[i].v)
			return NO;
	}
	return YES;
}

/// AAC comes out of FFmpeg as planar float; AudioQueue wants interleaved
/// signed 16-bit. There is no swresample in this build, so the loop is here.
- (BOOL)setupAudio {
	int rate = _audioCtx->sample_rate;
	int channels = _audioCtx->ch_layout.nb_channels;
	if (rate <= 0 || channels <= 0)
		return NO;
	_audioSampleRate = rate;
	_audioChannels = MIN(channels, 2);

	memset(&_audioFormat, 0, sizeof(_audioFormat));
	_audioFormat.mSampleRate = rate;
	_audioFormat.mFormatID = kAudioFormatLinearPCM;
	_audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	_audioFormat.mFramesPerPacket = 1;
	_audioFormat.mChannelsPerFrame = (UInt32)_audioChannels;
	_audioFormat.mBitsPerChannel = 16;
	_audioFormat.mBytesPerFrame = 2 * (UInt32)_audioChannels;
	_audioFormat.mBytesPerPacket = _audioFormat.mBytesPerFrame;

	if (AudioQueueNewOutput(&_audioFormat, TGSoftVideoAudioCallback,
							(__bridge void *)self, NULL, NULL, 0, &_audioQueue) != noErr)
		return NO;
	UInt32 bufferBytes = (UInt32)(kTGSoftAudioBufferFrames *
								  _audioFormat.mBytesPerFrame);
	for (int i = 0; i < kTGSoftAudioBuffers; i++){
		if (AudioQueueAllocateBuffer(_audioQueue, bufferBytes, &_audioBuffers[i]) != noErr){
			AudioQueueDispose(_audioQueue, true);
			_audioQueue = NULL;
			return NO;
		}
	}

	_pcmCapacity = rate * _audioChannels * kTGSoftAudioRingSeconds;
	_pcm = calloc((size_t)_pcmCapacity, sizeof(int16_t));
	if (!_pcm){
		AudioQueueDispose(_audioQueue, true);
		_audioQueue = NULL;
		return NO;
	}
	return YES;
}

- (void)closeMedia {
	if (_audioQueue){
		AudioQueueStop(_audioQueue, true);
		AudioQueueDispose(_audioQueue, true);
		_audioQueue = NULL;
	}
	free(_pcm);
	_pcm = NULL;
	av_frame_free(&_videoFrame);
	av_frame_free(&_audioFrame);
	av_packet_free(&_packet);
	avcodec_free_context(&_videoCtx);
	avcodec_free_context(&_audioCtx);
	if (_format)
		avformat_close_input(&_format);
}

#pragma mark - clock

/// Caller holds `_lock`. AudioQueueGetCurrentTime is the master; a silent
/// GIF has no queue, so its own start time stands in.
- (double)clockLocked {
	if (_seekPending)
		return _seekTarget;
	// The rest of the state is published under the lock when the decode
	// thread finishes opening the file.
	if (!_opened)
		return _clockBase;
	if (_hasAudio && _audioQueue && _audioStarted){
		AudioTimeStamp stamp;
		memset(&stamp, 0, sizeof(stamp));
		stamp.mFlags = kAudioTimeStampSampleTimeValid;
		if (AudioQueueGetCurrentTime(_audioQueue, NULL, &stamp, NULL) == noErr &&
			(stamp.mFlags & kAudioTimeStampSampleTimeValid))
			return _clockBase + stamp.mSampleTime / (double)_audioSampleRate;
	}
	if (_hostRunning)
		return _clockBase + (CFAbsoluteTimeGetCurrent() - _hostStart);
	return _clockBase;
}

- (NSTimeInterval)position {
	[_lock lock];
	double now = [self clockLocked];
	double length = _duration;
	[_lock unlock];
	if (length > 0)
		now = MIN(now, length);
	return MAX(now, 0.0);
}

- (NSTimeInterval)duration {
	[_lock lock];
	double length = _duration;
	[_lock unlock];
	return length;
}

- (BOOL)isPlaying {
	[_lock lock];
	BOOL playing = _playing;
	[_lock unlock];
	return playing;
}

#pragma mark - transport

- (void)play {
	[_lock lock];
	if (_stopped){
		[_lock unlock];
		return;
	}
	if (_atEnd){
		_atEnd = NO;
		_seekPending = YES;
		_seekTarget = 0;
		_clockBase = 0;
	}
	_playing = YES;
	// Before the file is open there is no stream to classify or clock to
	// start; the decode thread does both once opening finishes.
	BOOL opened = _opened;
	if (opened && !_hasAudio){
		_hostStart = CFAbsoluteTimeGetCurrent();
		_hostRunning = YES;
	}
	BOOL resumeQueue = opened && _hasAudio && _audioQueue && _audioStarted;
	[_lock broadcast];
	[_lock unlock];

	// First start waits for the decode thread to buffer real audio: starting
	// with silence would run the clock ahead of the sound by one buffer.
	if (resumeQueue)
		AudioQueueStart(_audioQueue, NULL);
}

- (void)appWillResignActive {
	[_lock lock];
	_resumeAfterBackground = _playing;
	[_lock unlock];
	// iOS kills an app that draws in the background, and sound without a
	// picture is not playback. Both stop here.
	[self pause];
}

- (void)appDidBecomeActive {
	[_lock lock];
	BOOL resume = _resumeAfterBackground;
	_resumeAfterBackground = NO;
	[_lock unlock];
	if (resume)
		[self play];
}

- (void)pause {
	[_lock lock];
	if (!_playing){
		[_lock unlock];
		return;
	}
	if (!_opened){
		_playing = NO;
		[_lock broadcast];
		[_lock unlock];
		return;
	}
	if (!_hasAudio)
		_clockBase = [self clockLocked];
	_hostRunning = NO;
	_playing = NO;
	[_lock broadcast];
	[_lock unlock];
	if (_audioQueue && _audioStarted)
		AudioQueuePause(_audioQueue);
}

- (void)seekToTime:(NSTimeInterval)time {
	[_lock lock];
	if (_stopped){
		[_lock unlock];
		return;
	}
	double target = MAX(0.0, time);
	if (_duration > 0)
		target = MIN(target, _duration);
	_seekTarget = target;
	_seekPending = YES;
	_clockBase = target;
	_atEnd = NO;
	_displayGeneration++;
	[_lock broadcast];
	[_lock unlock];
}

- (void)stop {
	if (!_lock)
		return;
	BOOL join = NO;
	[_lock lock];
	if (!_stopped){
		_stopped = YES;
		_playing = NO;
		[_lock broadcast];
	}
	if (_threadStarted){
		join = YES;
		_threadStarted = NO;
	}
	[_lock unlock];
	// A failed decode can drop the last reference on the decode thread itself;
	// joining yourself would hang the cleanup.
	if (join && !pthread_equal(pthread_self(), _thread))
		pthread_join(_thread, NULL);
	[self closeMedia];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - decode thread

- (void)runDecodeLoop {
	@autoreleasepool {
		// Opening and probing is a disk read plus a few decoded frames; it
		// stays off the main thread with the rest of the work.
		if (!_opened){
			if (![self openMedia] || ![self allocateFrameBuffers]){
				[self reportFailure:@"This video could not be opened"];
				return;
			}
			[_lock lock];
			_opened = YES;
			if (!_hasAudio && _playing){
				_hostStart = CFAbsoluteTimeGetCurrent();
				_hostRunning = YES;
			}
			[_lock broadcast];
			[_lock unlock];
		}
	}
	while (YES){
		// One pool per packet: the wait loops make NSDates, and a long clip
		// must not collect them for its whole length.
		@autoreleasepool {
			[_lock lock];
			if (_stopped){
				[_lock unlock];
				break;
			}
			if (_seekPending){
				double target = _seekTarget;
				[_lock unlock];
				[self performSeek:target];
				[_lock lock];
				if (!_seekPending)
					_seekPending = NO;
				BOOL again = _seekPending;
				[_lock unlock];
				if (again)
					continue;
				continue;
			}
			if (!_playing){
				[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
				[_lock unlock];
				continue;
			}
			if (_eof){
				[_lock unlock];
				[self waitForEndOfStream];
				continue;
			}
			[_lock unlock];

			int ret = av_read_frame(_format, _packet);
			if (ret < 0){
				[self flushDecoders];
				[_lock lock];
				BOOL shortAudio = _hasAudio && !_audioStarted && _pcmCount > 0 && _playing;
				[_lock unlock];
				// A clip shorter than the prefill still has to be heard.
				if (shortAudio)
					[self startAudioQueue];
				[_lock lock];
				_eof = YES;
				if (_hasAudio && _pcmCount == 0 && _audioBuffersInFlight == 0)
					_audioDone = YES;
				[_lock broadcast];
				[_lock unlock];
				continue;
			}
			if (_packet->stream_index == _videoIndex){
				[self decodeVideoPacket:_packet];
			} else if (_hasAudio && _packet->stream_index == _audioIndex){
				[self decodeAudioPacket:_packet];
			}
			av_packet_unref(_packet);
		}
	}
}

- (void)performSeek:(double)target {
	AVStream *videoStream = _format->streams[_videoIndex];
	int64_t timestamp = (int64_t)(target / av_q2d(videoStream->time_base));
	if (av_seek_frame(_format, _videoIndex, timestamp, AVSEEK_FLAG_BACKWARD) < 0)
		av_seek_frame(_format, -1, (int64_t)(target * AV_TIME_BASE),
					  AVSEEK_FLAG_BACKWARD);
	if (_videoCtx)
		avcodec_flush_buffers(_videoCtx);
	if (_audioCtx)
		avcodec_flush_buffers(_audioCtx);

	// Stop the queue before touching its counters: a buffer completion that
	// lands between the reset and the next fill would put a stale buffer back
	// into flight.
	if (_audioQueue){
		AudioQueueStop(_audioQueue, true);
		AudioQueueReset(_audioQueue);
	}

	[_lock lock];
	_pcmRead = _pcmWrite = _pcmCount = 0;
	_audioDone = NO;
	_audioStarted = NO;
	_audioBuffersInFlight = 0;
	_eof = NO;
	_atEnd = NO;
	_lastDisplayedPts = -1;
	_lastVideoPts = -1;
	_dropBefore = target - 0.001;
	_clockBase = target;
	_seekPending = NO;
	_quality = TGSoftVideoQualityFull;
	BOOL playing = _playing;
	if (!_hasAudio){
		_hostStart = CFAbsoluteTimeGetCurrent();
	}
	[_lock broadcast];
	[_lock unlock];

	if (_videoCtx){
		_videoCtx->skip_loop_filter = AVDISCARD_DEFAULT;
		_videoCtx->skip_frame = _highFrameRate ? AVDISCARD_NONREF : AVDISCARD_DEFAULT;
	}
	if (!playing && _audioQueue)
		_audioStarted = NO;
}

- (void)decodeVideoPacket:(AVPacket *)packet {
	int ret = avcodec_send_packet(_videoCtx, packet);
	if (ret < 0 && ret != AVERROR(EAGAIN))
		return;
	while (avcodec_receive_frame(_videoCtx, _videoFrame) == 0){
		[self handleVideoFrame:_videoFrame];
		av_frame_unref(_videoFrame);
	}
}

- (void)handleVideoFrame:(AVFrame *)frame {
	enum AVPixelFormat format = (enum AVPixelFormat)frame->format;
	if (format != AV_PIX_FMT_YUV420P && format != AV_PIX_FMT_YUVJ420P){
		[self reportFailure:@"Unsupported video pixel format"];
		return;
	}

	int64_t stamp = frame->best_effort_timestamp;
	if (stamp == AV_NOPTS_VALUE)
		stamp = frame->pts;
	double pts = stamp == AV_NOPTS_VALUE ? _lastVideoPts + _frameDuration
			: stamp * av_q2d(_format->streams[_videoIndex]->time_base);
	if (_lastVideoPts >= 0 && pts <= _lastVideoPts)
		pts = _lastVideoPts + _frameDuration;
	_lastVideoPts = pts;
	if (_dropBefore >= 0 && pts < _dropBefore)
		return;

	[_lock lock];
	double audio = [self clockLocked];
	TGSoftVideoQuality current = _quality;
	BOOL playing = _playing;
	[_lock unlock];
	if (!playing && !_seekPending)
		return;

	TGSoftVideoDecision decision = TGSoftVideoDecide(audio, pts, _frameDuration, current);
	// skip_frame and skip_loop_filter can be changed between frames; the
	// decoder reads them on the next one.
	if (decision.quality != current){
		_quality = decision.quality;
		_videoCtx->skip_loop_filter = decision.quality >= TGSoftVideoQualitySkipLoopFilter
				? AVDISCARD_ALL : AVDISCARD_DEFAULT;
		// NONREF, not BIDIR: these clips use B frames as references, and dropping
		// those smears blocks over everything until the next key frame.
		_videoCtx->skip_frame = _highFrameRate || decision.quality >= TGSoftVideoQualitySkipBidir
				? AVDISCARD_NONREF : AVDISCARD_DEFAULT;
	}
	if (!decision.display)
		return;

	// A 60 fps file is decoded at 60 but drawn at most at 30: the A4 has one
	// core and GL upload of every second frame is the difference between a
	// picture and a slideshow.
	if (_lastDisplayedPts >= 0 &&
		pts < _lastDisplayedPts + kTGSoftDisplayInterval * 0.9)
		return;

	// Wait for the audio clock, but stay responsive to pause and seek.
	while (YES){
		[_lock lock];
		if (_stopped || _seekPending){
			[_lock unlock];
			return;
		}
		if (!_playing){
			[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			[_lock unlock];
			continue;
		}
		// Before the audio queue runs there is no master clock. Waiting here
		// would also stop the packet reader from ever reaching the audio that
		// starts it, so the frame is dropped instead.
		if (_hasAudio && !_audioStarted){
			[_lock unlock];
			return;
		}
		audio = [self clockLocked];
		[_lock unlock];
		if (audio + kTGSoftLeadSeconds >= pts)
			break;
		[NSThread sleepForTimeInterval:0.005];
	}

	[_lock lock];
	BOOL late = audio - pts > kTGSoftLateSeconds;
	[_lock unlock];
	if (late)
		return;

	TGSoftFrameSlot *slot = [self acquireSlot];
	if (!slot)
		return;
	TGSoftCopyPlane(slot->y, frame->data[0], frame->linesize[0],
					slot->width, slot->height);
	TGSoftCopyPlane(slot->u, frame->data[1], frame->linesize[1],
					(slot->width + 1) / 2, (slot->height + 1) / 2);
	TGSoftCopyPlane(slot->v, frame->data[2], frame->linesize[2],
					(slot->width + 1) / 2, (slot->height + 1) / 2);
	slot->pts = pts;

	[_lock lock];
	slot->generation = _displayGeneration;
	unsigned generation = _displayGeneration;
	BOOL bt709 = _useBT709;
	BOOL fullRange = _fullRange;
	[_lock unlock];

	TGSoftVideoView *view = _view;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_lock lock];
		BOOL show = !self->_stopped && generation == self->_displayGeneration;
		[self->_lock unlock];
		if (show && view)
			[view displayY:slot->y u:slot->u v:slot->v
					  width:slot->width height:slot->height
					yStride:slot->width cStride:(slot->width + 1) / 2
					  bt709:bt709 fullRange:fullRange];
		[self releaseSlot:slot];
#if TG_DEV
		// What the bench cannot measure: the rate with drawing and sound.
		static int shown;
		static CFAbsoluteTime since;
		CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
		if (!since)
			since = now;
		shown++;
		if (now - since >= 2.0){
			NSLog(@"soft video: %.1f fps shown, quality %d, at %.1f s",
					shown / (now - since), (int)self->_quality, pts);
			shown = 0;
			since = now;
		}
#endif
	});
	_lastDisplayedPts = pts;
}

- (TGSoftFrameSlot *)acquireSlot {
	[_lock lock];
	while (!_stopped){
		int busy = 0;
		for (int i = 0; i < kTGSoftFrameCount; i++)
			if (_slots[i].busy)
				busy++;
		if (busy < kTGSoftFrameCount){
			for (int i = 0; i < kTGSoftFrameCount; i++){
				if (!_slots[i].busy){
					_slots[i].busy = YES;
					[_lock unlock];
					return &_slots[i];
				}
			}
		}
		[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
	[_lock unlock];
	return NULL;
}

- (void)releaseSlot:(TGSoftFrameSlot *)slot {
	[_lock lock];
	slot->busy = NO;
	[_lock broadcast];
	[_lock unlock];
}

- (void)decodeAudioPacket:(AVPacket *)packet {
	int ret = avcodec_send_packet(_audioCtx, packet);
	if (ret < 0 && ret != AVERROR(EAGAIN))
		return;
	while (avcodec_receive_frame(_audioCtx, _audioFrame) == 0){
		[self appendAudioFrame:_audioFrame];
		av_frame_unref(_audioFrame);
	}
}

- (void)appendAudioFrame:(AVFrame *)frame {
	int sourceChannels = frame->ch_layout.nb_channels;
	if (sourceChannels <= 0)
		sourceChannels = 1;
	int outChannels = _audioChannels;
	int frames = frame->nb_samples;
	if (frames <= 0)
		return;
	int needed = frames * outChannels;

	[_lock lock];
	while (_pcmCapacity - _pcmCount < needed && !_stopped)
		[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	if (_stopped){
		[_lock unlock];
		return;
	}
	int write = _pcmWrite;
	int capacity = _pcmCapacity;
	for (int i = 0; i < frames; i++){
		for (int channel = 0; channel < outChannels; channel++){
			int sourceChannel = MIN(channel, sourceChannels - 1);
			float sample = 0.0f;
			if (frame->format == AV_SAMPLE_FMT_FLTP){
				sample = ((const float *)frame->data[sourceChannel])[i];
			} else if (frame->format == AV_SAMPLE_FMT_FLT){
				sample = ((const float *)frame->data[0])[i * sourceChannels + sourceChannel];
			} else if (frame->format == AV_SAMPLE_FMT_S16P){
				sample = ((const int16_t *)frame->data[sourceChannel])[i] / 32768.0f;
			} else if (frame->format == AV_SAMPLE_FMT_S16){
				sample = ((const int16_t *)frame->data[0])[i * sourceChannels + sourceChannel] / 32768.0f;
			}
			if (sample > 1.0f) sample = 1.0f;
			if (sample < -1.0f) sample = -1.0f;
			_pcm[write] = (int16_t)lrintf(sample * 32767.0f);
			if (++write >= capacity)
				write = 0;
		}
	}
	_pcmWrite = write;
	_pcmCount += needed;
	[_lock broadcast];   // a buffer callback may be waiting for data
	BOOL start = !_audioStarted &&
			_pcmCount >= (int)(_audioSampleRate * _audioChannels *
							   kTGSoftAudioPrefillSeconds);
	[_lock unlock];

	if (start)
		[self startAudioQueue];
}

- (void)startAudioQueue {
	[_lock lock];
	if (_audioStarted || _stopped || !_playing){
		[_lock unlock];
		return;
	}
	_audioStarted = YES;
	_audioBuffersInFlight = 0;
	_audioDone = NO;
	[_lock unlock];

	// Do not pad with silence here: those buffers would become a gap between
	// the buffered audio and the audio decoded while they play.
	for (int i = 0; i < kTGSoftAudioBuffers; i++){
		if (![self fillAudioBuffer:_audioBuffers[i] allowSilence:NO])
			break;
	}
	AudioQueueStart(_audioQueue, NULL);
}

/// Returns YES when a buffer went to the queue. At EOF a short buffer is the
/// last one; if there is nothing left at all the queue drains and the clock
/// stops, which is what ends playback. `allowSilence` keeps the clock alive
/// during playback, but pad at the start would be a hole in the sound.
- (BOOL)fillAudioBuffer:(AudioQueueBufferRef)buffer allowSilence:(BOOL)allowSilence {
	[_lock lock];
	if (!_audioQueue || _stopped){
		[_lock unlock];
		return NO;
	}
	int channels = _audioChannels;
	int maxFrames = (int)(buffer->mAudioDataBytesCapacity /
						  (2 * (UInt32)channels));
	// A just-emptied queue gives the decoder a moment to put the next packet
	// in rather than starting a hole that would stay between sound and video.
	if (allowSilence && _pcmCount == 0 && !_eof){
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.02];
		while (_pcmCount == 0 && !_eof && !_stopped &&
			   [deadline timeIntervalSinceNow] > 0)
			[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	}
	int frames = MIN(maxFrames, _pcmCount / channels);
	int16_t *dst = (int16_t *)buffer->mAudioData;
	int read = _pcmRead;
	for (int i = 0; i < frames * channels; i++){
		dst[i] = _pcm[read];
		if (++read >= _pcmCapacity)
			read = 0;
	}
	_pcmRead = read;
	_pcmCount -= frames * channels;

	BOOL enqueue = frames > 0;
	if (frames == 0 && !_eof && !allowSilence){
		[_lock unlock];
		return NO;
	}
	if (frames == 0 && !_eof){
		// Keep the queue alive through a slow packet; silence is better than
		// stopping the master clock while the demuxer catches up.
		memset(buffer->mAudioData, 0, (size_t)maxFrames * 2 * channels);
		buffer->mAudioDataByteSize = (UInt32)(maxFrames * 2 * channels);
		enqueue = YES;
	} else {
		buffer->mAudioDataByteSize = (UInt32)(frames * 2 * channels);
	}
	if (enqueue)
		_audioBuffersInFlight++;
	else if (_pcmCount == 0 && _audioBuffersInFlight == 0)
		_audioDone = YES;
	[_lock unlock];

	if (enqueue)
		AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
	return enqueue;
}

- (void)handleAudioBuffer:(AudioQueueBufferRef)buffer {
	[_lock lock];
	if (!_audioQueue){
		[_lock unlock];
		return;
	}
	if (_audioBuffersInFlight > 0)
		_audioBuffersInFlight--;
	BOOL done = _eof && _pcmCount == 0 && _audioBuffersInFlight == 0;
	if (done)
		_audioDone = YES;
	[_lock unlock];
	if (!done)
		[self fillAudioBuffer:buffer allowSilence:YES];
}

- (void)flushDecoders {
	if (_videoCtx && _packet){
		avcodec_send_packet(_videoCtx, NULL);
		while (avcodec_receive_frame(_videoCtx, _videoFrame) == 0){
			[self handleVideoFrame:_videoFrame];
			av_frame_unref(_videoFrame);
		}
	}
	if (_audioCtx && _audioFrame){
		avcodec_send_packet(_audioCtx, NULL);
		while (avcodec_receive_frame(_audioCtx, _audioFrame) == 0){
			[self appendAudioFrame:_audioFrame];
			av_frame_unref(_audioFrame);
		}
	}
}

- (void)waitForEndOfStream {
	while (YES){
		[_lock lock];
		if (_stopped || _seekPending){
			[_lock unlock];
			return;
		}
		if (!_playing){
			[_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			[_lock unlock];
			continue;
		}
		double now = [self clockLocked];
		BOOL audioDone = !_hasAudio || _audioDone;
		BOOL timeDone = now >= (_duration > 0 ? _duration - _frameDuration
											  : _lastVideoPts + _frameDuration);
		[_lock unlock];
		if (audioDone && timeDone){
			[self finishPlayback];
			return;
		}
		[NSThread sleepForTimeInterval:0.05];
	}
}

- (void)finishPlayback {
	[_lock lock];
	BOOL loops = _loops;
	[_lock unlock];
	if (loops){
		[_lock lock];
		_seekPending = YES;
		_seekTarget = 0;
		_clockBase = 0;
		_atEnd = NO;
		_displayGeneration++;
		[_lock broadcast];
		[_lock unlock];
		return;
	}
	[_lock lock];
	_playing = NO;
	_atEnd = YES;
	[_lock unlock];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.finished)
			self.finished();
	});
}

- (void)reportFailure:(NSString *)message {
	[_lock lock];
	if (_failedReported || _stopped){
		[_lock unlock];
		return;
	}
	_failedReported = YES;
	_playing = NO;
	_stopped = YES;
	[_lock broadcast];
	[_lock unlock];
	NSError *error = [NSError errorWithDomain:@"TGSoftVideoPlayer" code:-1
									 userInfo:@{NSLocalizedDescriptionKey : message ?: @"Video decode failed"}];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.failed)
			self.failed(error);
	});
}

@end

#else   // !__arm__

@implementation TGSoftVideoPlayer

- (instancetype)initWithPath:(NSString *)path {
	return nil;
}

- (void)play {}
- (void)pause {}
- (void)seekToTime:(NSTimeInterval)time {}
- (void)stop {}

@end

#endif
