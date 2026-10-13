import SwiftUI

/// Shown when a Free account signs in while it's active on another phone.
struct DeviceSwitchView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("You're signed in on another iPhone")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Free accounts can be used on one phone at a time. If you continue here, you'll be signed out on the other phone.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button {
                Task { await session.confirmDeviceSwitch() }
            } label: {
                Text("Continue on this iPhone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Cancel") {
                Task { await session.cancelDeviceSwitch() }
            }
            .controlSize(.large)
        }
        .padding(24)
        .disabled(session.isWorking)
    }
}

#Preview {
    DeviceSwitchView()
        .environment(SessionStore(backend: nil, deviceID: "preview"))
}
