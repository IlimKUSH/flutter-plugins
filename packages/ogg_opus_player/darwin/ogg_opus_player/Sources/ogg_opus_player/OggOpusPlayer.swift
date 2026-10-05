import AVFoundation
import Foundation

fileprivate let audioQueueBufferSize: Int32 = 11520 // Should be smaller than AudioQueueBufferRef.mAudioDataByteSize

final class OggOpusPlayer {
  enum Error: Swift.Error {
    case newOutput
    case allocateBuffers
    case addPropertyListener
    case stop
    case cancelled
    case reset
  }

  enum Status: Int {
    case stopped = 0
    case playing
    case paused
  }

  var onStatusChanged: ((OggOpusPlayer) -> Void)?

  var currentTime: Float64 {
    assert(Queue.main.isCurrent)
    var timeStamp = AudioTimeStamp()
    let status = AudioQueueGetCurrentTime(audioQueue, nil, &timeStamp, nil)
    if status == noErr {
      return positionOffset + max(0, timeStamp.mSampleTime - queueSampleOrigin) / sampleRate
    } else {
      return positionOffset
    }
  }

  var playRate: Float = 1.0 {
    didSet {
      assert(Queue.main.isCurrent)
      if playRate < 0.5 {
        playRate = 0.5
      }
      if playRate > 2 {
        playRate = 2.0
      }
      AudioQueueSetParameter(audioQueue, kAudioQueueParam_PlayRate, playRate)
    }
  }

  fileprivate let reader: OggOpusReader

  @Synchronized(value: .stopped)
  fileprivate(set) var status: Status {
    didSet {
      self.onStatusChanged?(self)
    }
  }

  fileprivate var audioQueue: AudioQueueRef!

  private let sampleRate: Float64 = 48000
  private let numberOfBuffers = 3

  private var buffers = [AudioQueueBufferRef]()
  private var positionOffset: Double = 0
  private var queueSampleOrigin: Double = 0
  private var hasPrimedBuffers = false
  fileprivate var isResettingQueue = false

  private lazy var format: AudioStreamBasicDescription = {
    let mBitsPerChannel: UInt32 = 16
    let mChannelsPerFrame: UInt32 = 1
    let mBytesPerFrame = (mBitsPerChannel / 8) * mChannelsPerFrame
    let mFramesPerPacket: UInt32 = 1
    let mBytesPerPacket: UInt32 = mFramesPerPacket * mBytesPerFrame
    let format = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                             mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                             mBytesPerPacket: mBytesPerPacket,
                                             mFramesPerPacket: mFramesPerPacket,
                                             mBytesPerFrame: mBytesPerFrame,
                                             mChannelsPerFrame: mChannelsPerFrame,
                                             mBitsPerChannel: mBitsPerChannel,
                                             mReserved: 0)
    return format
  }()

  private var selfAsRawPointer: UnsafeMutableRawPointer {
    Unmanaged.passUnretained(self).toOpaque()
  }

  init(path: String) throws {
    reader = try OggOpusReader(fileAtPath: path)

    var status: OSStatus = noErr

    var audioQueue: AudioQueueRef!
    status = AudioQueueNewOutput(&format,
                                 bufferCallback,
                                 selfAsRawPointer,
                                 CFRunLoopGetMain(),
                                 CFRunLoopMode.commonModes.rawValue,
                                 0,
                                 &audioQueue)
    guard status == noErr, let audioQueue = audioQueue else {
      throw Error.newOutput
    }

    status = AudioQueueAddPropertyListener(audioQueue,
                                           kAudioQueueProperty_IsRunning,
                                           runningChangedCallback(_:_:_:),
                                           selfAsRawPointer)
    guard status == noErr else {
      throw Error.addPropertyListener
    }

    self.audioQueue = audioQueue

    buffers.reserveCapacity(numberOfBuffers)
    for _ in 0 ..< numberOfBuffers {
      var buffer: AudioQueueBufferRef!
      status = AudioQueueAllocateBuffer(audioQueue, UInt32(audioQueueBufferSize), &buffer)
      guard status == noErr else {
        dispose()
        throw Error.allocateBuffers
      }
      buffers.append(buffer)
    }

    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1)
    var enable: UInt32 = 1
    AudioQueueSetProperty(audioQueue, kAudioQueueProperty_EnableTimePitch, &enable,
                          UInt32(MemoryLayout.size(ofValue: enable)))
  }

  deinit {
    if status == .playing || status == .paused {
      stop()
    }
    dispose()
    #if DEBUG
      print("OggOpusPlayer \(Unmanaged<OggOpusPlayer>.passUnretained(self).toOpaque()) deinitialized")
    #endif
  }

  func play() {
    assert(Queue.main.isCurrent)
    guard status != .playing else { return }
    if currentTime >= reader.duration {
      status = .stopped
      return
    }
    status = .playing
    if !hasPrimedBuffers {
      hasPrimedBuffers = true
      for buffer in buffers {
        bufferCallback(inUserData: selfAsRawPointer, inAQ: audioQueue, inBuffer: buffer)
      }
    }
    AudioQueueStart(audioQueue, nil)
  }

  func seek(to seconds: Double) throws -> Double {
    assert(Queue.main.isCurrent)
    let wasPlaying = status == .playing
    isResettingQueue = true
    defer { isResettingQueue = false }
    guard AudioQueueStop(audioQueue, true) == noErr,
          AudioQueueReset(audioQueue) == noErr else { throw Error.reset }
    hasPrimedBuffers = false
    positionOffset = try reader.seek(to: seconds)
    var timestamp = AudioTimeStamp()
    queueSampleOrigin = AudioQueueGetCurrentTime(audioQueue, nil, &timestamp, nil) == noErr
      ? timestamp.mSampleTime : 0
    status = .paused
    if wasPlaying { play() }
    return positionOffset
  }

  func pause() {
    assert(Queue.main.isCurrent)
    guard status == .playing else {
      return
    }
    AudioQueuePause(audioQueue)
    status = .paused
  }

  func stop() {
    assert(Queue.main.isCurrent)
    guard status != .stopped else {
      return
    }
    AudioQueueStop(audioQueue, true)
    status = .stopped
  }

  func dispose() {
    assert(Queue.main.isCurrent)
    if let audioQueue = audioQueue {
      AudioQueueDispose(audioQueue, true)
    }
  }
}

fileprivate func bufferCallback(
  inUserData: UnsafeMutableRawPointer?,
  inAQ: AudioQueueRef,
  inBuffer: AudioQueueBufferRef
) {
  guard let ptr = inUserData else {
    return
  }
  let player = Unmanaged<OggOpusPlayer>.fromOpaque(ptr).takeUnretainedValue()
  guard player.status == .playing else {
    return
  }
  if let pcmData = try? player.reader.pcmData(maxLength: audioQueueBufferSize), pcmData.count > 0 {
    inBuffer.pointee.mAudioDataByteSize = UInt32(pcmData.count)
    pcmData.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: Data.Element.self),
                      count: pcmData.count)
    AudioQueueEnqueueBuffer(player.audioQueue, inBuffer, 0, nil)
  } else {
    AudioQueueStop(player.audioQueue, false)
  }
}

fileprivate func runningChangedCallback(
  _ inUserData: UnsafeMutableRawPointer?,
  _ inAQ: AudioQueueRef,
  _ inID: AudioQueuePropertyID
) {
  guard let ptr = inUserData else {
    return
  }
  let player = Unmanaged<OggOpusPlayer>.fromOpaque(ptr).takeUnretainedValue()
  guard !player.isResettingQueue else { return }
  var isRunning: UInt32 = 0
  var size = UInt32(MemoryLayout.size(ofValue: isRunning))
  guard AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &isRunning, &size) == noErr,
        isRunning == 0 else { return }
  if player.reader.didReachEnd {
    player.status = .stopped
  }
}
