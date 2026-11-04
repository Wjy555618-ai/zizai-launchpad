#!/usr/bin/env swift
import Foundation

struct SeededNoise {
    private var state: UInt64 = 0xA11C_E55A_7A5A_2026

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state & 0xFFFF_FFFF) / Double(UInt32.max) * 2 - 1
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var encoded = value.littleEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：generate_removal_sound.swift 输出.wav\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let sampleRate = 48_000
let channelCount = 2
let duration = 0.50
let frameCount = Int(Double(sampleRate) * duration)
let bytesPerSample = MemoryLayout<Int16>.size
let dataSize = frameCount * channelCount * bytesPerSample

var wav = Data(capacity: 44 + dataSize)
wav.append(contentsOf: Data("RIFF".utf8))
wav.appendLittleEndian(UInt32(36 + dataSize))
wav.append(contentsOf: Data("WAVEfmt ".utf8))
wav.appendLittleEndian(UInt32(16))
wav.appendLittleEndian(UInt16(1))
wav.appendLittleEndian(UInt16(channelCount))
wav.appendLittleEndian(UInt32(sampleRate))
wav.appendLittleEndian(UInt32(sampleRate * channelCount * bytesPerSample))
wav.appendLittleEndian(UInt16(channelCount * bytesPerSample))
wav.appendLittleEndian(UInt16(16))
wav.append(contentsOf: Data("data".utf8))
wav.appendLittleEndian(UInt32(dataSize))

var leftNoise = SeededNoise()
var rightNoise = SeededNoise()
_ = rightNoise.next()
var leftLowPass = 0.0
var rightLowPass = 0.0

for frame in 0..<frameCount {
    let time = Double(frame) / Double(sampleRate)
    let progress = time / duration
    let attack = min(1, time / 0.018)
    let release = max(0, min(1, (duration - time) / 0.055))
    let envelope = sin(attack * .pi / 2) * exp(-3.15 * progress) * release

    let leftRaw = leftNoise.next()
    let rightRaw = rightNoise.next()
    let smoothing = 0.16 - progress * 0.09
    leftLowPass += smoothing * (leftRaw - leftLowPass)
    rightLowPass += smoothing * (rightRaw - rightLowPass)

    let toneStart = max(0, time - 0.045)
    let toneEnvelope = min(1, toneStart / 0.025) * exp(-8.2 * toneStart)
    let toneFrequency = 175 - 65 * progress
    let settleTone = sin(2 * .pi * toneFrequency * toneStart) * toneEnvelope

    let shimmer =
        sin(2 * .pi * (780 - 430 * progress) * time)
        * exp(-6.8 * progress)
        * min(1, time / 0.012)
    let left = leftLowPass * envelope * 0.42 + settleTone * 0.12 + shimmer * 0.025
    let right = rightLowPass * envelope * 0.42 + settleTone * 0.12 - shimmer * 0.025

    for sample in [left, right] {
        let clamped = max(-0.82, min(0.82, sample))
        wav.appendLittleEndian(Int16(clamped * Double(Int16.max)))
    }
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try wav.write(to: outputURL, options: .atomic)
