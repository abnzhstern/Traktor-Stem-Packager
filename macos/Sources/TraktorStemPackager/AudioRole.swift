import Foundation
import SwiftUI

enum PackagingMode: String, CaseIterable, Identifiable {
    case portableAAC
    case nativeLossless

    var id: String { rawValue }
    var title: String {
        switch self {
        case .portableAAC: "AAC Stem File"
        case .nativeLossless: "Lossless Traktor Installation"
        }
    }
    var subtitle: String {
        switch self {
        case .portableAAC: "One shareable file • easiest workflow • 320 kbps AAC"
        case .nativeLossless: "Preserves source PCM • Installs directly into Traktor"
        }
    }
    var commandName: String {
        switch self {
        case .portableAAC: "portable-aac"
        case .nativeLossless: "native-alac"
        }
    }
}

enum AudioRole: String, CaseIterable, Identifiable, Hashable {
    case master = "Master"
    case drums = "Drums"
    case bass = "Bass"
    case other = "Other"
    case vocals = "Vocals"

    var id: String { rawValue }
    var commandName: String { rawValue.lowercased() }

    var help: String {
        switch self {
        case .master: "Complete stereo master"
        case .drums: "Drums and percussion"
        case .bass: "Bass and low-end elements"
        case .other: "Music and remaining instruments"
        case .vocals: "Lead and background vocals"
        }
    }

    var color: Color {
        switch self {
        case .master: Color(red: 0.35, green: 0.37, blue: 0.40)
        case .drums: Color(red: 0.992, green: 0.424, blue: 0.220) // #FD6C38
        case .bass: Color(red: 0.824, green: 0.196, blue: 0.957)  // #D232F4
        case .other: Color(red: 0.000, green: 1.000, blue: 0.675) // #00FFAC
        case .vocals: Color(red: 0.271, green: 0.855, blue: 0.992) // #45DAFD
        }
    }
}

struct ValidationReport: Decodable {
    let compatible: Bool
    let sampleRate: Int
    let channels: Int
    let duration: Double
    let stemSumLufs: Double
    let stemSumTruePeakDbfs: Double
    let compressorEnabled: Bool
    let limiterEnabled: Bool
    let limiterCeilingDbfs: Double
}

struct NativeReadiness: Decodable {
    let ready: Bool
    let found: Bool
    let hasAudioId: Bool
    let linkedStemExists: Bool
    let message: String
}
