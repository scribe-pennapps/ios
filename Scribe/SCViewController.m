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
    
    svc = [[SCSitesViewController alloc] init];
    svc = [self.storyboard instantiateViewControllerWithIdentifier:@"Sites"];
    [_overlayView addSubview:svc.view];
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

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (connection == videoConnection) {
        if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
//        if (hasOverlay && NO) {
            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
            [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@22.0f forKey:@"inputRadius"];
            image = [filter valueForKey:kCIOutputImageKey];
//        }
        CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
        image = [image imageByApplyingTransform:transform];
//        image = [image imageByApplyingTransform:CGAffineTransformTranslate(CGAffineTransformMakeScale(.665,  .665), 0, kCameraViewOffset*2.5)];
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [coreImageContext drawImage:image inRect:CGRectMake(0, 0, screenSize.width*2, screenSize.height*2) fromRect:CGRectMake(0, -1280, 720, 1280)];
            [self.context presentRenderbuffer:GL_RENDERBUFFER];
        });
    }
//    @synchronized(self)
//    {
//        if (paused) return;
//        if (discontinued)
//        {
//            if (isVideo) return;
//            NSLog(@"IN _DISCNT");
//            discontinued = NO;
//            // calc adjustment
//            CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//            CMTime last = isVideo ? _lastVideo : _lastAudio;
//            if (last.flags & kCMTimeFlags_Valid)
//            {
//                if (_timeOffset.flags & kCMTimeFlags_Valid)
//                {
//                    pts = CMTimeSubtract(pts, _timeOffset);
//                }
//                CMTime offset = CMTimeSubtract(pts, last);
//                NSLog(@"Setting offset from %s", isVideo ? "video": "audio");
//                NSLog(@"Adding %f to %f (pts %f)", ((double)offset.value)/offset.timescale, ((double)_timeOffset.value)/_timeOffset.timescale, ((double)pts.value/pts.timescale));
//                
//                // this stops us having to set a scale for _timeOffset before we see the first video time
//                if (_timeOffset.value == 0)
//                {
//                    _timeOffset = offset;
//                }
//                else
//                {
//                    _timeOffset = CMTimeAdd(_timeOffset, offset);
//                }
//            }
//            _lastVideo.flags = 0;
//            _lastAudio.flags = 0;
//        }
//        CFRetain(sampleBuffer);
//        CFRetain(formatDescription);
//        
//        if (_timeOffset.value > 0)
//        {
//            CFRelease(sampleBuffer);
//            sampleBuffer = [self adjustTime:sampleBuffer by:_timeOffset];
//        }
//        
//        // record most recent time so we know the length of the pause
//        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//        CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
//        if (dur.value > 0) pts = CMTimeAdd(pts, dur);
//        if (isVideo) _lastVideo = pts;
//        else  _lastAudio = pts;
//        
//        
//        dispatch_async(movieWritingQueue, ^{
//            
//            if ( assetWriter ) {
//                
//                BOOL wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo);
//                
//                if (connection == videoConnection) {
//                    
//                    // Initialize the video input if this is not done yet
//                    if (!readyToRecordVideo)
//                        readyToRecordVideo = [self setupAssetWriterVideoInput:formatDescription];
//                    
//                    // Write video data to file
//                    if (readyToRecordVideo && readyToRecordAudio)
//                        [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeVideo];
//                }
//                else if (connection == audioConnection) {
//                    
//                    // Initialize the audio input if this is not done yet
//                    if (!readyToRecordAudio)
//                        readyToRecordAudio = [self setupAssetWriterAudioInput:formatDescription];
//                    
//                    // Write audio data to file
//                    if (readyToRecordAudio && readyToRecordVideo)
//                        [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeAudio];
//                }
//                
//                BOOL isReadyToRecord = (readyToRecordAudio && readyToRecordVideo);
//                if ( !wasReadyToRecord && isReadyToRecord ) {
//                    recordingWillBeStarted = NO;
//                    self.recording = YES;
//                }
//            }
//            CFRelease(sampleBuffer);
//            CFRelease(formatDescription);
//        });
//    }
}


@end
