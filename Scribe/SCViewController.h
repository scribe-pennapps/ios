//
//  SCViewController.h
//  Scribe
//
//  Created by Michael Scaria on 2/14/14.
//  Copyright (c) 2014 MichaelScaria. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

#import "SCSitesViewController.h"


@interface SCViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, SCSitesViewControllerDelegate> {
    AVCaptureSession *avCaptureSession;
    CIContext *coreImageContext;
    CIImage *maskImage;
    CGSize screenSize;
    CGContextRef cgContext;
    GLuint _renderBuffer;
    
    AVCaptureConnection *videoConnection;
    AVCaptureDeviceInput *videoIn;
    
    SCSitesViewController *svc;
    CAShapeLayer *focusGrid;
    BOOL takePicture;
}

@property (nonatomic, strong) AVCaptureDevice *device;
@property (strong, nonatomic) EAGLContext *context;

@property (strong, nonatomic) IBOutlet GLKView *cameraPreviewView;
@property (strong, nonatomic) IBOutlet UIView *overlayView;
@end
