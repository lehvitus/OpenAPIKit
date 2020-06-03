//
//  Validator.swift
//  
//
//  Created by Mathew Polzin on 1/26/20.
//

/// A type that holds a function to determine if a validation
/// applies (`predicate`) and a function that applies
/// a validation (`validate`).
public struct Validator<T: Encodable> {
    /// Applies validation on type `T`. Throws if validation fails.
    ///
    /// The context includes
    /// - The entire `OpenAPI.Document`
    /// - A value of the type in which this validator specializes.
    /// - The coding path where the validation is occurring.
    public let validate: (ValidationContext<T>) -> Validity

    /// Returns `true` if this validator should apply to
    /// the given value of type `T`.
    ///
    /// The context includes
    /// - The entire `OpenAPI.Document`
    /// - A value of the type in which this validator specializes.
    /// - The coding path where the validation is occurring.
    public let predicate: (ValidationContext<T>) -> Bool

    /// Create a Validator that by default appllies to all
    /// values of type `T`.
    ///
    /// - Parameters:
    ///     - validate: A function taking values of type `T` and validating
    ///         them. This function should throw if a validation error occurs.
    ///     - predicate: A function returning `true` if this validator
    ///         should run against the given value.
    ///
    public init(
        if predicate: @escaping (ValidationContext<T>) -> Bool = { _ in true },
        validate: @escaping (ValidationContext<T>) -> Validity
    ) {
        self.validate = validate
        self.predicate = predicate
    }
}

/// Validation errors are just a textual reason for validation failure and
/// a coding path where the validation error occurred.
public struct ValidationError: Swift.Error, CustomStringConvertible {
    /// The reason for the validation failure.
    public let reason: String
    /// The location where the failure occurred.
    public let codingPath: [CodingKey]

    /// Create a new `ValidationError` with the given
    /// reason and location (coding path).
    public init(reason: String, at path: [CodingKey]) {
        self.reason = reason
        self.codingPath = path
    }

    public var description: String {
        "\(reason) at path: \(codingPath.map { $0.intValue.map { "[\($0)]" } ?? "/\($0.stringValue)" }.joined())"
    }
}

/// A type that collects `ValidationErrors`.
public struct ValidationErrors: Swift.Error {
    public let values: [ValidationError]

    internal var validity: Validity {
        return .invalid(because: values)
    }
}

public enum Validity {
    case valid
    case invalid(because: [ValidationError])

    public static func invalid(because reason: String, at path: [CodingKey]) -> Self {
        .invalid(because: [ValidationError(reason: reason, at: path)])
    }

    internal var isValid: Bool {
        guard case .valid = self else { return false }
        return true
    }

    internal var errors: [ValidationError] {
        guard case .invalid(because: let reasons) = self else { return [] }
        return reasons
    }

    internal mutating func merge(with other: Validity) {
        switch (self, other) {
        case (.valid, .valid):
            self = .valid
        case (.valid, _):
            self = other
        case (_, .valid):
            break
        case (.invalid(because: let reasons1), .invalid(because: let reasons2)):
            self = .invalid(because: reasons1 + reasons2)
        }
    }
}

internal struct ValidationAttempt {
    let validate: (OpenAPI.Document, Encodable, [CodingKey]) -> Validity

    #if swift(>=5.2)
    func callAsFunction(_ value: Encodable, in document: OpenAPI.Document, at codingPath: [CodingKey]) -> Validity {
        return attempt(on: value, in: document, at: codingPath)
    }
    #endif

    func attempt(on value: Encodable, in document: OpenAPI.Document, at codingPath: [CodingKey]) -> Validity {
        return validate(document, value, codingPath)
    }

    init<T: Encodable>(_ validator: Validator<T>) {
        self.validate = { document, input, codingPath in
            
            guard let subject = input as? T else {
                return .valid
            }
            guard type(of: subject) == type(of: input) else {
                // apparently we need to guard against T? being
                // coerced to T above.
                return .valid
            }
            let context = ValidationContext(document: document, subject: subject, codingPath: codingPath)
            guard validator.predicate(context) else {
                return .valid
            }

            return validator.validate(context)
        }
    }
}
