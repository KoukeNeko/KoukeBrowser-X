//
//  AutofillPrompt.swift
//  kouke browser
//
//  What the browser is currently asking the user about autofill.
//
//  Filling is never automatic. A page can present a login form the user cannot
//  see, so a credential only reaches the page after the user picks it here.
//

import Foundation

enum AutofillPrompt: Equatable, Identifiable {

    /// Saved logins exist for this site and can be filled on request.
    case offerToFill(tabId: UUID, host: String, credentials: [SavedCredential])

    /// The user just submitted a login that is not saved yet.
    case offerToSave(tabId: UUID, host: String, username: String, password: String)

    /// The user submitted a different password for a login already saved.
    case offerToUpdate(tabId: UUID, host: String, username: String, password: String)

    var tabId: UUID {
        switch self {
        case .offerToFill(let tabId, _, _),
             .offerToSave(let tabId, _, _, _),
             .offerToUpdate(let tabId, _, _, _):
            return tabId
        }
    }

    var host: String {
        switch self {
        case .offerToFill(_, let host, _),
             .offerToSave(_, let host, _, _),
             .offerToUpdate(_, let host, _, _):
            return host
        }
    }

    var id: String {
        switch self {
        case .offerToFill(let tabId, let host, _):
            return "fill-\(tabId)-\(host)"
        case .offerToSave(let tabId, let host, let username, _):
            return "save-\(tabId)-\(host)-\(username)"
        case .offerToUpdate(let tabId, let host, let username, _):
            return "update-\(tabId)-\(host)-\(username)"
        }
    }
}
