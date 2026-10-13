import SwiftUI

/// Shown on the old phone after the account was used on another phone.
struct SignedOutElsewhereView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "iphone.slash")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Signed in on another device")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Your PawDone account is now in use on another iPhone. Free accounts can be used on one phone at a time.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button {
                session.dismissSignedOutElsewhere()
            } label: {
                Text("Sign in again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

#Preview {
    SignedOutElsewhereView()
        .environment(SessionStore(backend: nil, deviceID: "preview"))
}
