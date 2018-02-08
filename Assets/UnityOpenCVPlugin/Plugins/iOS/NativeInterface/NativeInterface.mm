//
//  NativeInterface.mm
//
//
//  Created by Terry Liu on 2018/01/07.
//
//

#import <opencv2/opencv.hpp>
#import <UIKit/UIKit.h>

// OpenCV implementation part
@interface VideoCapture : NSObject
{
    int width;
    int height;
}
@end

@implementation VideoCapture
- (instancetype)initWithWidth:(int)w height:(int)h {
    self = [super self];
    if (self) {
        width = w;
        height = h;
    }
    return self;
}

- (void)dealloc {
   
}

- (void)updateWithWidth: (int) inputWidth height: (int) inputHeight input:(unsigned char*)inputData output:(unsigned char*)outputData {
    cv::Mat img(inputHeight, inputWidth, CV_8UC1, inputData);
    
    // Resized to specified size
    cv::Mat gray(height, width, img.type());
    cv::resize(img, gray, gray.size(), cv::INTER_AREA);
    
    // Convert to Unity's texture format (RGBA)
    cv::Mat argb;
    cv::cvtColor(gray, argb, CV_GRAY2RGBA);
    
    // Copy to buffer secured by Unity side
    memcpy(outputData, argb.data, argb.total() * argb.elemSize());
    //.data returns pointer to data of Mat
    //.total() returns total pixels
    //.eleSize() returns element size in bytes
    //memcpy(void* destination, const void* source, size_t num)
}
@end


// Declare functions to export to C#
extern "C" {
    void* allocateVideoCapture(int width, int height);
    void releaseVideoCapture(void* capture);
    void updateVideoCapture(void* capture, int width, int height, unsigned char* inputImage, unsigned char* outputImage);
}

// Generate objects
void* allocateVideoCapture(int width, int height) {
    VideoCapture* capture = [[VideoCapture alloc] initWithWidth:width height:height];
    return (__bridge_retained void*)capture;
}

// destroy object
void releaseVideoCapture(void* capture) {
    VideoCapture* cap = (__bridge_transfer VideoCapture*)capture;
    cap = nil;
}

// for calling every frame
void updateVideoCapture(void* capture, int width, int height, unsigned char* inputImage, unsigned char* outputImage) {
    VideoCapture* cap = (__bridge VideoCapture*)capture;
    [cap updateWithWidth:width height:height input:inputImage output:outputImage];
}

