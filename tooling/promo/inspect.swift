import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let asset=AVURLAsset(url:url)
let videos=asset.tracks(withMediaType:.video),audios=asset.tracks(withMediaType:.audio)
guard videos.count==1,audios.count==1,abs(CMTimeGetSeconds(asset.duration)-22)<0.1 else{fatalError("Invalid tracks or duration")}
let video=videos[0]
let reader=try AVAssetReader(asset:asset)
let output=AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
reader.add(output);reader.startReading()
var count=0
while let sample=output.copyNextSampleBuffer(){guard CMSampleBufferGetImageBuffer(sample) != nil else{fatalError("Missing decoded image")};count += 1}
guard reader.status == .completed,count==660 else{fatalError("Decode failed or incomplete: \(count)")}
let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
for t in [1.5,6.0,10.5,15.1,19.2]{
 let image=try generator.copyCGImage(at:CMTime(seconds:t,preferredTimescale:30),actualTime:nil)
 let target=url.deletingPathExtension().appendingPathExtension("check-\(t).jpg")
 let dest=CGImageDestinationCreateWithURL(target as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{fatalError("Cannot export decoded sample")}
}
let audioReader=try AVAssetReader(asset:asset)
let audio=AVAssetReaderTrackOutput(track:audios[0],outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false])
audioReader.add(audio);audioReader.startReading()
var nonzero=0,total=0
while let sample=audio.copyNextSampleBuffer(){
 guard let block=CMSampleBufferGetDataBuffer(sample) else{fatalError("Missing audio")}
 let bytes=CMBlockBufferGetDataLength(block);var data=Data(count:bytes)
 data.withUnsafeMutableBytes{buffer in _=CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:bytes,destination:buffer.baseAddress!)}
 data.withUnsafeBytes{buffer in for v in buffer.bindMemory(to:Int16.self){total += 1;if abs(Int(v))>100{nonzero += 1}}}
}
guard audioReader.status == .completed,nonzero>10000 else{fatalError("Missing or silent audio")}
print("PASS \(url.lastPathComponent): \(Int(video.naturalSize.width))×\(Int(video.naturalSize.height)), \(video.nominalFrameRate) fps, \(count) decoded frames, \(CMTimeGetSeconds(asset.duration))s, audible samples \(nonzero)/\(total)")
