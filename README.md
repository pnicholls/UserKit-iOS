# UserKit

Everything you need to talk to your users in just a few lines of code.

UserKit is the easiest way to add real-time video support to your iOS app. 

Designed for support, onboarding, or dev use cases, UserKit enables your team to connect with end-users via video & screensharing — without leaving your app.

## 🎉 Quick Demo

https://github.com/user-attachments/assets/7acc2987-ebe7-4f90-b47b-c4ef291b0216

## ✨ Features

- 🔄 Picture-in-Picture video calls
- 🖥️ Screen sharing from your app
- ⚡ Fast, minimal integration — just a few lines of code

## 📦 Installation

### Swift Package Manager

The preferred installation method is with [Swift Package Manager](https://swift.org/package-manager/). This is a tool for automating the distribution of Swift code and is integrated into the swift compiler. In Xcode, do the following:

- Select **File ▸ Add Packages...**
- Search for `https://github.com/pnicholls/userkit-ios` in the search bar.
- Set the **Dependency Rule** to **Up to Next Major Version** with the lower bound set to **0.1.0**.
- Make sure your project name is selected in **Add to Project**.
- Then, **Add Package**.

## 🚀 Getting Started

```swift
import UserKit

// Initialize with your API key
UserKit.configure(apiKey: "your_api_key")

// Log the user in
try await UserKit.shared.login(id: "2", name: "Tom Nicholls", email: "tom@nicholls.com")
```

That's all that is required! 

Now you can jump over to [getuserkit.com](https://getuserkit.com), find your logged in user and start making talking to your users, literally. 

