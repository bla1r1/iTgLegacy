//
//  UIImage+WebP.h
//  iOS-WebP
//
//  Created by Sean Ooi on 12/21/13.
//  Copyright (c) 2013 Sean Ooi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (WebP)

+ (UIImage *)convertFromWebP:(NSString *)filePath compressedData:(__autoreleasing NSData **)compressedData error:(NSError **)error;
+ (UIImage *)convertFromGZippedData:(NSString *)filePath size:(CGSize)size;

/// A static sticker or a set thumbnail as the bytes Telegram accepts: the
/// picture aspect-fitted on a transparent 512x512 square, encoded as WebP.
/// The declared sticker format and the bytes then agree. nil on failure.
+ (NSData *)webPDataFromImage:(UIImage *)image quality:(CGFloat)quality;

@end
