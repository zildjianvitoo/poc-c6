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
    /// Synthesized demo song with a known guide (ZV-06).
    let demo: SynthesizedDemoRepository
    /// Save to Photos on the export screen (ZV-13).
    let videoLibrary: any VideoLibrarySaving

    init(configuration: PoCConfiguration,
         demo: SynthesizedDemoRepository,
         stemSeparation: any StemSeparationRepository,
         audioAnalysis: any AudioAnalysisRepository,
         audioTransposition: any AudioTranspositionRepository,
         vocalRange: any VocalRangeRepository,
         capture: any CaptureRepository,
         referencePlayback: any ReferencePlaybackRepository,
         audioRoute: any AudioRouteMonitor,
         takeLog: any SessionTakeLogRepository,
         videoComposition: any VideoCompositionRepository,
         videoLibrary: any VideoLibrarySaving) {
        self.configuration = configuration
        self.demo = demo
        self.stemSeparation = stemSeparation
        self.audioAnalysis = audioAnalysis
        self.audioTransposition = audioTransposition
        self.vocalRange = vocalRange
        self.capture = capture
        self.referencePlayback = referencePlayback
        self.audioRoute = audioRoute
        self.takeLog = takeLog
        self.videoComposition = videoComposition
        self.videoLibrary = videoLibrary
    }

    /// What the app runs with. Fakes for now; swap each line as real implementations land.
    static func makeDefault() -> AppContainer {
        let demo = SynthesizedDemoRepository()
        return AppContainer(
            configuration: .default,
            demo: demo,
            stemSeparation: demo,
            audioAnalysis: FakeAudioAnalysisRepository(),
            audioTransposition: FakeAudioTranspositionRepository(),
            vocalRange: FakeVocalRangeRepository(),
            capture: FakeCaptureRepository(),
            referencePlayback: FakeReferencePlaybackRepository(),
            audioRoute: FakeAudioRouteMonitor(),
            takeLog: FakeSessionTakeLogRepository(),
            videoComposition: FakeVideoCompositionRepository(),
            videoLibrary: PhotoLibraryVideoSaver()
        )
    }

    /// All fakes, for previews and tests.
    static func fakes(vocalRange: VocalRange? = nil) -> AppContainer {
        AppContainer(
            configuration: .default,
            demo: SynthesizedDemoRepository(),
            stemSeparation: FakeStemSeparationRepository(delay: .zero),
            audioAnalysis: FakeAudioAnalysisRepository(),
            audioTransposition: FakeAudioTranspositionRepository(),
            vocalRange: FakeVocalRangeRepository(initial: vocalRange),
            capture: FakeCaptureRepository(),
            referencePlayback: FakeReferencePlaybackRepository(),
            audioRoute: FakeAudioRouteMonitor(),
            takeLog: FakeSessionTakeLogRepository(),
            videoComposition: FakeVideoCompositionRepository(duration: .zero),
            videoLibrary: FakeVideoLibrarySaver()
        )
    }
}
