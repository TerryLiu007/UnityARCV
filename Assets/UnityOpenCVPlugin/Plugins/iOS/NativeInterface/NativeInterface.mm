//
//  NativeInterface.mm
//
//
//  Created by Terry Liu on 2018/01/07.
//
//

#import <opencv2/opencv.hpp>
#import <opencv2/xfeatures2d.hpp>
#import <UIKit/UIKit.h>

using namespace cv;
using namespace cv::xfeatures2d;

enum mode {average, kalman, none};

// OpenCV interface
@interface videoCapture : NSObject
{
    int width;
    int height;
    int scaleFactor;
    Ptr<ORB> detector;
    std::vector<KeyPoint> keypoints_object;
    Mat descriptors_object;
    Mat img_object;
    enum mode smoothMode;
}
@end

// OpenCV implementation
@implementation videoCapture

// parameters for first approach
int totalNum = 3;
std::vector<Point2f> scene_centors(totalNum);
int counter = 0;

// parameters for second approach
KalmanFilter KF(4,2);
Mat_<float> measurement(2,1);

- (instancetype)initWithWidth:(int)w height:(int)h {
    // self = [super self];
    if (self) {
        width = w;
        height = h;
        scaleFactor = 3;
        detector = ORB::create();
        smoothMode = none;
        
        // Kalman Filter initialization
        KF.transitionMatrix = (Mat_<float>(4, 4) << 1,0,1,0, 0,1,0,1, 0,0,1,0, 0,0,0,1);
        measurement.setTo(Scalar(0));
        KF.statePre.at<float>(2) = 0;
        KF.statePre.at<float>(3) = 0;
        setIdentity(KF.measurementMatrix);
        setIdentity(KF.processNoiseCov, Scalar::all(1e-4));
        setIdentity(KF.measurementNoiseCov, Scalar::all(1e-1));
        setIdentity(KF.errorCovPost, Scalar::all(.1));
    }
    return self;
}


- (void)updateWithWidth: (int)inputWidth height: (int)inputHeight input: (unsigned char*)inputData output: (unsigned char*)outputData {
    Mat img(inputHeight, inputWidth, CV_8UC1, inputData);
    
    // Resized to specified size
    Mat gray((int)inputHeight/scaleFactor, (int)inputWidth/scaleFactor, img.type());
    resize(img, gray, gray.size(), cv::INTER_AREA);
    
    // Convert to Unity's texture format (RGBA)
    Mat argb;
    cvtColor(gray, argb, CV_GRAY2RGBA);
    
    // Copy to buffer secured by Unity side
    memcpy(outputData, argb.data, argb.total() * argb.elemSize());
    //.data returns pointer to data of Mat
    //.total() returns total pixels
    //.eleSize() returns element size in bytes
    //memcpy(void* destination, const void* source, size_t num)
}


- (void)recognizeImageWithWidth: (int)inputWidth height: (int)inputHeight stream: (unsigned char*)inputScene target: (unsigned char*)inputObject x_cord: (int*)x y_cord: (int*)y redetect: (BOOL)redetect output: (unsigned char*)outputData{
    
    Mat mat_scene(inputHeight, inputWidth, CV_8UC1, inputScene);
    
    // Resize input video frame to a smaller size
    Mat img_scene((int)inputHeight/scaleFactor, (int)inputWidth/scaleFactor, mat_scene.type());
    resize(mat_scene, img_scene, img_scene.size(), INTER_AREA);
    
    // Detect features of the object if needed
    if(redetect && inputObject)
    {
        Mat mat_object(height, width, CV_8UC4);
        memcpy(mat_object.data, inputObject, mat_object.total() * mat_object.elemSize());
        cvtColor(mat_object, mat_object, CV_RGBA2GRAY);
        flip(mat_object, img_object, 0);
        detector->detectAndCompute( img_object, Mat(), keypoints_object, descriptors_object );
    }
    
    if(!descriptors_object.data)
    {
        *x = 0;
        *y = 0;
        return;
    }
    
    std::vector<KeyPoint> keypoints_scene;
    Mat descriptors_scene;
    detector->detectAndCompute( img_scene, Mat(), keypoints_scene, descriptors_scene );
    
    if (keypoints_scene.size() < 12)
    {
        *x = 0;
        *y = 0;
        return;
    }
    
    //std::vector< DMatch > matches;
    std::vector< DMatch > good_matches;
    
    //Matching descriptor vectors using BF with crosscheck
    BFMatcher matcher(NORM_HAMMING, true);
    matcher.match( descriptors_object, descriptors_scene, good_matches );
    
    // Localize the object
    std::vector<Point2f> obj;
    std::vector<Point2f> scene;
    for( size_t i = 0; i < good_matches.size(); i++ )
    {
        // Get the keypoints from the good matches
        obj.push_back( keypoints_object[ good_matches[i].queryIdx ].pt );
        scene.push_back( keypoints_scene[ good_matches[i].trainIdx ].pt );
    }
    Mat H = findHomography( obj, scene, RANSAC, 6.0);
    
    // Get the corners from the object ( the object to be "detected" )
    std::vector<Point2f> obj_corners(4);
    obj_corners[0] = cvPoint(0,0);
    obj_corners[1] = cvPoint( img_object.cols, 0 );
    obj_corners[2] = cvPoint( img_object.cols, img_object.rows );
    obj_corners[3] = cvPoint( 0, img_object.rows );
    std::vector<Point2f> scene_corners(4);
    perspectiveTransform( obj_corners, scene_corners, H);
    
    if(isContourConvex(scene_corners) && 8*scaleFactor*scaleFactor*contourArea(scene_corners) > inputWidth*inputHeight){
        // pinpoint the centor
        std::vector<Point2f> obj_centor(1);
        obj_centor[0] = cvPoint( img_object.cols/2, img_object.rows/2 );
        std::vector<Point2f> scene_centor(1);
        perspectiveTransform(obj_centor, scene_centor, H);
        
        //**********FIRST APPROACH**********//
        if (smoothMode == average)
        {
            scene_centors[counter] = scene_centor[0];
            counter = counter + 1;
            if (counter > totalNum - 1){
                counter = 0;
            }

            float avg_x = 0;
            float avg_y = 0;

            for (int i = 0; i < totalNum; i++){
                avg_x += scene_centors[i].x;
            }

            for (int i = 0; i < totalNum; i++){
                avg_y += scene_centors[i].y;
            }

            *x = (int)(avg_x/totalNum);
            *y = 360-(int)(avg_y/totalNum);
        }
        
        //**********SECOND APPROACH**********//
        if (smoothMode == kalman)
        {
            if (counter == 0)
            {
                KF.statePre.at<float>(0) = scene_centor[0].x;
                KF.statePre.at<float>(1) = scene_centor[0].y;
                counter += 1;
            }
            
            // Kalman Filter
            Mat prediction = KF.predict();
            
            measurement(0) = scene_centor[0].x;
            measurement(1) = scene_centor[0].y;
            
            Mat estimated = KF.correct(measurement);
            *x = (int)(estimated.at<float>(0));
            *y = 360-(int)(estimated.at<float>(1));
        }
        
        if (smoothMode == none){
            *x = (int)scene_centor[0].x;
            *y = 360-(int)scene_centor[0].y;
        }
        
        // Draw lines between the corners ( the mapped object in the scene )
        line( img_scene, scene_corners[0], scene_corners[1], Scalar(255), 4 );
        line( img_scene, scene_corners[1], scene_corners[2], Scalar(255), 4 );
        line( img_scene, scene_corners[2], scene_corners[3], Scalar(255), 4 );
        line( img_scene, scene_corners[3], scene_corners[0], Scalar(255), 4 );
        
        // texture2D must match Unity texture2D dimension - 640*360
        Mat texture2D;
        cvtColor(img_scene, texture2D, CV_GRAY2RGBA);
        flip(texture2D, texture2D, 0);
        memcpy(outputData, texture2D.data, texture2D.total() * texture2D.elemSize());
        return;
        
    }else{
        *x = 0;
        *y = 0;
        return;
    }
}
@end



// Declare functions to export to C#
extern "C" {
    void* allocateVideoCapture(int width, int height);
    void releaseVideoCapture(void* capture);
    void updateVideoCapture(void* capture, int width, int height, unsigned char* inputImage, unsigned char* outputImage);
    void imageTrigger(void* capture, int inputWidth, int inputHeight, unsigned char* inputScene, unsigned char* inputObject, int* x, int* y, BOOL redetect, unsigned char* outputImage);
}

// Generate objects
void* allocateVideoCapture(int width, int height) {
    videoCapture* capture = [[videoCapture alloc] initWithWidth:width height:height];
    return (__bridge_retained void*)capture;
}

// destroy object
void releaseVideoCapture(void* capture) {
    videoCapture* cap = (__bridge_transfer videoCapture*)capture;
    cap = nil;
}

// for calling every frame
void updateVideoCapture(void* capture, int width, int height, unsigned char* inputImage, unsigned char* outputImage) {
    videoCapture* cap = (__bridge videoCapture*)capture;
    [cap updateWithWidth:width height:height input:inputImage output:outputImage];
}

// for image trigger mechanism
void imageTrigger(void* capture, int inputWidth, int inputHeight, unsigned char* inputScene, unsigned char* inputObject, int* x, int* y, BOOL redetect, unsigned char* outputImage) {
    videoCapture* cap = (__bridge videoCapture*)capture;
    [cap recognizeImageWithWidth:inputWidth height:inputHeight stream:inputScene target:inputObject x_cord:x y_cord:y redetect:redetect output:outputImage];
}

