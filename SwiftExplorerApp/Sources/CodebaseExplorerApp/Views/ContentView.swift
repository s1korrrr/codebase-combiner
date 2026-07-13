import SwiftUI

struct ContentView: View {
    @ObservedObject private var controller: AppController
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(controller: AppController) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = AdaptiveWorkspaceLayout(
                mode: WorkspaceLayoutPolicy.mode(for: Double(proxy.size.width))
            )

            NavigationSplitView(columnVisibility: $columnVisibility) {
                WorkspaceSidebar(controller: controller)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
            } detail: {
                HSplitView {
                    PreparationWorkspace(controller: controller, layout: layout)
                        .frame(minWidth: layout.preparationMinimumWidth)
                        .layoutPriority(1)

                    if controller.isInspectorPresented {
                        OutputInspector(controller: controller)
                            .frame(
                                minWidth: layout.inspectorMinimumWidth,
                                idealWidth: layout.inspectorIdealWidth,
                                maxWidth: 620
                            )
                    }
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            workspaceToolbar
            outputToolbar
            visibilityToolbar
        }
        .task {
            await controller.start()
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: controller.chooseFolder) {
                Label("Choose Folder", systemImage: "folder")
            }
            .help("Choose a workspace folder")
            .accessibilityHint("Opens a folder picker for the workspace")

            Button(action: controller.refresh) {
                Label("Refresh Workspace", systemImage: "arrow.clockwise")
            }
            .disabled(!controller.commandState.canRefresh)
            .help(controller.commandState.refreshHelp)
            .accessibilityHint(controller.commandState.refreshHelp)
        }
    }

    @ToolbarContentBuilder
    private var outputToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: controller.copy) {
                Label("Copy Combined Output", systemImage: "doc.on.doc")
            }
            .disabled(!controller.commandState.canExport)
            .help(controller.commandState.copyHelp)
            .accessibilityHint(controller.commandState.copyHelp)

            Button(action: controller.save) {
                Label("Save Combined Output", systemImage: "square.and.arrow.down")
            }
            .disabled(!controller.commandState.canExport)
            .help(controller.commandState.saveHelp)
            .accessibilityHint(controller.commandState.saveHelp)
        }
    }

    @ToolbarContentBuilder
    private var visibilityToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: filtersBinding) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help(controller.preferences.values.showFilters ? "Hide filters" : "Show filters")
            .accessibilityHint(controller.preferences.values.showFilters ? "Hides workspace filters" : "Shows workspace filters")

            Toggle(isOn: inspectorBinding) {
                Label("Output Inspector", systemImage: "sidebar.trailing")
            }
            .help(controller.isInspectorPresented ? "Hide the output inspector" : "Show the output inspector")
            .accessibilityHint(controller.isInspectorPresented ? "Collapses the output inspector" : "Shows the output inspector")
        }
    }

    private var filtersBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.values.showFilters },
            set: { newValue in
                if newValue != controller.preferences.values.showFilters {
                    controller.toggleFilters()
                }
            }
        )
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { controller.isInspectorPresented },
            set: { newValue in
                if newValue != controller.isInspectorPresented {
                    controller.toggleInspector()
                }
            }
        )
    }
}
