//
// Created by Marijn Schilling on 01/11/2017.
// Copyright (c) 2017 Bakken&Baeck. All rights reserved.
//

import Foundation
import Teapot

public struct ToshiError: LocalizedError {
    static func dataTaskError(withUnderLyingError error: Error) -> TeapotError {
        let errorDescription = String(format: NSLocalizedString("toshi_error_data_task_error", bundle: Teapot.localizationBundle, comment: ""), error.localizedDescription)

        return TeapotError(withType: .dataTaskError, errorDescription: errorDescription, underlyingError: error)
    }

    static let invalidPayload = ToshiError(withType: .invalidPayload, description: Localized("toshi_error_invalid_payload"))
    static let invalidResponseJSON = ToshiError(withType: .invalidPayload, description: Localized("toshi_error_invalid_response_json"))

    static func invalidResponseStatus(_ status: Int) -> ToshiError {
        let errorDescription = String(format: NSLocalizedString("teapot_invalid_response_status", bundle: Teapot.localizationBundle, comment: ""), status)

        return ToshiError(withType: .invalidResponseStatus, description: errorDescription, responseStatus: status)
    }


    enum ErrorType: Int {
        case dataTaskError
        case invalidPayload
        case invalidRequestPath
        case invalidResponseStatus
        case missingImage
        case invalidResponseJSON
    }

    let type: ErrorType
    public var description: String
    let responseStatus: Int?
    let underlyingError: Error?


    init(withType errorType: ErrorType, description: String, responseStatus: Int? = nil, underlyingError: Error? = nil) {
        self.type = errorType
        self.description = description
        self.responseStatus = responseStatus
        self.underlyingError = underlyingError
    }
}

extension ToshiError {
    init?(withTeapotError teapotError: TeapotError, errorDescription: String? = nil) {
        guard let errorType = ErrorType(rawValue: teapotError.type.rawValue) else { return nil }

        self.init(withType: errorType, description: errorDescription ?? teapotError.errorDescription, responseStatus: teapotError.responseStatus, underlyingError: teapotError.underlyingError)

    }
}
