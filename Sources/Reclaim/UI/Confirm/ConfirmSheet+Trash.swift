//
//  ConfirmSheet+Trash.swift
//  Reclaim
//
//  The Trash/delete disposal toggle in the sheet's footer.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension ConfirmSheet {
    func trashToggle(toTrash: Bool) -> some View {
        @Bindable var settings = settings
        return Toggle(isOn: Binding(
            get: { settings.disposal == .trash },
            set: { settings.disposal = $0 ? .trash : .delete }
        )) {
            Text(localized("confirm.trashToggle", defaultValue: "Move to Trash instead of deleting"))
                .themeFont(.body)
                .foregroundStyle(Theme.textChipLabel)
        }
        .toggleStyle(SmallCheckToggleStyle())
        .help(localized(
            "confirm.trashToggleHelp",
            defaultValue: "The app-wide disposal setting — also in Settings"
        ))
    }
}
