import Foundation
import LockTodoNoteShared
import SwiftUI

@MainActor
final class SmartLockScreenStore: ObservableObject {
    @Published private(set) var schedule = SmartLockScreenSchedule()
    @Published private(set) var loadFailed = false
    var onChange: (() -> Void)?
    private let store: AppGroupStore

    init(store: AppGroupStore) {
        self.store = store
        do { schedule = try SmartLockScreenSchedule.load(store: store) }
        catch { loadFailed = true }
    }

    enum ScheduleError: LocalizedError {
        case unavailable, proRequired, invalid, overlap, limit
        var errorDescription: String? {
            switch self {
            case .unavailable: bilingualString(korean: "규칙을 저장할 수 없습니다. 기존 데이터는 유지됩니다.", english: "Rules could not be saved. Existing data is preserved.")
            case .proRequired: bilingualString(korean: "자동 카드 전환은 Pro 기능입니다.", english: "Automatic card switching requires Pro.")
            case .invalid: bilingualString(korean: "이름, 저장 구성, 요일과 서로 다른 시작·종료 시각을 선택하세요.", english: "Choose a name, saved layout, weekdays and different start/end times.")
            case .overlap: bilingualString(korean: "다른 활성 규칙과 시간이 겹칩니다. 요일이나 시간을 변경하세요.", english: "This overlaps another enabled rule. Change its days or times.")
            case .limit: bilingualString(korean: "규칙은 최대 8개까지 저장할 수 있습니다.", english: "Save up to eight rules.")
            }
        }
    }

    func save(_ rule: SmartLockScreenRule, isPro: Bool) throws {
        guard isPro else { throw ScheduleError.proRequired }
        guard rule.isValid, try SmartLockScreenSchedule.profiles(store: store).contains(where: { $0.id == rule.profileID })
        else { throw ScheduleError.invalid }
        var next = schedule
        guard next.rules.count < 8 || next.rules.contains(where: { $0.id == rule.id }) else { throw ScheduleError.limit }
        guard !next.rules.contains(where: { $0.id != rule.id && $0.overlaps(rule) }) else { throw ScheduleError.overlap }
        if let index = next.rules.firstIndex(where: { $0.id == rule.id }) { next.rules[index] = rule }
        else { next.rules.append(rule) }
        try persist(next)
    }

    func setEnabled(_ enabled: Bool, isPro: Bool) throws {
        guard !enabled || isPro else { throw ScheduleError.proRequired }
        var next = schedule; next.isEnabled = enabled
        try persist(next)
    }

    func remove(_ rule: SmartLockScreenRule) throws {
        var next = schedule; next.rules.removeAll { $0.id == rule.id }
        try persist(next)
    }

    private func persist(_ next: SmartLockScreenSchedule) throws {
        guard !loadFailed, let url = store.containerURL?.appendingPathComponent(SmartLockScreenSchedule.fileName)
        else { throw ScheduleError.unavailable }
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        store.relaxFileProtection(at: url)
        schedule = next
        onChange?()
    }
}
