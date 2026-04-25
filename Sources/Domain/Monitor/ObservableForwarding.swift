import Foundation
import Combine

/// Helper for subscribing to an existential ObservableObject's objectWillChange publisher.
/// Swift cannot directly access objectWillChange on `any ObservableObject` because
/// the publisher type is generic. This helper opens the existential and bridges it.
enum ObservableSubscriber {
    static func subscribe(
        to object: any ObservableObject,
        receiveOn scheduler: some Scheduler,
        onChange: @escaping () -> Void
    ) -> AnyCancellable {
        subscribeToConcrete(object, receiveOn: scheduler, onChange: onChange)
    }

    private static func subscribeToConcrete<T: ObservableObject>(
        _ object: T,
        receiveOn scheduler: some Scheduler,
        onChange: @escaping () -> Void
    ) -> AnyCancellable {
        object.objectWillChange
            .receive(on: scheduler)
            .sink { _ in onChange() }
    }
}
