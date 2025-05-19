//
//  Constants.swift
//  ScrollSnap
//

import SwiftUI

struct Constants {
    struct Menu {
        static let height: CGFloat = 50.0
        static let cornerRadius: CGFloat = 6.0
        static let shadowBlurRadius: CGFloat = 10.0
        static let shadowOffset: CGSize = CGSize(width: 0, height: -3)
        static let shadowOpacity: CGFloat = 0.3
        static let shadowColor: NSColor = NSColor.black.withAlphaComponent(0.3)
        static let backgroundColor: NSColor = .white
        static let borderColor: NSColor = .black
        static let borderWidth: CGFloat = 1.0
        
        struct Options {
            static let destinations: [String] = ["Desktop", "Documents", "Downloads", "Clipboard", "Preview"]
            static let defaultDestination: String = "Downloads"
            static let selectedDestinationKey: String = "SelectedDestination"
        }
        
        struct Button {
            static let dragWidth: CGFloat = 35.0
            static let cancelWidth: CGFloat = 40.0
            static let optionsWidth: CGFloat = 90.0
            static let captureWidth: CGFloat = 70.0
            static let textColor: NSColor = .black
            static let textFont: NSFont = .systemFont(ofSize: 14)
            static let iconColor: NSColor = .black
        }
    }
    
    struct SelectionRectangle {
        static let initialX: CGFloat = 100.0
        static let initialY: CGFloat = 100.0
        static let initialWidth: CGFloat = 800.0
        static let initialHeight: CGFloat = 500.0
        static let borderWidth: CGFloat = 1.0
        static let borderDashPattern: [CGFloat] = [6.0, 4.0]
        static let fillColor: NSColor = NSColor.white.withAlphaComponent(0.01)
        static let handleSize: CGFloat = 10.0
        static let clearFillColor: CGColor = NSColor.clear.cgColor
    }
    
    struct Overlay {
        static let backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.5)
        static let windowLevel: NSWindow.Level = .statusBar
        static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    struct Thumbnail {
        static let clickDistanceThreshold: CGFloat = 5    // Max movement for a click
        static let swipeDistanceThreshold: CGFloat = 20   // Min distance for swipe-right save
        static let swipeRightAnimationDuration: TimeInterval = 0.5  // Animation time for swipe-right
        static let swipeBackAnimationDuration: TimeInterval = 0.3   // Animation time for swipe-back
        static let swipeSmoothingNewFactor: CGFloat = 0.7  // Weight for new position in smoothing
        static let swipeSmoothingOldFactor: CGFloat = 0.3  // Weight for old position in smoothing
    }
    
    static let rectangleKey = "LastRectangleFrame"
    static let menuRectKey = "LastMenuFrame"
    static let dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
}
