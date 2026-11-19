import SwiftUI

/// The cleanup hero's ring: while scanning, file particles spiral in from around the card and the ring fills with
/// liquid in proportion to the junk found; while cleaning, the liquid drains with bubbles; finishing bursts sparks.
/// With Reduce Motion it is a still ring with a flat liquid level.
struct CleanupVacuumRing: View {
    var tint: Color
    var symbol: String
    /// The amount the liquid level represents (found, or left after cleaning).
    var bytes: Int64
    var scanning: Bool
    var working: Bool
    /// Changes whenever a scan or a cleanup finishes; each change bursts sparks.
    var celebration: Int
    var size: CGFloat = 128
    /// The area particles fly in from, centered on the ring; the hero card clips it.
    var field = CGSize(width: 560, height: 340)

    @PocketReduceMotion private var reduceMotion
    @State private var simulation = VacuumSimulation()
    /// The ring keeps moving briefly after a change so the liquid can settle. This must be state that a task
    /// clears, not a deadline compared with `Date()` in `body`: nothing re-evaluates `body` when the deadline
    /// passes, so the timeline never paused and redrew at 60 fps while the page sat idle (~25 % CPU).
    @State private var settling = false
    @State private var settleRequest = 0
    @State private var settleSeconds: TimeInterval = 0

    var body: some View {
        let level = Self.level(for: bytes)
        ZStack {
            if reduceMotion {
                staticRing(level: level)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !isAnimating)) { context in
                    Canvas(rendersAsynchronously: false) { gc, canvasSize in
                        simulation.step(to: context.date, targetLevel: level, scanning: scanning, draining: working)
                        simulation.draw(in: &gc, size: canvasSize, ringRadius: size / 2, tint: tint)
                    }
                }
                .frame(width: field.width, height: field.height)
                .allowsHitTesting(false)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(level > 0.45 ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                .shadow(color: .black.opacity(level > 0.45 ? 0.18 : 0), radius: 3, y: 1)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: scanning && !reduceMotion)
        }
        .frame(width: size, height: size)
        .onChange(of: bytes) { keepAnimating(for: 3) }
        .onChange(of: scanning) { keepAnimating(for: 3) }
        .onChange(of: working) { keepAnimating(for: 3) }
        .onChange(of: celebration) {
            simulation.burst()
            keepAnimating(for: 2)
        }
        .onAppear { keepAnimating(for: 2.5) }
        .task(id: settleRequest) {
            guard settleRequest > 0 else { return }
            settling = true
            do { try await Task.sleep(for: .seconds(settleSeconds)) } catch { return }
            settling = false
        }
        .accessibilityHidden(true)
    }

    private var isAnimating: Bool { scanning || working || settling }

    /// A newer request restarts the wait (the previous task is cancelled by the new id).
    private func keepAnimating(for seconds: TimeInterval) {
        settleSeconds = seconds
        settleRequest &+= 1
    }

    private func staticRing(level: Double) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.06))
            Circle().fill(tint.opacity(0.85)).mask(alignment: .bottom) {
                Rectangle().frame(height: size * level)
            }
            Circle().stroke(tint.opacity(0.55), lineWidth: size * 0.04)
        }
    }

    /// Fills quickly for the first gigabytes and approaches (never reaches) full for very large amounts.
    static func level(for bytes: Int64) -> Double {
        guard bytes > 0 else { return 0 }
        return min(0.92, 1 - exp(-Double(bytes) / 12_000_000_000))
    }
}

/// Mutable particle state advanced by the Canvas on every frame; not observed by SwiftUI.
@MainActor
final class VacuumSimulation {
    private struct Particle { var angle: Double; var radius: Double; var size: Double; var spin: Double }
    private struct Bubble { var x: Double; var y: Double; var radius: Double; var age: Double }
    private struct Spark { var angle: Double; var distance: Double; var speed: Double; var age: Double }

    private var particles: [Particle] = []
    private var bubbles: [Bubble] = []
    private var sparks: [Spark] = []
    private var level = 0.0
    private var time = 0.0
    private var last: Date?
    private var spawnCarry = 0.0
    private var fieldRadius = 300.0
    private var generator = SystemRandomNumberGenerator()

    func burst() {
        for index in 0..<18 {
            sparks.append(Spark(angle: Double(index) / 18 * .pi * 2 + .random(in: -0.1...0.1), distance: 0,
                                speed: .random(in: 90...140), age: 0))
        }
    }

    func step(to date: Date, targetLevel: Double, scanning: Bool, draining: Bool) {
        let dt = min(1.0 / 20, last.map { date.timeIntervalSince($0) } ?? 0)
        last = date
        time += dt * (scanning ? 2.4 : 1)
        level += (targetLevel - level) * min(1, dt * 3)

        if scanning {
            spawnCarry += dt * 240
            while spawnCarry >= 1 {
                spawnCarry -= 1
                particles.append(Particle(angle: .random(in: 0..<(.pi * 2)), radius: fieldRadius * .random(in: 0.85...1.1),
                                          size: .random(in: 1.6...3.4), spin: .random(in: 0..<(.pi * 2))))
            }
        }
        for index in particles.indices {
            let radius = particles[index].radius
            particles[index].angle += dt * 260 / max(40, radius)
            particles[index].radius -= dt * (120 + max(0, 240 - radius) * 2.2)
            particles[index].spin += dt * 9
        }
        particles.removeAll { $0.radius < 34 }

        if draining, bubbles.count < 40, Double.random(in: 0...1) < dt * 40 {
            bubbles.append(Bubble(x: .random(in: -0.7...0.7), y: 1, radius: .random(in: 1.5...4), age: 0))
        }
        for index in bubbles.indices {
            bubbles[index].age += dt
            bubbles[index].y -= dt * (0.55 + bubbles[index].radius * 0.08)
        }
        bubbles.removeAll { $0.y < 1 - level * 2 || $0.age > 3 }

        for index in sparks.indices {
            sparks[index].age += dt
            sparks[index].distance += dt * sparks[index].speed * max(0, 1 - sparks[index].age)
        }
        sparks.removeAll { $0.age > 1 }
    }

    func draw(in gc: inout GraphicsContext, size: CGSize, ringRadius: Double, tint: Color) {
        fieldRadius = Double(max(size.width, size.height)) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Particles spiralling in.
        for particle in particles {
            let point = CGPoint(x: center.x + cos(particle.angle) * particle.radius, y: center.y + sin(particle.angle) * particle.radius)
            var piece = gc
            piece.translateBy(x: point.x, y: point.y)
            piece.rotate(by: .radians(particle.spin))
            let rect = CGRect(x: -particle.size, y: -particle.size * 1.3, width: particle.size * 2, height: particle.size * 2.6)
            piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(tint.opacity(min(0.85, particle.radius / 140))))
        }

        // Soft glow behind the vessel.
        let glowRect = CGRect(x: center.x - ringRadius * 2, y: center.y - ringRadius * 2, width: ringRadius * 4, height: ringRadius * 4)
        gc.fill(Path(ellipseIn: glowRect), with: .radialGradient(Gradient(colors: [tint.opacity(0.22 + 0.06 * sin(time * 2)), tint.opacity(0)]),
                                                                    center: center, startRadius: ringRadius * 0.5, endRadius: ringRadius * 2))

        // Vessel and liquid.
        let vessel = Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
        var inside = gc
        inside.clip(to: vessel)
        inside.fill(vessel, with: .color(tint.opacity(0.07)))
        let surface = center.y + ringRadius - level * ringRadius * 2
        for (amplitude, speed, opacity) in [(4.0, 2.2, 0.45), (6.0, 1.4, 0.9)] {
            var wave = Path()
            wave.move(to: CGPoint(x: center.x - ringRadius, y: center.y + ringRadius))
            var x = -ringRadius
            while x <= ringRadius {
                wave.addLine(to: CGPoint(x: center.x + x, y: surface + sin(x / 14 + time * speed) * amplitude * min(1, level * 6)))
                x += 3
            }
            wave.addLine(to: CGPoint(x: center.x + ringRadius, y: center.y + ringRadius))
            wave.closeSubpath()
            inside.fill(wave, with: .color(tint.opacity(opacity)))
        }
        for bubble in bubbles {
            let point = CGPoint(x: center.x + bubble.x * ringRadius + sin(bubble.age * 6) * 2, y: center.y + (bubble.y * 2 - 1) * ringRadius)
            inside.stroke(Path(ellipseIn: CGRect(x: point.x - bubble.radius, y: point.y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)),
                          with: .color(.white.opacity(0.85)), lineWidth: 1.3)
        }
        gc.stroke(vessel, with: .color(tint.opacity(0.55)), lineWidth: ringRadius * 0.08)

        // Sparks.
        for spark in sparks {
            let distance = ringRadius + spark.distance
            let point = CGPoint(x: center.x + cos(spark.angle) * distance, y: center.y + sin(spark.angle) * distance)
            let radius = 3.5 * (1 - spark.age * 0.8)
            gc.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(tint.opacity(1 - spark.age)))
        }
    }
}
