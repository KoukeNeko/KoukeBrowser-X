import Foundation
import AuthenticationServices

class WebAuthnManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    private var completionHandler: ((String?, Error?) -> Void)?
    private weak var window: NSWindow?
    
    // MARK: - API
    
    func performRegistration(jsonRequest: String, in window: NSWindow, completion: @escaping (String?, Error?) -> Void) {
        self.window = window
        self.completionHandler = completion
        
        // TODO: Parse JSON to ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest
        // This is complex because we need to map the exact JSON structure from JS to Swift objects.
        // For a full implementation, we need Codable structs matching the WebAuthn spec.
        
        // For now, we assume the JS sends us the necessary parameters or we map them manually.
        // real implementation requires robust JSON decoding.
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "todo-domain.com")
        let request = provider.createCredentialRegistrationRequest(challenge: Data(), name: "User", userID: Data())
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    func performAssertion(jsonRequest: String, in window: NSWindow, completion: @escaping (String?, Error?) -> Void) {
        self.window = window
        self.completionHandler = completion
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "todo-domain.com")
        let request = provider.createCredentialAssertionRequest(challenge: Data())
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            // Handle registration success
            // Serialize credential back to JSON for JS
            completionHandler?("{}", nil)
        } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // Handle assertion success
            completionHandler?("{}", nil)
        } else {
            completionHandler?(nil, NSError(domain: "WebAuthn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown credential type"]))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completionHandler?(nil, error)
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return window ?? NSWindow()
    }
}
