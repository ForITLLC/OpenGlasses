import XCTest
import AVFoundation
@testable import OpenGlasses

/// The acknowledgment, end-listening and disconnect tones are the user's only
/// confirmation that the glasses heard them — there is no screen in their line of
/// sight. Both tones are synthesised as in-memory WAV data by pure static functions,
/// so they are fully testable on a simulator with no audio hardware.
///
/// This failure mode is SILENT. If a header field drifts, `AVAudioPlayer(data:)`
/// throws, `playTone` swallows the error into a system sound and `playDisconnectTone`
/// falls back to a single note — the app keeps working, the tone is just wrong or
/// missing, and nothing else in the suite notices. Hence the emphasis on asserting
/// that AVAudioPlayer can genuinely parse these bytes, not merely that they look
/// well-formed to us.
///
/// Layout of the 44-byte canonical WAV header these functions emit:
///   0  RIFF   4  fileSize   8  WAVE   12 "fmt "  16 chunkSize(16)
///   20 format 22 channels   24 sampleRate        28 byteRate
///   32 blockAlign           34 bitsPerSample     36 "data"  40 dataSize  44 samples…
@MainActor
final class AudioToneGenerationTests: XCTestCase {

    private static let sampleRate = 44100.0
    private static let headerBytes = 44

    // MARK: - Header helpers

    private func ascii(_ data: Data, at offset: Int, length: Int = 4) -> String {
        String(decoding: data[offset..<(offset + length)], as: UTF8.self)
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<(offset + 2)].reversed().reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    /// The PCM payload, decoded back into signed 16-bit samples.
    private func samples(_ data: Data) -> [Int16] {
        stride(from: Self.headerBytes, to: data.count, by: 2).map { i in
            Int16(bitPattern: UInt16(data[i]) | (UInt16(data[i + 1]) << 8))
        }
    }

    /// Every assertion that must hold for ANY tone this app generates, regardless of
    /// frequency or length. Both generators are checked against it.
    private func assertCanonicalWAVHeader(_ data: Data,
                                          expectedSamples: Int,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
        XCTAssertEqual(ascii(data, at: 0), "RIFF", "missing RIFF magic", file: file, line: line)
        XCTAssertEqual(ascii(data, at: 8), "WAVE", "missing WAVE magic", file: file, line: line)
        XCTAssertEqual(ascii(data, at: 12), "fmt ", "missing fmt chunk", file: file, line: line)
        XCTAssertEqual(ascii(data, at: 36), "data", "missing data chunk", file: file, line: line)

        XCTAssertEqual(uint32(data, at: 16), 16, "fmt chunk size must be 16 for PCM", file: file, line: line)
        XCTAssertEqual(uint16(data, at: 20), 1, "audio format must be 1 (uncompressed PCM)", file: file, line: line)
        XCTAssertEqual(uint16(data, at: 22), 1, "tones are mono", file: file, line: line)
        XCTAssertEqual(uint32(data, at: 24), 44100, "sample rate", file: file, line: line)
        XCTAssertEqual(uint16(data, at: 34), 16, "bits per sample", file: file, line: line)

        // These three are derived values. Getting one wrong is the classic way to
        // produce a file that looks fine but plays at the wrong speed or not at all.
        XCTAssertEqual(uint16(data, at: 32), 2,
                       "block align must be channels * bytesPerSample = 2", file: file, line: line)
        XCTAssertEqual(uint32(data, at: 28), 88200,
                       "byte rate must be sampleRate * blockAlign", file: file, line: line)

        let declaredDataSize = uint32(data, at: 40)
        XCTAssertEqual(Int(declaredDataSize), expectedSamples * 2,
                       "declared data size must match the sample count", file: file, line: line)
        XCTAssertEqual(data.count, Self.headerBytes + Int(declaredDataSize),
                       "declared data size must match the bytes actually present", file: file, line: line)
        XCTAssertEqual(Int(uint32(data, at: 4)), data.count - 8,
                       "RIFF file size counts every byte after the first 8", file: file, line: line)
    }

    // MARK: - Single tone

    func testAcknowledgmentToneHasCanonicalWAVHeader() throws {
        // The parameters playAcknowledgmentTone() actually ships.
        let data = try TextToSpeechService.generateToneData(
            frequency: 880, duration: 0.15, sampleRate: Self.sampleRate)
        assertCanonicalWAVHeader(data, expectedSamples: Int(Self.sampleRate * 0.15))
    }

    func testEndListeningToneHasCanonicalWAVHeader() throws {
        let data = try TextToSpeechService.generateToneData(
            frequency: 440, duration: 0.12, sampleRate: Self.sampleRate)
        assertCanonicalWAVHeader(data, expectedSamples: Int(Self.sampleRate * 0.12))
    }

    func testToneLengthFollowsRequestedDuration() throws {
        let data = try TextToSpeechService.generateToneData(
            frequency: 880, duration: 0.15, sampleRate: Self.sampleRate)
        XCTAssertEqual(samples(data).count, 6615, "44100 * 0.15")
    }

    /// The real contract. Everything above checks our own arithmetic; this checks the
    /// thing production actually depends on — that AVAudioPlayer accepts the bytes.
    func testAcknowledgmentToneIsPlayableByAVAudioPlayer() throws {
        let data = try TextToSpeechService.generateToneData(
            frequency: 880, duration: 0.15, sampleRate: Self.sampleRate)
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.15, accuracy: 0.01)
        XCTAssertEqual(player.numberOfChannels, 1)
    }

    /// The envelope exists to stop the speaker clicking when the tone starts. A tone
    /// that begins at full amplitude is audibly wrong but still a perfectly valid WAV,
    /// so no header assertion would catch its loss.
    func testToneFadesInFromSilenceToAvoidAClick() throws {
        let data = try TextToSpeechService.generateToneData(
            frequency: 880, duration: 0.15, sampleRate: Self.sampleRate)
        let pcm = samples(data)

        XCTAssertEqual(pcm[0], 0, "the first sample must be silent")
        let fadeInSamples = Int(Self.sampleRate * 0.01)  // 10ms fade
        XCTAssertLessThan(abs(Int(pcm[1])), abs(Int(pcm[fadeInSamples / 2])),
                          "amplitude must ramp up across the fade")
    }

    /// Amplitude is scaled by 0.8 before conversion to Int16. If that headroom were
    /// removed the samples would clip and the tone would buzz.
    func testToneStaysWithinItsAmplitudeHeadroom() throws {
        let data = try TextToSpeechService.generateToneData(
            frequency: 880, duration: 0.15, sampleRate: Self.sampleRate)
        let ceiling = Int(0.8 * Double(Int16.max)) + 1
        let loudest = samples(data).map { abs(Int($0)) }.max() ?? 0

        XCTAssertLessThanOrEqual(loudest, ceiling, "tone clips — 0.8 headroom lost")
        XCTAssertGreaterThan(loudest, ceiling / 2, "tone is far too quiet to hear")
    }

    // MARK: - Descending disconnect tone

    func testDescendingToneHasCanonicalWAVHeader() throws {
        let data = try TextToSpeechService.generateDescendingToneData(sampleRate: Self.sampleRate)
        // note (0.1s) + gap (0.04s) + note (0.1s)
        assertCanonicalWAVHeader(data, expectedSamples: 4410 + 1764 + 4410)
    }

    func testDescendingToneIsPlayableByAVAudioPlayer() throws {
        let data = try TextToSpeechService.generateDescendingToneData(sampleRate: Self.sampleRate)
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.24, accuracy: 0.01, "0.1 + 0.04 + 0.1")
    }

    /// Two notes with an audible break between them, not one smeared 0.24s tone.
    func testDescendingToneHasASilentGapBetweenTheTwoNotes() throws {
        let data = try TextToSpeechService.generateDescendingToneData(sampleRate: Self.sampleRate)
        let pcm = samples(data)
        let gap = pcm[4410..<(4410 + 1764)]

        XCTAssertTrue(gap.allSatisfy { $0 == 0 }, "the gap between notes must be silent")
        XCTAssertTrue(pcm[0..<4410].contains { $0 != 0 }, "first note must carry audio")
        XCTAssertTrue(pcm[(4410 + 1764)...].contains { $0 != 0 }, "second note must carry audio")
    }
}
