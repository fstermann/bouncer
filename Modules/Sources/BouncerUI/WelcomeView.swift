import Settings
import SwiftUI

/// Shown on first launch, to pick the modes Bouncer runs in before anything asks for attention.
public struct WelcomeView: View {
    @Bindable private var settings: SettingsStore
    private let finish: () -> Void

    public init(settings: SettingsStore, finish: @escaping () -> Void) {
        _settings = Bindable(settings)
        self.finish = finish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Bouncer")
                    .font(.title2.bold())
                Text("Choose what Bouncer does. You can change this any time in Settings.")
                    .foregroundStyle(.secondary)
            }

            ForEach(Mode.allCases) { mode in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mode.symbol)
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title).font(.headline)
                        Text(mode.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle(mode.title, isOn: mode.binding(in: $settings.preferences))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(mode.isLastOn(in: settings.preferences))
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Continue", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
