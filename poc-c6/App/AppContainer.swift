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
    /// Reads picked song files for the import screen.
    let audioInspector: any AudioFileInspecting = AudioFileInspector()
    /// Plays the trim selection and prepared tracks on the Ready screen.
    let audioPreview: any AudioPreviewing = AudioPreviewPlayer()
    /// Synced lyrics for the trim screen.
    let lyrics: any LyricsProviding = LRCLibLyricsProvider()
    /// Microphone pitch for the vocal range test.
    let livePitch: any LivePitchSource

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
    /// Camera and microphone permissions for PermissionGate (ZV-14).
    let permissions: any MediaPermissionProviding
    /// Simulator only: sings along with the fake playback so the recording loop can run.
    let simulatedSinger: SimulatedSinger?
    /// Loads the CoreML models at app start; nil with fakes.
    let modelPrewarmer: ModelPrewarmer?

    init(configuration: PoCConfiguration,
         demo: SynthesizedDemoRepository,
         stemSeparation: any StemSeparationRepository,
         audioAnalysis: any AudioAnalysisRepository,
         audioTransposition: any AudioTranspositionRepository,
         vocalRange: any VocalRangeRepository,
         livePitch: any LivePitchSource,
         capture: any CaptureRepository,
         referencePlayback: any ReferencePlaybackRepository,
         audioRoute: any AudioRouteMonitor,
         takeLog: any SessionTakeLogRepository,
         videoComposition: any VideoCompositionRepository,
         videoLibrary: any VideoLibrarySaving,
         permissions: any MediaPermissionProviding,
         simulatedSinger: SimulatedSinger? = nil,
         modelPrewarmer: ModelPrewarmer? = nil) {
        self.configuration = configuration
        self.demo = demo
        self.stemSeparation = stemSeparation
        self.audioAnalysis = audioAnalysis
        self.audioTransposition = audioTransposition
        self.vocalRange = vocalRange
        self.livePitch = livePitch
        self.capture = capture
        self.referencePlayback = referencePlayback
        self.audioRoute = audioRoute
        self.takeLog = takeLog
        self.videoComposition = videoComposition
        self.videoLibrary = videoLibrary
        self.permissions = permissions
        self.simulatedSinger = simulatedSinger
        self.modelPrewarmer = modelPrewarmer
    }

    /// What the app runs with: imported songs are prepared on the device (CoreML vocal separation
    /// with a center-channel fallback, CREPE guide, offline transposition); recording and comping are real on a device.
    static func makeDefault() -> AppContainer {
        let demo = SynthesizedDemoRepository()
        let store = ConfigurationStore()
        #if targetEnvironment(simulator)
        // No camera or microphone: a simulated singer drives the real recording loop.
        // 0.12 s ≈ the device's scheduling lead + output latency.
        let singer = SimulatedSinger()
        let capture: any CaptureRepository = FakeCaptureRepository { _ in singer.frequencyNow() }
        let playback: any ReferencePlaybackRepository = FakeReferencePlaybackRepository(latency: 0.12) { singer.playbackStarted(from: $0, heard: $1) }
        let audioRoute: any AudioRouteMonitor = FakeAudioRouteMonitor()
        let videoComposition: any VideoCompositionRepository = FakeVideoCompositionRepository()
        let livePitch: any LivePitchSource = FakeLivePitchSource()
        #else
        let singer: SimulatedSinger? = nil
        let cameraCapture = CaptureRepositoryImpl()
        let capture: any CaptureRepository = cameraCapture
        // Read on every play so Debug Settings (manual latency) apply immediately.
        let playback: any ReferencePlaybackRepository = ReferencePlaybackRepositoryImpl(capture: cameraCapture) { store.load() }
        let audioRoute: any AudioRouteMonitor = AudioRouteMonitorImpl()
        let videoComposition: any VideoCompositionRepository = VideoCompositionRepositoryImpl()
        let livePitch: any LivePitchSource = MicrophonePitchSource()
        #endif
        let htDemucs = HTDemucsStemSeparationRepository()
        return AppContainer(
            configuration: store.load(),
            demo: demo,
            stemSeparation: SelectingStemSeparationRepository(
                coreML: LoggingStemSeparationRepository(name: "htdemucs", wrapped: htDemucs),
                centerChannel: CenterChannelStemRepository(),
                useCoreML: { store.load().useCoreMLSeparation }),
            audioAnalysis: CrepeAnalysisRepository(),
            audioTransposition: AudioTranspositionRepositoryImpl(),
            vocalRange: VocalRangeRepositoryImpl(),
            livePitch: livePitch,
            capture: capture,
            referencePlayback: playback,
            audioRoute: audioRoute,
            takeLog: SessionTakeLogRepositoryImpl(),
            videoComposition: videoComposition,
            videoLibrary: PhotoLibraryVideoSaver(),
            permissions: SystemMediaPermissions(),
            simulatedSinger: singer,
            modelPrewarmer: ModelPrewarmer(htDemucs: htDemucs)
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
            livePitch: FakeLivePitchSource(),
            capture: FakeCaptureRepository(),
            referencePlayback: FakeReferencePlaybackRepository(),
            audioRoute: FakeAudioRouteMonitor(),
            takeLog: FakeSessionTakeLogRepository(),
            videoComposition: FakeVideoCompositionRepository(duration: .zero),
            videoLibrary: FakeVideoLibrarySaver(),
            permissions: FakeMediaPermissions()
        )
    }
}
