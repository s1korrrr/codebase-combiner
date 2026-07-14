import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var controller: AppController

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Folder…", action: controller.chooseFolder)
                .keyboardShortcut("o", modifiers: [.command])

            Button("Refresh Workspace", action: controller.refresh)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!controller.commandState.canRefresh)
                .help(controller.commandState.refreshHelp)
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Combined Output", action: controller.copy)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!controller.commandState.canExport)
                .help(controller.commandState.copyHelp)
        }

        CommandGroup(after: .saveItem) {
            Button("Save Combined Output…", action: controller.save)
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!controller.commandState.canExport)
                .help(controller.commandState.saveHelp)
        }

        CommandGroup(after: .sidebar) {
            Button(
                controller.sidebarCommandTitle,
                action: controller.toggleSidebar
            )
            Button(
                controller.preferences.values.showFilters ? "Hide Filters" : "Show Filters",
                action: controller.toggleFilters
            )
            Button(
                controller.isInspectorPresented ? "Hide Output Inspector" : "Show Output Inspector",
                action: controller.toggleInspector
            )
        }

        CommandMenu("Support") {
            Button("Buy Me a Coffee") {
                AppLinks.openSupportPage()
            }
        }
    }
}
