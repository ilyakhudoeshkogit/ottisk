import SwiftUI

/// Замена `@State` для сборки без Xcode.
///
/// В новых SDK (macOS 27+) `@State` объявлен как макрос из модуля `SwiftUIMacros`,
/// а плагин этого модуля есть только в Xcode — в Command Line Tools его нет,
/// и `swift build` падает с «plugin for module 'SwiftUIMacros' not found».
/// Сама структура `State<Value>` никуда не делась, поэтому храним её внутри
/// обычной обёртки-свойства: SwiftUI находит вложенные `DynamicProperty`
/// и управляет хранилищем так же, как для `@State`.
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State<Value>(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}

extension LocalState where Value: ExpressibleByNilLiteral {
    /// Позволяет писать `@LocalState private var error: String?` без `= nil`.
    init() { self.init(wrappedValue: nil) }
}
