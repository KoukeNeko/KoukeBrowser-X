# KoukeBrowser-X 🌐

<div align="center">

![Swift](https://img.shields.io/badge/swift-F54A2A?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0071e3?style=for-the-badge&logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-000000?style=for-the-badge&logo=apple&logoColor=white)
![WebKit](https://img.shields.io/badge/WebKit-000000?style=for-the-badge&logo=safari&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-007ACC?style=for-the-badge&logo=xcode&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)

</div>
<br/>

<div align="center">
    <img width="800" alt="KoukeBrowser Start Page" src="https://github.com/user-attachments/assets/b0da41ba-7b2e-4058-9f7b-99a04790c472" />
    <br/>
    <br/>
    <img width="800" alt="KoukeBrowser Settings" src="https://github.com/user-attachments/assets/5248db81-d932-44bc-82cf-60d37244a1a2" />
</div>

<br/>

> A modern, privacy-focused, and highly customizable web browser built for macOS.

## 📖 Introduction

**KoukeBrowser-X** is a native macOS application designed to push the boundaries of hybrid **SwiftUI** and **AppKit** development. Unlike standard SwiftUI apps, this project leverages underlying `NSWindow` and `NSHostingView` capabilities to achieve advanced window management features similar to Safari, such as tab dragging, window splitting, and custom traffic light positioning.

The core engine is powered by Apple's **WebKit** framework, ensuring performance and security, while featuring a robust bookmark management system, tab operations, and privacy settings.

## 🚀 Key Features

### 🖥️ Advanced Window & Tab Management
- **Tab Detaching**: Drag a tab out of the window to automatically create a new window instance (powered by `WindowManager`).
- **Cross-Window Tab Moving**: Support for dragging and merging tabs between different windows.
- **Dual Interface Modes**:
  - **Normal**: Traditional layout with the tab bar located above the address bar.
  - **Compact**: Safari-style design where tabs and the address bar are integrated into a single row to save vertical space.
- **Tab Overview**: Grid view of all open tabs with support for quick switching and closing.

### ⚡️ Browsing Experience
- **Smart Address Bar**: Integrated URL input and search functionality supporting Google, Bing, DuckDuckGo, Yahoo, and more.
- **Start Page**: Features shortcuts to favorite websites and a bookmark overview.
- **Bookmark System**: Complete CRUD functionality with support for nested folder structures and JSON import/export.

### 🛡️ Privacy & Settings
- **Privacy Controls**: Built-in options to clear browsing data (Cookies, Cache) and prevent tracking.
- **Developer Tools**: Integrated WebKit developer menu (View Source, JavaScript Console).
- **Full Customization**: Supports Dark/Light theme switching, font size adjustments, and startup behavior configuration.

## 🛠️ Tech Stack

* **Language**: Swift 5.0+
* **UI Frameworks**: SwiftUI (Primary Interface), AppKit (Window Management & Underlying Events)
* **Web Engine**: WebKit (WKWebView)
* **Architecture**: MVVM (Model-View-ViewModel)
* **Persistence**: UserDefaults, Codable (Bookmarks & Settings)
* **Concurrency**: Combine, Swift Concurrency (Task/Await)

## 🧩 Architecture Highlights

This project demonstrates several key engineering implementations:

1.  **Hybrid AppKit/SwiftUI Integration**:
    To overcome SwiftUI's limitations in macOS window control, the project uses `NSWindow` concepts to manage the SwiftUI `BrowserView`. This allows for a custom title bar and precise traffic light positioning.
    * *Relevant Files*: `WindowManager.swift`, `BrowserView.swift`

2.  **State Management**:
    Utilizes Singleton patterns for `BrowserSettings` and `BookmarkManager` to ensure data consistency across windows, employing `Combine`'s `@Published` properties for real-time UI updates.

3.  **Drag & Drop Mechanism**:
    Implements `NSDraggingSource` and `NSDraggingDestination` protocols to handle complex tab logic (reordering within a window vs. detaching to create a new window).
    * *Relevant Files*: `DraggableTabView.swift`, `CompactTabBar.swift`

## 🏃‍♂️ How to Run

1.  Ensure you have **Xcode 16.0** or later installed.
2.  Clone the repository:
    ```bash
    git clone [https://github.com/yourusername/KoukeBrowser-X.git](https://github.com/yourusername/KoukeBrowser-X.git)
    ```
3.  Open `kouke browser.xcodeproj`.
4.  Select the Target `My Mac`.
5.  Press `Cmd + R` to build and run.

## 🔮 Roadmap

- [ ] Implement full browsing History storage (CoreData/SwiftData).
- [ ] Support for Web Extensions.
- [ ] Add Reader Mode.
- [ ] Implement Tab Groups.

---

*Built with ❤️ by [Your Name]*
