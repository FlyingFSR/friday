import Foundation

/// 16-bit PCM WAV audio as Friday records it (AVAudioRecorder, 16 kHz mono), parsed into the float
/// samples the speech engine consumes.
struct PCM16Audio {
  let sampleRate: Int
  let samples: [Int16]

  var duration: Double {
    Double(samples.count) / Double(sampleRate)
  }

  init(sampleRate: Int, samples: [Int16]) {
    self.sampleRate = sampleRate
    self.samples = samples
  }

  /// Parses a RIFF/WAVE file by walking its chunks rather than assuming a fixed 44-byte header:
  /// AVAudioRecorder inserts extra chunks (such as `FLLR` padding) before `data`. Returns nil for
  /// anything other than mono 16-bit integer PCM.
  init?(wavData: Data) {
    let bytes = [UInt8](wavData)
    guard bytes.count >= 12,
          bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], // "RIFF"
          bytes[8..<12] == [0x57, 0x41, 0x56, 0x45] // "WAVE"
    else {
      return nil
    }

    func readUInt16(_ offset: Int) -> Int {
      Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }
    func readUInt32(_ offset: Int) -> Int {
      readUInt16(offset) | readUInt16(offset + 2) << 16
    }

    var offset = 12
    var format: (audioFormat: Int, channels: Int, sampleRate: Int, bitsPerSample: Int)?
    var dataRange: Range<Int>?

    while offset + 8 <= bytes.count {
      let chunkID = bytes[offset..<offset + 4]
      let chunkSize = readUInt32(offset + 4)
      let bodyStart = offset + 8
      let bodyEnd = min(bytes.count, bodyStart + chunkSize)

      if chunkID.elementsEqual("fmt ".utf8), chunkSize >= 16, bodyStart + 16 <= bytes.count {
        format = (
          readUInt16(bodyStart),
          readUInt16(bodyStart + 2),
          readUInt32(bodyStart + 4),
          readUInt16(bodyStart + 14)
        )
      } else if chunkID.elementsEqual("data".utf8) {
        // A recorder that was not finalized can leave a zero or oversized length; clamp to the file.
        dataRange = bodyStart..<bodyEnd
        break
      }

      // Chunks are padded to an even length.
      offset = bodyStart + chunkSize + (chunkSize & 1)
    }

    // Format 1 is integer PCM; 0xFFFE (WAVE_FORMAT_EXTENSIBLE) is also accepted because some
    // writers use it for plain 16-bit PCM.
    guard let format, let dataRange,
          format.audioFormat == 1 || format.audioFormat == 0xFFFE,
          format.channels == 1,
          format.bitsPerSample == 16,
          format.sampleRate > 0
    else {
      return nil
    }

    var samples = [Int16]()
    samples.reserveCapacity(dataRange.count / 2)
    var index = dataRange.lowerBound
    while index + 1 < dataRange.upperBound {
      samples.append(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8))
      index += 2
    }

    self.init(sampleRate: format.sampleRate, samples: samples)
  }

  /// Samples scaled to [-1, 1) by 1/32768, as the reference implementations do for int16.
  var floatSamples: [Float] {
    samples.map { Float($0) / 32768 }
  }
}
