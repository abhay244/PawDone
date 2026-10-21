import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignInNonce()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("Logo")
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("TailTick")
                .font(.largeTitle.bold())
                .padding(.top, 20)
            Text("Fed yet? Walked yet?\nNow you'll know.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()

            if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            } else if let notice = session.notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            if session.state == .notConfigured {
                Text("Sign-in isn't set up yet. Add your Supabase details to Config/Secrets.xcconfig.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }

            SignInWithAppleButton(.continue) { request in
                nonce = AppleSignInNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce.hashed
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .disabled(session.state == .notConfigured || session.isWorking)
            .opacity(session.state == .notConfigured || session.isWorking ? 0.5 : 1)

            if AppConfig.isGoogleSignInConfigured && session.state != .notConfigured {
                GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide, action: signInWithGoogle)
                    .disabled(session.isWorking)
                    .padding(.top, 12)
            }

            Text(Self.legalNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    /// "By continuing, you agree to the Terms of Use and Privacy Policy", with both as links.
    private static let legalNote: AttributedString = {
        let markdown = "By continuing, you agree to the [Terms of Use](\(AppConfig.termsOfUseURL.absoluteString)) "
            + "and [Privacy Policy](\(AppConfig.privacyPolicyURL.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString("By continuing, you agree to the Terms of Use and Privacy Policy.")
    }()

    private func signInWithGoogle() {
        guard let presenter = Self.topViewController() else { return }
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
                guard let idToken = result.user.idToken?.tokenString else {
                    session.showSignInError("Couldn't sign in with Google. Try again.")
                    return
                }
                await session.signInWithGoogle(
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    fullName: result.user.profile?.name
                )
            } catch {
                if (error as? GIDSignInError)?.code == .canceled { return }
                session.showSignInError("Couldn't sign in with Google. Try again.")
            }
        }
    }

    /// Google's sign-in sheet needs a UIKit view controller to present from.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                session.showSignInError("Couldn't sign in with Apple. Try again.")
                return
            }
            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            }
            let rawNonce = nonce.raw
            Task {
                await session.signInWithApple(idToken: idToken, nonce: rawNonce, fullName: fullName)
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            session.showSignInError("Couldn't sign in with Apple. Try again.")
        }
    }
}

#Preview {
    SignInView()
        .environment(SessionStore(backend: nil, deviceID: "preview"))
}
