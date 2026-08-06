import SwiftUI
import UniformTypeIdentifiers

/// Choose a ledger, then read it.
///
/// Two pages and the transition between them. Kept separate from ``MainPage`` so
/// that page stays what it was — a view over one source — rather than growing a
/// mode.
struct RootPage: View {
    @State private var model: Model

    init(model: Model = Model()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let opened = model.opened {
                MainPage(
                    source: opened.source,
                    request: opened.request,
                    loaded: opened.loaded,
                    onClose: model.close
                )
                // A new ledger is a new page, not a reconfigured one: `.id`
                // makes SwiftUI build a fresh `MainPage.Model` rather than
                // trying to swap a source under a running load.
                .id(opened.id)
            } else {
                WelcomePage(
                    candidates: model.candidates,
                    samples: model.samples,
                    lastOpenedPath: model.lastOpenedPath,
                    problem: model.problem,
                    onOpen: model.open,
                    onOpenSample: model.open,
                    onBrowse: model.browse
                )
            }
        }
        .fileImporter(
            isPresented: $model.isBrowsing,
            allowedContentTypes: Model.ledgerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            model.finishBrowsing(result)
        }
        .task { model.discover() }
    }
}
