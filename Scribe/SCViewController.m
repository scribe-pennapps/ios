//
//  SCViewController.m
//  Scribe
//
//  Created by Michael Scaria on 2/14/14.
//  Copyright (c) 2014 MichaelScaria. All rights reserved.
//


#import "SCViewController.h"


#import <MobileCoreServices/MobileCoreServices.h>
#import <Accelerate/Accelerate.h>

#define kCameraViewOffset 60
#define KSizeOfSquare 75.0f

#define BLACK_THRESHOLD 45
#define PERCENT_ERROR .00001

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
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self goToCamera];
    });
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
        NSMutableArray *circles = [[NSMutableArray alloc] init];
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
//            buffer = CVPixelBufferGetBaseAddress(pixelBuffer);
            buffer = [self rotateBuffer:sampleBuffer];
            UIGraphicsBeginImageContext(CGSizeMake(w, h));
            CGContextRef c = UIGraphicsGetCurrentContext();
            unsigned char* data = CGBitmapContextGetData(c);
            NSLog(@"bytesPerPixel:%lu", bytesPerPixel);
            if (data != NULL) {
                
//                for (int y = 0; y < h; y++) {
//                    for (int x = 0; x < w; x++) {
//                        unsigned long offset = bytesPerPixel*((w*y)+x);
////                        NSLog(@"r:%d g:%d b:%d a:%f", buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3]/255.0);
////                        float average = (buffer[offset] + buffer[offset+1] + buffer[offset+2])/3;
//                        BOOL testPercent = (buffer[offset] > BLACK_THRESHOLD &&  buffer[offset+1] > BLACK_THRESHOLD &&  buffer[offset+2] > BLACK_THRESHOLD);
//                        offset +=2;
//                        if (!testPercent/* || (abs(1 - buffer[offset]/average) < PERCENT_ERROR &&  abs(1 - buffer[offset + 1]/average) < PERCENT_ERROR &&  abs(1 - buffer[offset + 2]/average) < PERCENT_ERROR)*/) {
//                            //TODO:hack
//                            if (y > h/2) {
//                                data[offset] = 170;
//                                data[offset + 1] = 220;
//                                data[offset + 2] = 0;
//                                data[offset + 3] = 255;
//                            }
//                            else {
//                                data[offset] = 52;
//                                data[offset + 1] = 170;
//                                data[offset + 2] = 220;
//                                data[offset + 3] = 255;
//                            }
//                            
//                        }
//                    }
//                }
                for (int y = 0; y < h; y++) {
//                    BOOL firstVerticalFound = NO;
                    for (int x = 0; x < w; x++) {
                        unsigned long offset = bytesPerPixel*((w*y)+x);
                        if (buffer[offset] < BLACK_THRESHOLD &&  buffer[offset+1] < BLACK_THRESHOLD &&  buffer[offset+2] < BLACK_THRESHOLD) {
                            //TODO:hack
//                            firstVerticalFound = YES;
                            //check if corner
                            int counter = 0;
                            //weighted horizontal
//                            NSLog(@"%d, %lu", x + 1500, w-1);
                            int horizontalEndLimit = MIN(x + 1500, w - 400);
                            int horizontalStartLimit = MAX(x - 1500, 0);
                            for (int k = y; k < y + 10; k++) {
                                for (int j = horizontalStartLimit; j < horizontalEndLimit; j++) {
                                    unsigned long cOffset = bytesPerPixel*((w*k)+j);
                                    if ((buffer[cOffset] < BLACK_THRESHOLD &&  buffer[cOffset+1] < BLACK_THRESHOLD &&  buffer[cOffset+2] < BLACK_THRESHOLD)) {
                                        counter += 1;
                                    }
                                    
                                }
                            }

                            int verticalStartLimit = MIN(y + 11, h - 4);
                            int verticalEndLimit = MIN(y - 11, 0);
                            for (int k = verticalStartLimit; k < verticalEndLimit; k++) {
                                for (int j = x + 1; j < x + 11; j++) {
                                    unsigned long cOffset = bytesPerPixel*((w*k)+j);
                                    if ((buffer[cOffset] < BLACK_THRESHOLD &&  buffer[cOffset+1] < BLACK_THRESHOLD &&  buffer[cOffset+2] < BLACK_THRESHOLD)) {
                                        counter++;
                                    }
                                    
                                }
                            }
                            float percentage = .004;
//                            ((horizontalLimit - (x + 1)) * (verticalLimit - y))
                            float finalPercentage = counter/((float)((horizontalEndLimit - horizontalStartLimit) *1)* (verticalEndLimit - verticalStartLimit));
                            NSLog(@"percentage:%f", finalPercentage);
                            if (finalPercentage > percentage && finalPercentage < 8) {
                                UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(((float)x/w) * self.view.frame.size.width, ((float)y/h) * self.view.frame.size.height, 500 * finalPercentage, 500 * finalPercentage)];
                                circle.layer.cornerRadius = circle.frame.size.width/2;
                                circle.backgroundColor = [UIColor colorWithRed:52/255.0 green:170/255.0 blue:220/255.0 alpha:1];
                                if (circles.count == 0) {
                                    circle.backgroundColor = [UIColor redColor];
                                }
                                UIView *view = [[UIView alloc] initWithFrame:CGRectMake(((float)horizontalStartLimit/w) * self.view.frame.size.width, ((float)verticalStartLimit/h) * self.view.frame.size.height, ((float)(horizontalEndLimit - horizontalStartLimit)/w) *  self.view.frame.size.width, ((float)(verticalEndLimit - verticalStartLimit)/h) * self.view.frame.size.height)];
                                view.backgroundColor = [UIColor colorWithWhite:.2 alpha:.5];
                                [circles addObject:view];
                                
                                [circles addObject:circle];
                                x = 0; y += 20;
                            }
                            
                            
                            offset +=2;
                            data[offset] = 52;
                            data[offset + 1] = 170;
                            data[offset + 2] = 220;
                            data[offset + 3] = 255;
                        }
                    }
                }
                
                
            }
            CGContextRotateCTM (c, radians(-90));
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            
            UIGraphicsEndImageContext();
            
            UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
            imageView.image = img;
            [self.view addSubview:imageView];
            for (UIView *circle in circles) {
                [self.view addSubview:circle];
            }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
         }

        
    }
    
    if (connection == videoConnection) {
        if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
//        if (hasOverlay && NO) {
//            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
//            [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@22.0f forKey:@"inputRadius"];
//            image = [filter valueForKey:kCIOutputImageKey];
//        }
        CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
        image = [image imageByApplyingTransform:transform];
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [coreImageContext drawImage:image inRect:CGRectMake(0, 0, screenSize.width*2, screenSize.height*2) fromRect:CGRectMake(0, -1280, 720, 1280)];
            [self.context presentRenderbuffer:GL_RENDERBUFFER];
        });
    }

}

#pragma mark - SCSitesViewControllerDelegate

- (void)goToCamera {
    [UIView animateWithDuration:.5 animations:^{
        _overlayView.alpha = 0;
    }completion:^(BOOL isCompleted){
        
    }];
}
@end
