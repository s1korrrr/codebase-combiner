import SwiftUI

struct ContentView: View {
    @ObservedObject private var controller: AppController

    init(controller: AppController) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = AdaptiveWorkspaceLayout(
                mode: WorkspaceLayoutPolicy.mode(for: Double(proxy.size.width))
            )
            let frames = WorkspacePaneGeometry.frames(
                totalWidth: Double(proxy.size.width),
                layout: layout,
                isSidebarPresented: controller.isSidebarPresented,
                isInspectorPresented: controller.isInspectorPresented
            )

            workspace(layout: layout, frames: frames)
        }
        .frame(
            minWidth: WindowContentSizePolicy.minimumWidth,
            minHeight: WindowContentSizePolicy.minimumHeight
        )
        .toolbar {
            workspaceToolbar
            outputToolbar
            visibilityToolbar
        }
        .task {
            await controller.start()
        }
    }

    private func workspace(layout: AdaptiveWorkspaceLayout, frames: WorkspacePaneFrames) -> some View {
        ZStack(alignment: .leading) {
            PreparationWorkspace(controller: controller, layout: layout)
                .padding(.leading, frames.preparation.x)
                .padding(.trailing, max(0, frames.inspector.maxX - frames.preparation.maxX))

            InspectorPaneHost(
                controller: controller,
                layout: layout,
                isPresented: controller.isInspectorPresented
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            SidebarPaneHost(
                controller: controller,
                layout: layout,
                isPresented: controller.isSidebarPresented
            )
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
            Button(action: controller.toggleSidebar) {
                Label("Toggle Workspace Sidebar", systemImage: "rectangle.leftthird.inset.filled")
            }
            .help("Show or hide the workspace sidebar")
            .accessibilityHint("Toggles the workspace sidebar without changing its contents")

            Toggle(isOn: filtersBinding) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help(controller.preferences.values.showFilters ? "Hide filters" : "Show filters")
            .accessibilityHint(controller.preferences.values.showFilters ? "Hides workspace filters" : "Shows workspace filters")

            Button(action: controller.toggleInspector) {
                Label("Toggle Output Inspector", systemImage: "rectangle.rightthird.inset.filled")
            }
            .help("Show or hide the output inspector")
            .accessibilityHint("Toggles the output inspector without changing its contents")
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
}

private struct SidebarPaneHost: View {
    @ObservedObject var controller: AppController
    let layout: AdaptiveWorkspaceLayout
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(controller: controller)
                .frame(width: SidebarPanePresentation.width(layout: layout))
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()
        }
        .frame(width: SidebarPanePresentation.width(layout: layout) + 1)
        .offset(x: SidebarPanePresentation.offset(isPresented: isPresented, layout: layout))
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct InspectorPaneHost: View {
    @ObservedObject var controller: AppController
    let layout: AdaptiveWorkspaceLayout
    let isPresented: Bool

    private var presentedWidth: Double {
        InspectorPanePresentation.width(layout: layout)
    }

    var body: some View {
        HStack(spacing: 0) {
            Divider()

            OutputInspector(controller: controller, layout: layout)
                .frame(width: presentedWidth)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: presentedWidth + 1)
        .offset(
            x: InspectorPanePresentation.offset(isPresented: isPresented, layout: layout)
        )
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
