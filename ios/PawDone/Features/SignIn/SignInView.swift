import AuthenticationServices
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
            Text("PawDone")
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
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
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
