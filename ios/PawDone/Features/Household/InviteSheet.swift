import SwiftUI

/// Shows an invite code to read out or share.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let invite: Invite
    let petName: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Invite someone to help with \(petName)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("They install TailTick, choose “Join a household” and enter this code:")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(InviteCode.display(invite.code))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 12))
                    .accessibilityLabel("Code \(invite.code.map(String.init).joined(separator: " "))")
                Text("Works once, until \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                ShareLink(item: message) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var message: String {
        "Help me look after \(petName) on TailTick! Install the app, choose “Join a household” "
            + "and enter this code: \(InviteCode.display(invite.code)). It works for 7 days."
    }
}
