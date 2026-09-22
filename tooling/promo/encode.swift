import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

func run() throws {
    let args = CommandLine.arguments
    guard args.count == 7 else { fatalError("encode FRAMES OUTPUT WIDTH HEIGHT FPS AUDIO") }
    let folder=args[1], output=URL(fileURLWithPath:args[2])
    let width=Int(args[3])!, height=Int(args[4])!, fps=Int32(args[5])!
    let silent=output.deletingPathExtension().appendingPathExtension("silent.mp4")
    for url in [silent,output] { if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } }
    let frames=try FileManager.default.contentsOfDirectory(atPath:folder).filter{$0.hasSuffix(".jpg")}.sorted()
    guard frames.count == 22 * Int(fps) else { fatalError("Expected a complete 22-second sequence, got \(frames.count)") }
    let writer=try AVAssetWriter(outputURL:silent,fileType:.mp4)
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:8_000_000,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,AVVideoExpectedSourceFrameRateKey:Int(fps)]])
    let adapter=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
    writer.add(input);guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime:.zero)
    for (i,name) in frames.enumerated() {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error! }
            Thread.sleep(forTimeInterval:0.002)
        }
        try autoreleasepool {
            let url=URL(fileURLWithPath:folder).appendingPathComponent(name)
            guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { fatalError("Bad frame \(name)") }
            var pixel:CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil,adapter.pixelBufferPool!,&pixel)==kCVReturnSuccess,let buffer=pixel else { fatalError("Cannot allocate frame") }
            CVPixelBufferLockBaseAddress(buffer,[])
            let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            CVPixelBufferUnlockBaseAddress(buffer,[])
            if !adapter.append(buffer,withPresentationTime:CMTime(value:Int64(i),timescale:fps)) { throw writer.error! }
        }
        if i % 150 == 0 { print("Encoded \(i)/\(frames.count)") }
    }
    input.markAsFinished();let complete=DispatchSemaphore(value:0)
    writer.finishWriting { complete.signal() };complete.wait()
    guard writer.status == .completed else { throw writer.error! }
    let composition=AVMutableComposition()
    let video=AVURLAsset(url:silent), audio=AVURLAsset(url:URL(fileURLWithPath:args[6]))
    let duration=CMTime(value:Int64(frames.count),timescale:fps)
    let videoTrack=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!
    try videoTrack.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:video.tracks(withMediaType:.video)[0],at:.zero)
    let audioTrack=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!
    try audioTrack.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:audio.tracks(withMediaType:.audio)[0],at:.zero)
    let export=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
    export.outputURL=output;export.outputFileType = .mp4;export.shouldOptimizeForNetworkUse=true
    let done=DispatchSemaphore(value:0);export.exportAsynchronously{done.signal()};done.wait()
    guard export.status == .completed else { throw export.error! }
    let result=AVURLAsset(url:output)
    print("Exported \(output.path): \(CMTimeGetSeconds(result.duration))s; \(result.tracks(withMediaType:.video).count) video / \(result.tracks(withMediaType:.audio).count) audio tracks")
    try FileManager.default.removeItem(at:silent)
}
do { try run() } catch { fputs("\(error)\n",stderr);exit(1) }
