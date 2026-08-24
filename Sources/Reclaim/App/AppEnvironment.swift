//
//  AppEnvironment.swift
//  Reclaim
//
//  Injects the app model and each of its sub-models into the
//  environment in one call, so views can declare exactly the
//  dependencies they read instead of reaching through AppModel.
//

import ReclaimAppCore
import SwiftUI

extension View {
    /// Injects the app model and each of its sub-models so views can
    /// declare exactly the dependencies they read.
    func appEnvironment(_ model: AppModel) -> some View {
        self
            .environment(model)
            .environment(model.settings)
            .environment(model.activity)
            .environment(model.results)
            .environment(model.breakdowns)
            .environment(model.selection)
            .environment(model.projects)
            .environment(model.scanner)
            .environment(model.cleaner)
            .environment(model.history)
    }
}
