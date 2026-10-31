//
//  AppContainer.swift
//  poc-c6
//
//  Dependency wiring. Owner: Zildjian Vito (ZV-04).
//  When a real implementation is ready, replace its fake in `makeDefault()`.
//

import Foundation

final class AppContainer {
    var configuration: PoCConfiguration

    // Ikzaz
    let stemSeparation: any StemSeparationRepository
    let audioAnalysis: any AudioAnalysisRepository
    let audioTransposition: any AudioTranspositionRepository
    let vocalRange: any VocalRangeRepository

    // Takin
    let capture: any CaptureRepository
    let referencePlayback: any ReferencePlaybackRepository
    let audioRoute: any AudioRouteMonitor
    let takeLog: any SessionTakeLogRepository

    // Zildjian
    let videoComposition: any VideoCompositionRepository

    init(configuration: PoCConfiguration,
         stemSeparation: any StemSeparationRepository,
         audioAnalysis: any AudioAnalysisRepository,
         audioTransposition: any AudioTranspositionRepository,
         vocalRange: any VocalRangeRepository,
         capture: any CaptureRepository,
         referencePlayback: any ReferencePlaybackRepository,
         audioRoute: any AudioRouteMonitor,
         takeLog: any SessionTakeLogRepository,
         videoComposition: any VideoCompositionRepository) {
        self.configuration = configuration
        self.stemSeparation = stemSeparation
        self.audioAnalysis = audioAnalysis
        self.audioTransposition = audioTransposition
        self.vocalRange = vocalRange
        self.capture = capture
        self.referencePlayback = referencePlayback
        self.audioRoute = audioRoute
        self.takeLog = takeLog
        self.videoComposition = videoComposition
    }

    /// What the app runs with. Fakes for now; swap each line as real implementations land.
    static func makeDefault() -> AppContainer {
        AppContainer(
            configuration: .default,
            stemSeparation: FakeStemSeparationRepository(),
            audioAnalysis: FakeAudioAnalysisRepository(),
            audioTransposition: FakeAudioTranspositionRepository(),
            vocalRange: FakeVocalRangeRepository(),
            capture: FakeCaptureRepository(),
            referencePlayback: FakeReferencePlaybackRepository(),
            audioRoute: FakeAudioRouteMonitor(),
            takeLog: FakeSessionTakeLogRepository(),
            videoComposition: FakeVideoCompositionRepository()
        )
    }

    /// All fakes, for previews and tests.
    static func fakes(vocalRange: VocalRange? = nil) -> AppContainer {
        AppContainer(
            configuration: .default,
            stemSeparation: FakeStemSeparationRepository(delay: .zero),
            audioAnalysis: FakeAudioAnalysisRepository(),
            audioTransposition: FakeAudioTranspositionRepository(),
            vocalRange: FakeVocalRangeRepository(initial: vocalRange),
            capture: FakeCaptureRepository(),
            referencePlayback: FakeReferencePlaybackRepository(),
            audioRoute: FakeAudioRouteMonitor(),
            takeLog: FakeSessionTakeLogRepository(),
            videoComposition: FakeVideoCompositionRepository(duration: .zero)
        )
    }
}
