import Foundation

/// A dimension the paper list can be sorted by. Combined with a direction
/// (ascending / descending) in `ContentView`. Raw values persist the user's
/// choice in `AppSettings`.
enum SortKey: String, CaseIterable, Identifiable {
    case score
    case publicationDate
    case citations
    case statusTime
    case dateAdded
    case title

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .score:           return L10n.pick("Score", "评分")
        case .publicationDate: return L10n.pick("Publication date", "发表日期")
        case .citations:       return L10n.pick("Citations", "引用数")
        case .statusTime:      return L10n.pick("Status time", "状态时间")
        case .dateAdded:       return L10n.pick("Date added", "加入时间")
        case .title:           return L10n.pick("Title", "标题")
        }
    }

    var systemImage: String {
        switch self {
        case .score:           return "star"
        case .publicationDate: return "calendar"
        case .citations:       return "quote.bubble"
        case .statusTime:      return "clock"
        case .dateAdded:       return "tray.and.arrow.down"
        case .title:           return "a.square"
        }
    }
}
