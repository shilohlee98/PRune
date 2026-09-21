import AppKit
import SwiftUI

struct AppDropdown<Label: View, MenuContent: View>: View {
    @Binding var isPresented: Bool
    let width: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background {
            DropdownPanelPresenter(
                isPresented: $isPresented,
                width: width
            ) {
                menuContent()
            }
        }
    }
}

struct AppDropdownRow<Content: View>: View {
    let isSelected: Bool
    var isEnabled = true
    var foregroundStyle: Color = .primary
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                content()
                    .foregroundStyle(isEnabled ? foregroundStyle : Color.mutedText)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        Color.white.opacity(
                            isSelected ? 0.085 : (isEnabled && isHovered ? 0.065 : 0)
                        )
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = isEnabled && $0 }
    }
}

private struct DropdownPanelPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.anchorView = view

        if isPresented {
            DispatchQueue.main.async {
                context.coordinator.present()
            }
        } else {
            context.coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DropdownPanelPresenter
        weak var anchorView: NSView?

        private var panel: NSPanel?
        private var localEventMonitor: Any?
        private var anchorScreenFrame = NSRect.zero

        init(parent: DropdownPanelPresenter) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func present() {
            guard parent.isPresented,
                  let anchorView,
                  let window = anchorView.window
            else { return }

            let rootView = VStack(spacing: 0) {
                parent.content()
            }
            .padding(6)
            .frame(width: parent.width)
            .background(Color(red: 0.105, green: 0.108, blue: 0.116))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            }

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame.size = hostingView.fittingSize

            let panel = panel ?? makePanel()
            panel.appearance = window.appearance ?? NSAppearance(named: .darkAqua)
            panel.contentView = hostingView
            panel.setContentSize(hostingView.fittingSize)

            let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
            anchorScreenFrame = window.convertToScreen(anchorFrameInWindow)
            position(panel, below: anchorScreenFrame, on: window.screen ?? NSScreen.main)
            panel.orderFront(nil)
            installEventMonitorIfNeeded()
        }

        func dismiss() {
            panel?.orderOut(nil)
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.transient, .ignoresCycle]
            self.panel = panel
            return panel
        }

        private func position(_ panel: NSPanel, below anchor: NSRect, on screen: NSScreen?) {
            let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let margin: CGFloat = 8
            let gap: CGFloat = 4
            let size = panel.frame.size

            var origin = NSPoint(
                x: anchor.minX,
                y: anchor.minY - size.height - gap
            )
            origin.x = min(
                max(origin.x, visibleFrame.minX + margin),
                visibleFrame.maxX - size.width - margin
            )
            if origin.y < visibleFrame.minY + margin {
                origin.y = anchor.maxY + gap
            }
            panel.setFrameOrigin(origin)
        }

        private func installEventMonitorIfNeeded() {
            guard localEventMonitor == nil else { return }
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self, parent.isPresented else { return event }

                if event.type == .keyDown, event.keyCode == 53 {
                    closeFromInteraction()
                    return nil
                }
                if event.window === panel {
                    return event
                }

                let point = event.window?.convertPoint(toScreen: event.locationInWindow)
                    ?? NSEvent.mouseLocation
                if anchorScreenFrame.contains(point) {
                    return event
                }

                closeFromInteraction()
                return event
            }
        }

        private func closeFromInteraction() {
            parent.isPresented = false
            dismiss()
        }

        @objc private func applicationDidResignActive(_ notification: Notification) {
            closeFromInteraction()
        }
    }
}
