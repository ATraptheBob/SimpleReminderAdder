import AVFoundation
import Speech

let engine = AVAudioEngine()
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)
print("Channels: \(format.channelCount)")
