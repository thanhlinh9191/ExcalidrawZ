//
//  ExcalidrawWebView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import SwiftUI
import WebKit
import Combine
import Logging
import QuartzCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

class ExcalidrawWebView: WKWebView {
    var shouldHandleInput = true
#if os(iOS)
    private var indirectScrollForwarder: ExcalidrawIndirectScrollForwarder?
#endif
    
    enum ToolbarActionKey {
        case number(Int)
        case char(Character)
        case space, escape
    }
    var toolbarActionHandler: (ToolbarActionKey) -> Void
    
    init(
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        toolbarActionHandler: @escaping (ToolbarActionKey) -> Void
    ) {
        self.toolbarActionHandler = toolbarActionHandler
        super.init(frame: frame, configuration: configuration)
#if canImport(UIKit)
        self.scrollView.isScrollEnabled = false
        self.scrollView.backgroundColor = .clear
#if os(iOS)
        self.indirectScrollForwarder = ExcalidrawIndirectScrollForwarder(webView: self)
#endif
#endif
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
#if canImport(UIKit)
    override var safeAreaInsets: UIEdgeInsets { .zero }
#endif
    
#if canImport(AppKit)
    override func keyDown(with event: NSEvent) {
        if shouldHandleInput,
           let char = event.characters {
            if let num = Int(char), num >= 0, num <= 9 {
                self.toolbarActionHandler(.number(num))
            } else if ExcalidrawTool.allCases.compactMap({$0.keyEquivalent}).contains(where: {$0 == Character(char)}), !char.isEmpty {
                self.toolbarActionHandler(.char(Character(char)))
            } else if Character(char) == Character(" ") {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.space)
            } else if Character(char) == Character("q") {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.char("q"))
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
#endif
}

#if os(iOS)
private final class ExcalidrawIndirectScrollForwarder: NSObject, UIGestureRecognizerDelegate {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()

        let recognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleIndirectScroll(_:))
        )
        recognizer.allowedScrollTypesMask = .all
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        webView.addGestureRecognizer(recognizer)
    }

    @objc private func handleIndirectScroll(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed,
              let webView else {
            return
        }

        let translation = recognizer.translation(in: webView)
        recognizer.setTranslation(.zero, in: webView)

        guard abs(translation.x) > 0.01 || abs(translation.y) > 0.01 else {
            return
        }

        let location = recognizer.location(in: webView)
        dispatchWheelEvent(
            deltaX: -translation.x,
            deltaY: -translation.y,
            location: location,
            in: webView
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive event: UIEvent
    ) -> Bool {
        event.type == .scroll
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive press: UIPress
    ) -> Bool {
        false
    }

    private func dispatchWheelEvent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        location: CGPoint,
        in webView: WKWebView
    ) {
        let script = """
        (() => {
            const clientX = Math.max(0, Math.min(window.innerWidth, \(Self.javascriptNumber(location.x))));
            const clientY = Math.max(0, Math.min(window.innerHeight, \(Self.javascriptNumber(location.y))));
            const target = document.elementFromPoint(clientX, clientY)
                || document.querySelector(".excalidraw-container")
                || document.body;

            if (!target) {
                return false;
            }

            const event = new WheelEvent("wheel", {
                bubbles: true,
                cancelable: true,
                composed: true,
                clientX,
                clientY,
                screenX: clientX,
                screenY: clientY,
                deltaX: \(Self.javascriptNumber(deltaX)),
                deltaY: \(Self.javascriptNumber(deltaY)),
                deltaZ: 0,
                deltaMode: 0
            });

            return target.dispatchEvent(event);
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func javascriptNumber(_ value: CGFloat) -> String {
        let number = Double(value)
        return number.isFinite ? String(number) : "0"
    }
}
#endif

extension Notification.Name {
    static let forceReloadExcalidrawFile = Notification.Name("ForceReloadExcalidrawFile")
}


/// Minimal wrapper to bridge WKWebView to SwiftUI
struct ExcalidrawViewRepresentable {
    @EnvironmentObject private var core: ExcalidrawCore
    
    func makeExcalidrawWebView(context: Context) -> ExcalidrawWebView {
        return context.coordinator.webView
    }
    
    func updateExcalidrawWebView(_ webView: ExcalidrawWebView, context: Context) {
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        return core
    }
}

#if os(macOS)
extension ExcalidrawViewRepresentable: NSViewRepresentable {
    
    func makeNSView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(nsView, context: context)
    }
}
#elseif os(iOS)
extension ExcalidrawViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateUIView(_ uiView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(uiView, context: context)
    }
}
#endif
