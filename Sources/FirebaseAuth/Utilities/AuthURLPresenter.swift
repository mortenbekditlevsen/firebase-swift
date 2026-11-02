// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
#if os(iOS)

  import Foundation
  import SafariServices
  import UIKit

  /// Presents a URL in an `SFSafariViewController` (or a `WKWebView` on Mac Catalyst) until
  /// the app gets a callback URL that `Auth.canHandle(_:)` matches.
  @MainActor
  final class AuthURLPresenter: NSObject, SFSafariViewControllerDelegate,
    AuthWebViewControllerDelegate {
    /// `Auth` creates one off the main actor.
    nonisolated override init() {
      super.init()
    }

    /// Presents `url` and returns the matching callback URL.
    ///
    /// Throws `webContextAlreadyPresented`-style cancellation if another presentation is
    /// active, and `webContextCancelled` if the user closes the page.
    func present(_ url: URL,
                 uiDelegate: AuthUIDelegate?,
                 callbackMatcher: @escaping @Sendable (URL?) -> Bool) async throws -> URL {
      guard continuation == nil else {
        // Unable to start a new presentation on top of another.
        throw AuthErrorUtils.webContextCancelledError(message: nil)
      }
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        self.callbackMatcher = callbackMatcher
        let uiDelegate = fakeUIDelegate ?? uiDelegate ?? AuthDefaultUIDelegate.defaultUIDelegate()
        self.uiDelegate = uiDelegate
        #if targetEnvironment(macCatalyst)
          let webViewController = AuthWebViewController(url: url, delegate: self)
          self.webViewController = webViewController
          let navigationController = UINavigationController(rootViewController: webViewController)
          // Upstream #16274: fill the window on Mac Catalyst.
          navigationController.modalPresentationStyle = .fullScreen
          uiDelegate?.present(navigationController, animated: true, completion: nil)
        #else
          let safariViewController = SFSafariViewController(url: url)
          safariViewController.delegate = self
          self.safariViewController = safariViewController
          uiDelegate?.present(safariViewController, animated: true, completion: nil)
        #endif
      }
    }

    /// Determines if a URL was produced by the currently presented URL, and if so finishes
    /// the presentation with it.
    func canHandle(url: URL) -> Bool {
      guard let callbackMatcher, callbackMatcher(url) else {
        return false
      }
      finishPresentation(.success(url))
      return true
    }

    // MARK: SFSafariViewControllerDelegate

    nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
      MainActor.assumeIsolated {
        guard controller == safariViewController else { return }
        // The controller is gone already, so there's nothing to dismiss.
        safariViewController = nil
        finishPresentation(.failure(AuthErrorUtils.webContextCancelledError(message: nil)))
      }
    }

    // MARK: AuthWebViewControllerDelegate

    func webViewControllerDidCancel(_ controller: AuthWebViewController) {
      guard webViewController == controller else { return }
      finishPresentation(.failure(AuthErrorUtils.webContextCancelledError(message: nil)))
    }

    func webViewController(_ controller: AuthWebViewController, canHandle url: URL) -> Bool {
      webViewController == controller && canHandle(url: url)
    }

    func webViewController(_ controller: AuthWebViewController,
                           didFailWithError error: Error) {
      guard webViewController == controller else { return }
      finishPresentation(.failure(error))
    }

    /// Test-only option to validate the calls to the uiDelegate.
    var fakeUIDelegate: AuthUIDelegate?

    // MARK: Private

    /// The callback URL matcher for the current presentation, if one is active.
    private var callbackMatcher: (@Sendable (URL?) -> Bool)?

    /// Resumes the caller of `present`; non-nil while a presentation is active.
    private var continuation: CheckedContinuation<URL, Error>?

    private var safariViewController: SFSafariViewController?
    private var webViewController: AuthWebViewController?

    /// The UIDelegate used to present the view controller.
    private var uiDelegate: AuthUIDelegate?

    private func finishPresentation(_ result: Result<URL, Error>) {
      let continuation = self.continuation
      self.continuation = nil
      callbackMatcher = nil
      let uiDelegate = self.uiDelegate
      self.uiDelegate = nil
      let presented = safariViewController != nil || webViewController != nil
      safariViewController = nil
      webViewController = nil
      guard let continuation else { return }
      if presented, let uiDelegate {
        uiDelegate.dismiss(animated: true) {
          continuation.resume(with: result)
        }
      } else {
        continuation.resume(with: result)
      }
    }
  }
#endif
