//
//  SCViewController.m
//  Scribe
//
//  Created by Michael Scaria on 2/14/14.
//  Copyright (c) 2014 MichaelScaria. All rights reserved.
//


#import "SCViewController.h"

#import "JSONKit.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <Accelerate/Accelerate.h>

#import <AssetsLibrary/AssetsLibrary.h>

#define kCameraViewOffset 60
#define KSizeOfSquare 75.0f

#define BLACK_THRESHOLD 45
#define PERCENT_ERROR .00001

#define BOUNDARY @"AaB03x"

static inline double radians (double degrees) {return degrees * M_PI/180;}

@interface SCViewController ()
@property (readwrite) CMVideoCodecType videoType;
@end

@implementation SCViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    hasOverlay = YES;
	self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    screenSize = [[UIScreen mainScreen] bounds].size;
    _cameraPreviewView.context = self.context;
    _cameraPreviewView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    coreImageContext = [CIContext contextWithEAGLContext:self.context];
    
    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
    
    NSError *error;
    self.device = [self videoDeviceWithPosition:AVCaptureDevicePositionBack];
    videoIn = [[AVCaptureDeviceInput alloc] initWithDevice:self.device error:&error];
    
    AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
    [videoOut setAlwaysDiscardsLateVideoFrames:YES];
    //    @{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]};
    [videoOut setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [videoOut setSampleBufferDelegate:self queue:dispatch_queue_create("com.michaelscaria.VidLab Video", DISPATCH_QUEUE_SERIAL)];
    
    avCaptureSession = [[AVCaptureSession alloc] init];
    [avCaptureSession beginConfiguration];
    [avCaptureSession setSessionPreset:AVCaptureSessionPreset1280x720];
    if ([avCaptureSession canAddInput:videoIn]) [avCaptureSession addInput:videoIn];
    if ([avCaptureSession canAddOutput:videoOut]) [avCaptureSession addOutput:videoOut];
    videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
    
    [avCaptureSession commitConfiguration];
    [avCaptureSession startRunning];
    
    [self setupCGContext];
    CGImageRef cgImg = CGBitmapContextCreateImage(cgContext);
    maskImage = [CIImage imageWithCGImage:cgImg];
    CGImageRelease(cgImg);
    
    
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(takePicture)];
    tap.numberOfTapsRequired = 2;
    [_cameraPreviewView addGestureRecognizer:tap];
    
    UITapGestureRecognizer *focusTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focus:)];
    focusTap.numberOfTapsRequired = 1;
    [focusTap requireGestureRecognizerToFail:tap];
    [_cameraPreviewView addGestureRecognizer:focusTap];
    
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown;
    [_cameraPreviewView addGestureRecognizer:swipe];

    svc = [[SCSitesViewController alloc] init];
    svc = [self.storyboard instantiateViewControllerWithIdentifier:@"Sites"];
    svc.delegate = self;
    [_overlayView addSubview:svc.view];
    
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
//        [self goToCamera];
//    });
}

- (void)takePicture {
    takePicture = YES;
}

- (void)focus:(UITapGestureRecognizer *)recognizer {
    CGPoint locationPoint = [recognizer locationInView:self.view];
    [self autoFocusAtPoint:locationPoint];
    CGPoint resizedPoint = CGPointMake(locationPoint.x / _cameraPreviewView.bounds.size.width, locationPoint.y / _cameraPreviewView.bounds.size.height);
    CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(0.5,0.5);
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(-90);
    CGAffineTransform customRotation = CGAffineTransformConcat(CGAffineTransformConcat( CGAffineTransformInvert(translateTransform), rotationTransform), translateTransform);
    CGPoint newPoint = CGPointApplyAffineTransform(resizedPoint, customRotation);
    
    AVCaptureDevice *captureDevice = self.device;
    if ([_device isFocusPointOfInterestSupported] && [captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        if ([captureDevice lockForConfiguration:&error]) {
            [captureDevice setFocusPointOfInterest:newPoint];
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            [captureDevice unlockForConfiguration];
        }
    }
}

- (void) autoFocusAtPoint:(CGPoint)point
{
    //make square for focus
    float halfSize = KSizeOfSquare/2.0;
    
    
    focusGrid = [[CAShapeLayer alloc] init];
    CGRect finalRect = (CGRect){
        point.x - halfSize,
        point.y - halfSize,
        KSizeOfSquare,KSizeOfSquare
    };
    UIBezierPath *finalPath = [self pathWithRect:finalRect];
    
    halfSize = KSizeOfSquare*3.0/2.0;
    CGRect initialRect = (CGRect){
        point.x - halfSize,
        point.y - halfSize,
        KSizeOfSquare*3,KSizeOfSquare*3
    };
    
    UIBezierPath *initialPath = [self pathWithRect:initialRect];
    
    focusGrid.path = initialPath.CGPath;
    focusGrid.lineWidth = 1.0;
    focusGrid.miterLimit = 5.0;
    focusGrid.fillColor = [UIColor clearColor].CGColor;
    //grid.shouldRasterize = YES;
    focusGrid.lineCap = kCALineCapRound;
    focusGrid.strokeColor = [UIColor whiteColor].CGColor;
    
    //grid.shadow
    focusGrid.strokeColor = [UIColor whiteColor].CGColor;
    
    CAShapeLayer *maskLayert = [[CAShapeLayer alloc] init];
    maskLayert.path = initialPath.CGPath;
    maskLayert.fillColor = [UIColor clearColor].CGColor;
    maskLayert.lineWidth = 2;
    maskLayert.miterLimit = 5.0;
    maskLayert.lineCap = kCALineCapRound;
    maskLayert.strokeColor = [UIColor whiteColor].CGColor;
    
    
    [_cameraPreviewView.layer addSublayer:focusGrid];
    focusGrid.mask = maskLayert;
    
    [CATransaction begin];
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.duration = 0.25;
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.toValue = (id)finalPath.CGPath;
    [focusGrid addAnimation:animation forKey:@"animatePath"];
    [maskLayert addAnimation:animation forKey:@"animatePathII"];
    
    
    [CATransaction setCompletionBlock:^{
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            
            [focusGrid removeAllAnimations];
            [maskLayert removeAllAnimations];
            [focusGrid removeFromSuperlayer];
            [maskLayert removeFromSuperlayer];
            focusGrid = nil;
            
        });
    }];
    [CATransaction commit];
    
}

- (UIBezierPath*)pathWithRect:(CGRect)rect{
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:rect];
    
    CGFloat offset = rect.size.width/10.0;
    CGPoint origin = rect.origin;
    
    [path moveToPoint:(CGPoint){origin.x + rect.size.width/2.0,origin.y}];//Top
    [path addLineToPoint:(CGPoint){origin.x + rect.size.width/2.0,origin.y + offset}];
    
    [path moveToPoint:(CGPoint){origin.x,origin.y + rect.size.height/2.0}];//Left
    [path addLineToPoint:(CGPoint){origin.x + offset,origin.y + rect.size.height/2.0}];
    
    [path moveToPoint:(CGPoint){origin.x +rect.size.width,origin.y + rect.size.height/2.0}];//Right
    [path addLineToPoint:(CGPoint){origin.x + rect.size.width - offset,origin.y + rect.size.height/2.0}];
    
    [path moveToPoint:(CGPoint){origin.x + rect.size.width/2.0,origin.y + rect.size.height}];//Bottom
    [path addLineToPoint:(CGPoint){origin.x + rect.size.width/2.0,origin.y + rect.size.height - offset}];
    
    return path;
}

- (void)swiped {
    [UIView animateWithDuration:.5 animations:^{
        _overlayView.alpha = 1;
    }completion:^(BOOL isCompleted){
        hasOverlay = YES;
    }];
}

- (AVCaptureDevice *)videoDeviceWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *aDevice in devices)
        if ([aDevice position] == position)
            return aDevice;
    
    return nil;
}

-(void)setupCGContext {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * screenSize.width;
    NSUInteger bitsPerComponent = 8;
    NSLog(@"%lu %f", (unsigned long)bytesPerRow, screenSize.width);
    cgContext = CGBitmapContextCreate(NULL, screenSize.width, screenSize.height, bitsPerComponent, bytesPerRow, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!cgContext) {
        NSLog(@"nil");
    }
    CGColorSpaceRelease(colorSpace);
}

#pragma mark Capture

- (unsigned char*) rotateBuffer: (CMSampleBufferRef) sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t currSize = bytesPerRow*height*sizeof(unsigned char);
    size_t bytesPerRowOut = 4*height*sizeof(unsigned char);
    
    void *srcBuff = CVPixelBufferGetBaseAddress(imageBuffer);
    
    /*
     * rotationConstant:   0 -- rotate 0 degrees (simply copy the data from src to dest)
     *             1 -- rotate 90 degrees counterclockwise
     *             2 -- rotate 180 degress
     *             3 -- rotate 270 degrees counterclockwise
     */
    uint8_t rotationConstant = 3;
    
    unsigned char *outBuff = (unsigned char*)malloc(currSize);
    
    vImage_Buffer ibuff = { srcBuff, height, width, bytesPerRow};
    vImage_Buffer ubuff = { outBuff, width, height, bytesPerRowOut};
    Pixel_8888 backgroundColor = {0,0,0,0} ;
    vImage_Error err= vImageRotate90_ARGB8888 (&ibuff, &ubuff,rotationConstant, backgroundColor, kvImageNoFlags);
    if (err != kvImageNoError) NSLog(@"%ld", err);
    
    return outBuff;
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    if (takePicture) {
        takePicture = NO;
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        
        CVReturn lock = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        if (lock == kCVReturnSuccess) {
            unsigned long w = 0;
            unsigned long h = 0;
            unsigned long r = 0;
            unsigned long bytesPerPixel = 0;
            unsigned char *buffer;
            //switch
            h = CVPixelBufferGetWidth(pixelBuffer);
            w = CVPixelBufferGetHeight(pixelBuffer);
            r = CVPixelBufferGetBytesPerRow(pixelBuffer);
            bytesPerPixel = r/h;
            buffer = [self rotateBuffer:sampleBuffer];
            UIGraphicsBeginImageContext(CGSizeMake(w, h));
            CGContextRef c = UIGraphicsGetCurrentContext();
            unsigned char* data = CGBitmapContextGetData(c);
            NSLog(@"bytesPerPixel:%lu", bytesPerPixel);
            if (data != NULL) {
                
                for (int y = 0; y < h - 4; y++) {
                    for (int x = 0; x < w - 4; x++) {
                        unsigned long offset = bytesPerPixel*((w*y)+x);
                        offset +=2;
                        data[offset] = buffer[offset];
                        data[offset + 1] = buffer[offset + 1];
                        data[offset + 2] = buffer[offset + 2];
                        data[offset + 3] = buffer[offset + 3];
                    }
                }
                
                UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
                
                UIGraphicsEndImageContext();
                UIImageWriteToSavedPhotosAlbum(img, self, @selector(image:finishedSavingWithError:contextInfo:), nil);
                
            }
            
            
        }
    }
    
    if (connection == videoConnection) {
        if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        if (hasOverlay) {
            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
            [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@18.0f forKey:@"inputRadius"];
            image = [filter valueForKey:kCIOutputImageKey];
        }
        CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
        image = [image imageByApplyingTransform:transform];
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [coreImageContext drawImage:image inRect:CGRectMake(0, 0, screenSize.width*2, screenSize.height*2) fromRect:CGRectMake(0, -1280, 720, 1280)];
            [self.context presentRenderbuffer:GL_RENDERBUFFER];
        });
    }
    
}


-(void)image:(UIImage *)image finishedSavingWithError:(NSError *)imageError contextInfo:(void *)contextInfo {
    if (imageError) {
        UIAlertView *alert = [[UIAlertView alloc]
                              initWithTitle: @"Save failed"
                              message: @"Failed to save image"
                              delegate: nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    NSLog(@"finishedSavingWithError:%@", NSStringFromCGSize(image.size));
    
    NSError *error = nil; NSURLResponse *response = nil;
    NSMutableData *body = [NSMutableData data];
//    NSLog(@"Size:%@", NSStringFromCGSize(image.size));
    image = [self resizeImage:image newSize:CGSizeMake(image.size.width *.75, image.size.height *.75)];
//    NSLog(@"Size:%@", NSStringFromCGSize(image.size));
    NSData *dataImage = UIImagePNGRepresentation(image);
    if (!dataImage) {
        NSLog(@"shit");
    }
    NSDictionary *dictionary = @{@"file": dataImage};
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", BOUNDARY] dataUsingEncoding:NSUTF8StringEncoding]];
        
        if ([value isKindOfClass:[NSData class]]) {
            NSString *name = @"file";
            NSString *filename = @"file.png";
            NSString *type = @"image/png";
            [body appendData: [[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@\r\nContent-Transfer-Encoding: binary\r\n\r\n", name, filename, type] dataUsingEncoding:NSUTF8StringEncoding]];
        } else {
            [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        
        if ([value isKindOfClass:[NSData class]]) {
            
            
            [body appendData:value];
            
        } else {
            [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
        }
        
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }];
    
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", BOUNDARY] dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
    NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://scribe.zachlatta.com/upload"] cachePolicy: NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [req setHTTPMethod:@"POST"];
    [req setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [req setHTTPShouldHandleCookies:NO];
    [req setTimeoutInterval:30];
    [req setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", BOUNDARY];
    [req setValue:contentType forHTTPHeaderField: @"Content-Type"];
    [req setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [req setHTTPBody:body];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&response error:&error];
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
//        NSString *v = @"C50yEGDi";
//        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Success!" message:[NSString stringWithFormat:@"Visit your site at scribe.zachlatta.com/p/%@", v] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
//            [alert show];
//            NSArray *array = [[NSUserDefaults standardUserDefaults] objectForKey:@"Sites"];
//            [[NSUserDefaults standardUserDefaults] setObject:[array arrayByAddingObject:@{@"Title" : v, @"URL" : [NSString stringWithFormat:@"scribe.zachlatta.com/p/%@", v]}] forKey:@"Sites"];
//            [[NSUserDefaults standardUserDefaults] synchronize];
//            [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdatedLocations" object:nil];
//        [self swiped];
//    });
    if (error) {
        NSLog(@"Error:%@", error.localizedDescription);
    }
    else {
        id d = [[JSONDecoder decoder] objectWithData:data];
        NSLog(@"response:%@", d);
        if (d[@"error"] || !d || d == [NSNull null]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Please try retaking the picture" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
            [alert show];
        }
        else if (d[@"Success"]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Success!" message:[NSString stringWithFormat:@"Visit your site at scribe.zachlatta.com/p/%@", d[@"SessionID"]] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
            [alert show];
            NSArray *array = [[NSUserDefaults standardUserDefaults] objectForKey:@"Sites"];
            [[NSUserDefaults standardUserDefaults] setObject:[array arrayByAddingObject:@{@"Title" : d[@"SessionID"], @"URL" : [NSString stringWithFormat:@"scribe.zachlatta.com/p/%@", d[@"SessionID"]]}] forKey:@"Sites"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdatedLocations" object:nil];
        }
        [self swiped];
    }
}

- (UIImage *)resizeImage:(UIImage*)image newSize:(CGSize)newSize {
    CGRect newRect = CGRectIntegral(CGRectMake(0, 0, newSize.width, newSize.height));
    CGImageRef imageRef = image.CGImage;
    
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Set the quality level to use when rescaling
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, newSize.height);
    
    CGContextConcatCTM(context, flipVertical);
    // Draw into the context; this scales the image
    CGContextDrawImage(context, newRect, imageRef);
    
    // Get the resized image from the context and a UIImage
    CGImageRef newImageRef = CGBitmapContextCreateImage(context);
    UIImage *newImage = [UIImage imageWithCGImage:newImageRef];
    
    CGImageRelease(newImageRef);
    UIGraphicsEndImageContext();
    
    return newImage;
}


#pragma mark - SCSitesViewControllerDelegate

- (void)goToCamera {
    [UIView animateWithDuration:.5 animations:^{
        _overlayView.alpha = 0;
    }completion:^(BOOL isCompleted){
        hasOverlay = NO;
    }];
}
@end
