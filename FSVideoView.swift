//
//  FSVideoView.swift
//
//  Copyright (c) <2015> <Matthew Lui>
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software
//  is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit
import AVFoundation
import MobileCoreServices
import GLKit

/// FSVideoView using an underlay GLKView to draw each frame of the
/// video by rendering of CIContext from an CIImage. We only aspect a simple
/// video play back for special use, so we don't provide the audio play back
/// right now. Because we render the video through CIImage, we also provide
/// a filter parameter that let you to put some effect if you like.
public class FSVideoView:UIView{
    
    public  var filter      : (CIImage -> CIImage)?
    
    private let glContext   = EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
    private var completion  : ((Bool)->())?
    /// Loop the videos from input sources
    private var loop        = false
    private var pauseFlag   = true
    private var videoUrls   = [NSURL]()
    private var fps         : Int64 = 25
    
    private lazy var glView : GLKView = {
        GLKView(frame: self.bounds, context: self.glContext)
    }()
    
    private lazy var rendererContext:CIContext = {
        CIContext(EAGLContext: self.glContext)
    }()
    
    override public func didMoveToSuperview() {
        glView.bindDrawable()
        addSubview(glView)
    }
    
    public func playVideos(urls:[NSURL],fps:Int64 = 24,loop:Bool = false, completion:((Bool)->())? = nil)throws{
        self.loop = loop
        self.fps  = fps
        if !loop {
            self.completion = completion
        }
        videoUrls.removeAll()
        videoUrls.appendContentsOf(urls)
    }
    
    private func playVideosInUrls(){
        func playUrlAtIndex(index:Int){
            if videoUrls.count <= 0 {
                return
            }
            if index <= videoUrls.count - 1{
                do {
                    try _playVideo(videoUrls[index], completion: { (f) -> () in
                        if f {
                            playUrlAtIndex(index + 1)
                        }
                    })
                }catch let err{
                    print("FSVideoBackgroundView: Error occur when try to play file at index:\(index)")
                }
            }else{
                if loop {
                    playUrlAtIndex(0)
                }else{
                    completion?(true)
                }
            }
        }
        playUrlAtIndex(0)
    }
    
    /// Don't set fps higher than 25 since it's meaningless and will take away
    /// the help of increase performance.
    /// completion will only execute when video mode is not loop.
    public func playVideo(of url:NSURL,fps:Int64 = 24,loop:Bool = false,completion:((Bool)->())? = nil)throws{
        self.loop = loop
        self.fps  = fps
        self.completion = completion
        videoUrls.removeAll()
        videoUrls.append(url)
    }
    
    public func play(){
        playVideosInUrls()
    }
    
    public func pause(){
        pauseFlag = true
    }
    
    internal func _playVideo(url:NSURL,completion:((Bool)->())? = nil) throws{
        //load an asset to play from url
        let asset       = AVAsset(URL: url)
        // loading up the first track from an video file
        let track       = asset.tracksWithMediaType(AVMediaTypeVideo)[0]
        let reader:AVAssetReader
        do{
            reader      = try AVAssetReader(asset: asset)
        }catch let err{
            print("Error Located in FSVideoBackgroundView")
            completion?(false)
            throw err
        }
        
        let setting     = [kCVPixelBufferPixelFormatTypeKey as String:
                            NSNumber(unsignedInt: kCVPixelFormatType_32BGRA)]
        let output      = AVAssetReaderTrackOutput(track: track,
                                          outputSettings: setting)
        reader.addOutput(output)
        // If output catch sample buffer before start reading, will raise an
        // exception
        reader.startReading()
        
        //FIXME: add 5 fps to tempory fix the latency inssus, will be fix soon
        let deltaPerFrame = UInt64((1 / Double(fps)) * 1000000000)
        let drawBounds  = CGRect(x: 0, y: 0, width: glView.drawableWidth, height: glView.drawableHeight)
        
        let renderQueue = dispatch_queue_create("com.FSVideoView.renderQueue", DISPATCH_QUEUE_SERIAL)
        let dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, renderQueue)
        dispatch_source_set_timer(dispatch_source, DISPATCH_TIME_NOW, deltaPerFrame, 0)
        // Prepare resources to reduce alloc in realtime
        let drawingWidth    = glView.drawableWidth
        let drawingHeight   = glView.drawableHeight
        let drawingBounds   = CGRect(x: 0, y: 0, width: drawingWidth, height: drawingHeight)
        let viewAR          = drawingBounds.width / drawingBounds.height
        let renderBlock = dispatch_block_create(DISPATCH_BLOCK_BARRIER, { [unowned self, glView = self.glView] () -> Void in
            // Return flase only when output buffer is nil because an absense
            // of imageBuffer may due to the current frame is empty.
            if reader.canAddOutput(output){
                reader.addOutput(output)
            }
            guard let buffer = output.copyNextSampleBuffer() else{
                dispatch_source_cancel(dispatch_source)
                if reader.status == .Completed{
                    completion?(true)
                }else{
                    completion?(false)
                }
                return
            }
            
            guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else{
                return
            }
            
            // For supporting iOS8 and it didn't support initial CIImage
            // with CVImageBuffer yet, we have to do it manually by converting
            // an CVImageBuffer to CVPixelBuffer.
            let opaque = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer).toOpaque()
            let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaque).takeUnretainedValue()

            var image = CIImage(CVPixelBuffer: pixelBuffer)
            // Calculating Draw Rect
            if let filter = self.filter {
                image = filter(image)
            }

            var drawFrame       = image.extent
            let imageAR         = drawFrame.width / drawFrame.height
            
            if imageAR < viewAR {
                let finalHeight = imageAR / viewAR * drawFrame.height
                let finalY = (drawFrame.height - finalHeight) / 2
                drawFrame.size.height = finalHeight
                drawFrame.origin.y = finalY
            }else{
                let finalWidth = imageAR / viewAR * drawFrame.width
                let finalX = (drawFrame.width - finalWidth) / 2
                drawFrame.size.width = finalWidth
                drawFrame.origin.x = finalX
            }
            
            if glView.context != EAGLContext.currentContext(){
                EAGLContext.setCurrentContext(self.glView.context)
            }
            
            glView.bindDrawable()
            glClearColor(0.5, 0.5, 0.5, 1)
            glClear(0x00000000) // make it long so easy to see
            glEnable(UInt32(GL_BLEND)) // constant value of 0x0BE2
            glBlendFunc(0x1, UInt32(GL_ONE_MINUS_SRC_ALPHA))
            self.rendererContext.drawImage(image, inRect: drawBounds, fromRect: drawFrame)
            glView.display()
            
            })
        

        dispatch_source_set_event_handler(dispatch_source, renderBlock)
        dispatch_resume(dispatch_source)

    }
}

