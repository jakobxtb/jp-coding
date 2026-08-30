import Foundation

/// Ergebnis eines Modelltests, wird auf Platte zwischengespeichert.
struct ModelResult: Codable, Hashable {
    var ok: Bool
    var ms: Int
    var detail: String
    var checkedAt: Date
    var age: String {
        let s = Int(Date().timeIntervalSince(checkedAt))
        if s < 60 { return "gerade eben" }
        if s < 3600 { return "vor \(s/60) min" }
        if s < 86400 { return "vor \(s/3600) h" }
        return "vor \(s/86400) d"
    }
}

/// Testet Modelle gegen den Proxy und merkt sich die Ergebnisse.
@MainActor
final class ModelProbe: ObservableObject {
    @Published private(set) var results: [String: ModelResult] = [:]
    @Published private(set) var testing: Set<String> = []
    @Published private(set) var sweepRunning = false
    @Published private(set) var sweepDone = 0
    @Published private(set) var sweepTotal = 0

    private var file: URL { Paths.data.appendingPathComponent("model-results.json") }
    private var sweepTask: Task<Void, Never>? = nil

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: file),
              let r = try? JSONDecoder().decode([String: ModelResult].self, from: d) else { return }
        results = r
    }
    func save() {
        guard let d = try? JSONEncoder().encode(results) else { return }
        try? d.write(to: file, options: .atomic)
    }

    func result(for m: String) -> ModelResult? { results[m] }
    func isTesting(_ m: String) -> Bool { testing.contains(m) }

    /// Einzelnes Modell testen und Ergebnis merken.
    @discardableResult
    func test(_ model: String, timeout: TimeInterval = 130) async -> ModelResult {
        testing.insert(model)
        let t0 = Date()
        let (ok, detail) = await Backend.testModel(model, timeout: timeout)
        let r = ModelResult(ok: ok, ms: Int(Date().timeIntervalSince(t0) * 1000),
                            detail: detail, checkedAt: Date())
        results[model] = r
        testing.remove(model)
        save()
        return r
    }

    /// Reihum alle uebergebenen Modelle testen, zwei gleichzeitig.
    func sweep(_ models: [String], timeout: TimeInterval = 75) {
        guard !sweepRunning else { return }
        sweepRunning = true; sweepDone = 0; sweepTotal = models.count
        sweepTask = Task {
            let maxParallel = 2
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                while next < min(maxParallel, models.count) {
                    let m = models[next]; next += 1
                    group.addTask { [weak self] in _ = await self?.test(m, timeout: timeout) }
                }
                while await group.next() != nil {
                    sweepDone += 1
                    if Task.isCancelled { break }
                    if next < models.count {
                        let m = models[next]; next += 1
                        group.addTask { [weak self] in _ = await self?.test(m, timeout: timeout) }
                    }
                }
            }
            sweepRunning = false
        }
    }

    func cancelSweep() {
        sweepTask?.cancel(); sweepTask = nil; sweepRunning = false
    }

    /// Bekannt funktionierende Modelle, neueste Pruefung zuerst.
    func workingModels() -> [String] {
        results.filter { $0.value.ok }
            .sorted { $0.value.ms < $1.value.ms }
            .map { $0.key }
    }
}
