# FSVideoView - UI element support easy video playback.
Use a video as a background is more commonly
on many app nowadays .There are many different solutions,
some may use gif and some may use video.For video,
some choose to play directly through AVPlayerlayer,
but we chose GLKView because it's more flexible,
both on functionality and performance. It cost
a little bit more cpu than AVPlayer but it's fun
to have many interesting effect by code.

**We now support loop. You can add the videos to play, we will loop them as default.

**We don't support sound. ( May be in the coming future we see a need)**


Also we allow you to add simple filter to the
video at real time.Because the video is finally
render by an CIImage object, you just have to 
handle the CIImage as usually like adding an 
filter to it, chain them up...

        let videoView = FSVideoView(frame: view.bounds)
        var controlFlag  = 0
        videoView.filter = { image -> CIImage in
            controlFlag++
            if controlFlag % 10 > 5 {
                let filter = CIFilter(name: "CIColorInvert", withInputParameters: ["inputImage":image])!
                return filter.outputImage!
            }
            let filter = CIFilter(name: "CIColorClamp", withInputParameters: ["inputImage":image,"inputMinComponents":CIVector(CGRect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0)),"inputMaxComponents":CIVector(CGRect: CGRectMake(0.5, 0.7, 0.9, 1))])!
            return filter.outputImage!
        }
        view.addSubview(videoView)
        view.sendSubviewToBack(videoView)
        do {
            try videoView.playVideos([path,path2],fps: 25,loop: true)
            videoView.play()
        }catch _ {
            
        }

Have fun!

***Help us to improve this element if it will be fun for you.***
