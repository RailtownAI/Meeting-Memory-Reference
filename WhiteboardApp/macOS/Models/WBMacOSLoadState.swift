/// Idle → loading → loaded/failed lifecycle for any async-backed section of the macOS UI.
enum WBMacOSLoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        switch self {
        case .loaded(let value):
            return value
        case .idle, .loading, .failed:
            return nil
        }
    }
}
