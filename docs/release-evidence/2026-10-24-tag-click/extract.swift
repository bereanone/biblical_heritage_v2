import Foundation
import AVFoundation
let source = "/Users/deanbowen/Development/StudyBible2/assets/audio/qwen_bible/02_Exo_020.m4a"
let ranges: [(Int, Double, Double)] = [(8,44.179,46.84),(9,46.84,50.342),(10,50.342,65.369),(11,65.369,75.693)]
for (verse,start,end) in ranges {
  let file = try AVAudioFile(forReading: URL(fileURLWithPath: source))
  let output = try AVAudioFile(forWriting: URL(fileURLWithPath: "/tmp/studybible-tag-click-20261024/verse\(verse)-before.wav"), settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false], commonFormat: .pcmFormatFloat32, interleaved: false)
  let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4096)!
  file.framePosition=Int64(start*24000)
  while file.framePosition < Int64(end*24000) {
    try file.read(into:buffer,frameCount:AVAudioFrameCount(min(4096,Int64(end*24000)-file.framePosition)))
    try output.write(from:buffer)
  }
  print("Exported Exodus 20:\(verse)")
}
