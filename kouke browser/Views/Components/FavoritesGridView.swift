//
//  FavoritesGridView.swift
//  kouke browser
//
//  Shared favorites grid component used by StartPage and AddressBarDropdown.
//

import SwiftUI

/// 收藏夾網格視圖的配置
struct FavoritesGridConfig {
    var iconSize: CGFloat = 64
    var spacing: CGFloat = 16
    var columns: Int = 6
    var maxItems: Int = 12
    var horizontalPadding: CGFloat = 32
    var isAdaptive: Bool = false  // true = 根據寬度自適應，false = 固定列數

    /// 計算總寬度（僅用於固定模式）
    var totalWidth: CGFloat {
        let iconsWidth = CGFloat(columns) * iconSize
        let gapsWidth = CGFloat(columns - 1) * spacing
        let paddingWidth = horizontalPadding * 2
        return iconsWidth + gapsWidth + paddingWidth
    }

    /// StartPage 預設配置（自適應寬度）
    static let startPage = FavoritesGridConfig(
        iconSize: 64,
        spacing: 16,
        columns: 6,
        maxItems: 12,
        horizontalPadding: 32,
        isAdaptive: true
    )

    /// AddressBar Dropdown 預設配置（與 StartPage 統一樣式）
    static let dropdown = FavoritesGridConfig(
        iconSize: 64,
        spacing: 16,
        columns: 6,
        maxItems: 6,
        horizontalPadding: 32,
        isAdaptive: true
    )
}

/// 共用的收藏夾網格視圖
struct FavoritesGridView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    let folderId: UUID?
    let config: FavoritesGridConfig
    let onNavigate: (String) -> Void
    let onFolderTap: ((UUID) -> Void)?

    init(
        bookmarkManager: BookmarkManager = .shared,
        folderId: UUID? = nil,
        config: FavoritesGridConfig = .startPage,
        onNavigate: @escaping (String) -> Void,
        onFolderTap: ((UUID) -> Void)? = nil
    ) {
        self.bookmarkManager = bookmarkManager
        self.folderId = folderId
        self.config = config
        self.onNavigate = onNavigate
        self.onFolderTap = onFolderTap
    }

    private var currentFolders: [BookmarkFolder] {
        bookmarkManager.folders(in: folderId)
    }

    private var currentBookmarks: [Bookmark] {
        bookmarkManager.bookmarks(in: folderId)
    }

    private var hasContent: Bool {
        !currentFolders.isEmpty || !currentBookmarks.isEmpty
    }

    /// 根據配置生成 grid columns
    private var gridColumns: [GridItem] {
        if config.isAdaptive {
            // 自適應模式：根據可用寬度自動調整列數
            return [GridItem(.adaptive(minimum: config.iconSize, maximum: config.iconSize), spacing: config.spacing)]
        } else {
            // 固定模式：使用指定的列數
            return Array(repeating: GridItem(.fixed(config.iconSize), spacing: config.spacing), count: config.columns)
        }
    }

    var body: some View {
        if hasContent {
            LazyVGrid(
                columns: gridColumns,
                spacing: config.spacing
            ) {
                // Folders first
                ForEach(currentFolders.prefix(config.maxItems)) { folder in
                    FolderButton(
                        folder: folder,
                        bookmarkManager: bookmarkManager,
                        action: {
                            if let onFolderTap = onFolderTap {
                                // StartPage: 進入資料夾
                                onFolderTap(folder.id)
                            } else {
                                // Dropdown: 導航到第一個書籤
                                if let first = bookmarkManager.bookmarks(in: folder.id).first {
                                    onNavigate(first.url)
                                }
                            }
                        },
                        size: config.iconSize
                    )
                }

                // Then bookmarks
                let remainingSlots = max(0, config.maxItems - currentFolders.count)
                ForEach(currentBookmarks.prefix(remainingSlots)) { bookmark in
                    BookmarkButton(
                        bookmark: bookmark,
                        action: { onNavigate(bookmark.url) },
                        size: config.iconSize
                    )
                }
            }
            // 不在此處加 padding，由父視圖處理
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        // StartPage style
        FavoritesGridView(
            config: .startPage,
            onNavigate: { _ in },
            onFolderTap: { _ in }
        )

        // Dropdown style
        FavoritesGridView(
            config: .dropdown,
            onNavigate: { _ in }
        )
    }
    .padding()
    .background(Color("Bg"))
}
