import SwiftUI

public final class WaveformModel: ObservableObject {
    @Published public var phase: CGFloat = 0
    private var timer: Timer?
    private var isRunning = false
    
    public init() {}
    
    /// Start only when visible AND playing — saves battery completely when hidden
    public func start(interval: TimeInterval = 0.1) {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.phase = (self.phase + 0.3).truncatingRemainder(dividingBy: .pi * 2)
        }
    }
    
    public func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
    }
}

public struct WaveformVisualizer: View {
    public let isPlaying: Bool
    public var tintColor: Color
    public var barCount: Int = 4
    public var height: CGFloat = 14
    @StateObject private var model = WaveformModel()
    
    public init(isPlaying: Bool, tintColor: Color = .green, barCount: Int = 4, height: CGFloat = 14) {
        self.isPlaying = isPlaying
        self.tintColor = tintColor
        self.barCount = barCount
        self.height = height
    }
    
    private let delays: [Double] = [0.0, 0.25, 0.5, 0.15, 0.35, 0.1]
    
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                bar(delay: delays[i % delays.count])
            }
        }
        .frame(height: height)
        .onAppear {
            if isPlaying { model.start(interval: 0.1) }
        }
        .onDisappear {
            model.stop() // Battery: stop animating when off-screen
        }
        .onChange(of: isPlaying) { playing in
            if playing { model.start(interval: 0.1) } else { model.stop() }
        }
    }
    
    private func bar(delay: Double) -> some View {
        let normalizedSin = (sin(model.phase + delay * .pi * 2) + 1) / 2
        let barHeight = isPlaying ? max(2.5, height * normalizedSin * 0.85 + 2.5) : 2.5
        
        return RoundedRectangle(cornerRadius: 1.2)
            .fill(
                LinearGradient(
                    colors: [tintColor.opacity(0.6), tintColor],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 2, height: barHeight)
            .animation(.easeOut(duration: 0.1), value: model.phase)
    }
}
