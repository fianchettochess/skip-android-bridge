// Copyright 2024–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if os(Android)
import Foundation
import FoundationNetworking
import AndroidAssetManager
import AndroidLogging
@preconcurrency import SwiftJNI

fileprivate let logger: Logger = Logger(subsystem: "skip.android.bridge", category: "AssetURLProtocol")

/// A custom URLProtocol that serves requests from the native Android `AAssetManager`, which is implemented in `swift-android-native / AndroidAssetManager.swift`
public class AssetURLProtocol: URLProtocol {
    /// The URL scheme that this protocol handles
    public static let scheme = "asset"

    private static let registrationLock = NSLock()
    nonisolated(unsafe) private static var registered = false
    nonisolated(unsafe) private static var assetManager: AndroidAssetManager? = nil

    public static func register() throws {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        if registered { return }

        _ = URLProtocol.registerClass(AssetURLProtocol.self)
        // Resolve the AssetManager with static JNI rather than AnyDynamicObject: the dynamic
        // path reflects over the full android.content.Context hierarchy with kotlin-reflect,
        // costing hundreds of ms of main-thread time at launch
        let context = ProcessInfo.processInfo.dynamicAndroidContext()
        guard let contextObj = context.toJavaObject(options: []) else {
            throw AndroidAssetError(errorDescription: "no value for ProcessInfo.processInfo.dynamicAndroidContext.toJavaObject")
        }
        let contextClass = try JClass(name: "android/content/Context")
        guard let getResourcesID = contextClass.getMethodID(name: "getResources", sig: "()Landroid/content/res/Resources;") else {
            throw AndroidAssetError(errorDescription: "unable to resolve Context.getResources")
        }
        let resourcesObj: JavaObjectPointer = try JObject(contextObj).call(method: getResourcesID, options: [], args: [])
        let resourcesClass = try JClass(name: "android/content/res/Resources")
        guard let getAssetsID = resourcesClass.getMethodID(name: "getAssets", sig: "()Landroid/content/res/AssetManager;") else {
            throw AndroidAssetError(errorDescription: "unable to resolve Resources.getAssets")
        }
        let assetManagerObj: JavaObjectPointer = try JObject(resourcesObj).call(method: getAssetsID, options: [], args: [])
        let am = JNI.jni.withEnv { intf, env in
            AndroidAssetManager(env: env, peer: assetManagerObj)
        }
        Self.assetManager = am
        Self.registered = true
    }

    private static func registeredManager() -> AndroidAssetManager? {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        return assetManager
    }

    private static func assetPath(for url: URL) -> String {
        String(url.path.trimmingPrefix("/"))
    }

    /// Open an asset URL resolved by the bundle as a bounded sequential stream.
    /// The bridge must be registered before opening a stream.
    public static func openStream(for url: URL) throws -> AssetInputStream {
        guard url.scheme == scheme else {
            throw AndroidAssetError(errorDescription: "not an asset URL")
        }
        guard let manager = registeredManager() else {
            throw AndroidAssetError(errorDescription: "asset manager is not registered")
        }
        let path = assetPath(for: url)
        guard let asset = manager.open(from: path, mode: .streaming) else {
            throw AndroidAssetError(errorDescription: "asset could not be opened: \(path)")
        }
        return AssetInputStream(
            remaining: { asset.remainingLength },
            read: { asset.read(size: $0) },
            close: { asset.close(); withExtendedLifetime(manager) {} }
        )
    }

    public override func startLoading() {
        guard let client else { return }

        guard let url = request.url else {
            client.urlProtocol(self, didFailWithError: NSError(domain: "AssetURLProtocol", code: -1, userInfo: nil))
            return
        }

        defer {
            client.urlProtocolDidFinishLoading(self)
        }

        func sendHTTP(code: Int) {
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)

        }
        guard let assetManager = Self.registeredManager() else {
            sendHTTP(code: 500) // "server error"
            return
        }

        let assetPath = Self.assetPath(for: url)
        if let data = assetManager.load(from: assetPath) {
            sendHTTP(code: 200)
            client.urlProtocol(self, didLoad: data)
        } else {
            sendHTTP(code: 404)
        }
    }

    public override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.scheme == AssetURLProtocol.scheme
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }


    public override func stopLoading() {
        // no-op
    }
}


public struct AndroidAssetError : LocalizedError {
    public var errorDescription: String?

    public init(errorDescription: String? = nil) {
        self.errorDescription = errorDescription
    }
}

#endif
