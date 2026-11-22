import BoltZipCore
import SwiftUI

extension ArchiveExplorerView {
    @ViewBuilder
    func rowContextMenu(ids: Set<String>, listing: ArchiveListing, l: L10n) -> some View {
        let picked = ids.compactMap { vm.visibleEntryByID[$0] }
        if let first = picked.first, picked.count == 1 {
            if vm.isSearchingActive {
                Button {
                    vm.jumpToEntryLocation(first)
                } label: {
                    Label(l.ctxJumpToPath, systemImage: "arrow.turn.down.right")
                }
                Divider()
            }
            Button(first.isDirectory ? l.ctxOpenFolder : l.ctxQuickLook) {
                vm.previewOrOpenEntry(first)
            }
            Button(l.ctxProperties) {
                vm.activeSheet = .entryProperties(first)
            }
            Divider()
            Button("\(l.ctxCopyName) (\(first.name))") {
                vm.copyToPasteboard(first.name)
            }
            Button(l.ctxCopyPath) {
                vm.copyToPasteboard(first.path)
            }
            Divider()
        }

        Button(l.ctxExtractSelHere) {
            vm.quickExtract(mode: .selected(ids))
        }
        Button(l.ctxExtractSelTo) {
            vm.activeSheet = .extractOptions(.selected(ids))
        }
        Button(l.ctxExportNewZip) {
            vm.exportSelectedAsNewZip(entryIDs: ids)
        }

        Divider()

        Button(l.ctxVerifyArchive) {
            vm.testIntegrity()
        }

        if listing.canEditInPlace {
            Divider()
            if let single = picked.first, picked.count == 1, !single.isDirectory, !single.isSymbolicLink {
                Button(l.editEntryText) { vm.editEntryText(single) }
                Button(l.replaceEntryFile) { vm.replaceEntryFile(single) }
            }
            Button(l.ctxAddHere) {
                vm.addItemsToCurrentZipPanel()
            }
            Button(l.ctxNewFolderHere) {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
            if let single = picked.first, picked.count == 1 {
                Button(l.ctxRename) {
                    vm.activeSheet = .renamePath(oldPath: single.path, currentName: single.name)
                }
            }
            Button(l.ctxDeleteFromArchive, role: .destructive) {
                vm.selectedEntryIDs = ids
                vm.requestDeleteSelectedEntries()
            }
        }
    }

    @ViewBuilder
    func emptySpaceContextMenu(listing: ArchiveListing, l: L10n) -> some View {
        Button(l.ctxSmartExtractAll) {
            vm.quickExtract(mode: .smart)
        }
        Button(l.ctxExtractAllSubfolder) {
            vm.quickExtract(mode: .subfolder)
        }
        Button(l.ctxExtractAllTo) {
            vm.activeSheet = .extractOptions(.smart)
        }

        if listing.canEditInPlace {
            Divider()
            Button(l.ctxAddHere) {
                vm.addItemsToCurrentZipPanel()
            }
            Button(l.ctxNewFolderHere) {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
            Menu(l.zipAddAlgoLabel) {
                ForEach(listing.format.supportedAlgorithms) { algo in
                    Button {
                        vm.preferredZipEditAlgorithm = algo
                    } label: {
                        let resolvedCurrent = listing.format.supportedAlgorithms.contains(vm.preferredZipEditAlgorithm)
                            ? vm.preferredZipEditAlgorithm
                            : listing.format.defaultAlgorithm
                        if resolvedCurrent == algo {
                            Label(algo.shortName, systemImage: "checkmark")
                        } else {
                            Text(algo.shortName)
                        }
                    }
                }
            }
            if listing.format.supportsArchiveComment {
                Button(l.archiveCommentEditBtn) {
                    vm.activeSheet = .editArchiveComment(current: listing.comment)
                }
            }
        }

        Divider()

        Button(l.ctxVerifyAll) {
            vm.testIntegrity()
        }

        Menu(l.ctxSwitchEncoding) {
            ForEach(FilenameEncodingOption.allCases) { enc in
                Button {
                    vm.reloadWithEncoding(enc)
                } label: {
                    if vm.encodingOption == enc {
                        Label(l.encodingTitle(enc), systemImage: "checkmark")
                    } else {
                        Text(l.encodingTitle(enc))
                    }
                }
            }
        }

        Menu(l.ctxSortBy) {
            ForEach(SortColumn.allCases) { col in
                Button {
                    vm.toggleSortColumn(col)
                } label: {
                    if vm.sortColumn == col {
                        Label(l.sortColumnTitle(col), systemImage: vm.sortAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(l.sortColumnTitle(col))
                    }
                }
            }
        }

        Divider()
        Button(l.ctxShowInFinder) {
            vm.showInFinder(listing.archiveURL)
        }
    }
}
