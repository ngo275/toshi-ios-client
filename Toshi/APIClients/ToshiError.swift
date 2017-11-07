//
// Created by Marijn Schilling on 01/11/2017.
// Copyright (c) 2017 Bakken&Baeck. All rights reserved.
//

import Foundation
import Teapot

public struct ToshiError: LocalizedError {
    enum ErrorType: Int {
        case dataTaskError
        case invalidPayload
        case invalidRequestPath
        case invalidResponseStatus
        case missingImage
    }

    let responseStatus: Int?
    let underlyingError: Error?
    let type: ErrorType

    public var description: String
}

extension ToshiError {
    init?(withTeapotError teapotError: TeapotError, errorDescription: String? = nil) {
        guard let errorType = ErrorType(rawValue: teapotError.type.rawValue) else { return nil }

        self.type = errorType
        self.responseStatus = teapotError.responseStatus
        self.underlyingError = teapotError.underlyingError
        self.description = errorDescription ?? teapotError.errorDescription
    }
}
