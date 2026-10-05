import Foundation
#if SWIFT_PACKAGE
import ogg_opus_player_c
#endif

class OggOpusReader {
    
    enum Error: Swift.Error {
        case memoryAllocation
        case openFile(Int32)
        case read(Int32)
        case seek(Int32)
    }
    
    private(set) var didReachEnd = false
    
    private let file: OpaquePointer
    
    init(fileAtPath path: String) throws {
        var result: Int32 = 0
        let file = path.withCString { (cPath) -> OpaquePointer? in
            op_open_file(cPath, &result)
        }
        if result == 0, let file = file {
            self.file = file
        } else {
            throw Error.openFile(result)
        }
    }
    
    deinit {
        op_free(file)
    }
    
    var duration: Double {
        Double(max(0, op_pcm_total(file, -1))) / 48000
    }

    func seek(to seconds: Double) throws -> Double {
        let totalSamples = max(0, op_pcm_total(file, -1))
        let sample = min(totalSamples, Int64(max(0, min(seconds, duration)) * 48000))
        let result = op_pcm_seek(file, sample)
        guard result == 0 else { throw Error.seek(result) }
        didReachEnd = false
        return Double(sample) / 48000
    }

    func pcmData(maxLength: Int32) throws -> Data {
        guard let buffer = malloc(Int(maxLength)) else {
            throw Error.memoryAllocation
        }
        defer {
            free(buffer)
        }
        
        let output = buffer.assumingMemoryBound(to: opus_int16.self)
        let outputLength = maxLength / 2
        var remainingOutputLength = outputLength
        
        var result: Int32 = 1
        while (result == OP_HOLE || result > 0) && remainingOutputLength > 0 {
            let position = output.advanced(by: Int(outputLength - remainingOutputLength))
            result = op_read(file, position, remainingOutputLength, nil)
            remainingOutputLength -= result
        }
        
        if result < 0 {
            throw Error.read(result)
        } else {
            let count = Int(outputLength - remainingOutputLength) * 2
            if count == 0 {
                didReachEnd = true
                return Data()
            } else {
                return Data(bytes: buffer, count: count)
            }
        }
    }
    
}
