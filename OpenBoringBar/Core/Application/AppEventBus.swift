import Combine
import CoreGraphics
import Foundation

enum AppEvent {
    case capsuleAppSwitchConfirmed(processID: pid_t)
    case barDisplayHeightChanged(displayID: CGDirectDisplayID, height: CGFloat)
}

protocol AppEventBus {
    var events: AnyPublisher<AppEvent, Never> { get }
    func post(_ event: AppEvent)
}

final class DefaultAppEventBus: AppEventBus {
    private let subject = PassthroughSubject<AppEvent, Never>()

    var events: AnyPublisher<AppEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    func post(_ event: AppEvent) {
        subject.send(event)
    }
}
