//
//  MenuBarView.swift
//  ScrollSnap
//

import SwiftUI

/// `MenuBarView` manages the menu bar's appearance and interactions.
class MenuBarView: NSView {
    
    // MARK: - Properties
    
    private weak var manager: OverlayManager?
    private weak var overlayView: OverlayView?
    private let screenFrame: NSRect
    
    // MARK: - Initialization
    
    init(manager: OverlayManager, screenFrame: NSRect, overlayView: OverlayView) {
        self.manager = manager
        self.screenFrame = screenFrame
        self.overlayView = overlayView
        super.init(frame: screenFrame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    func draw(in dirtyRect: NSRect) {
        guard let manager = manager else { return }
        let menuRect = manager.getMenuRectangle()
        drawMenuBar(in: menuRect)
    }
    
    func handleMouseDown(at globalPoint: NSPoint) {
        guard let manager = manager else { return }
        let menuRect = manager.getMenuRectangle()
        handleMenuMouseDown(at: globalPoint, in: menuRect)
    }
    
    func handleMouseUp(at globalPoint: NSPoint) {
        guard let manager = manager else { return }
        let menuRect = manager.getMenuRectangle()
        if menuRect.contains(globalPoint) {
            handleMenuMouseUp(at: globalPoint, in: menuRect)
        }
    }
    
    // MARK: - Menu Drawing
    
    private func drawMenuBar(in menuRect: NSRect) {
        let menuRectToDraw = menuRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        
        drawMenuBackground(in: menuRectToDraw)
        
        drawDragButton(for: menuRectToDraw)
        drawCancelButton(for: menuRectToDraw)
        drawOptionsButton(for: menuRectToDraw)
        drawCaptureButton(for: menuRectToDraw)
    }
    
    /// Draws the menu background with rounded corners and a shadow.
    private func drawMenuBackground(in menuRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: menuRect,
            xRadius: Constants.Menu.cornerRadius,
            yRadius: Constants.Menu.cornerRadius
        )
        
        Constants.Menu.backgroundColor.setFill()
        path.fill()
        
        let shadow = NSShadow()
        shadow.shadowOffset = Constants.Menu.shadowOffset
        shadow.shadowBlurRadius = Constants.Menu.shadowBlurRadius
        shadow.shadowColor = Constants.Menu.shadowColor
        shadow.set()
        
        Constants.Menu.borderColor.setStroke()
        path.lineWidth = Constants.Menu.borderWidth
        path.stroke()
    }
    
    /// Draw the Capture button inside the menu rectangle, toggling between "Capture" and "Save".
    private func drawCaptureButton(for menuRect: NSRect) {
        let buttonRect = getCaptureButtonRect(for: menuRect)
        let label = manager?.getIsScrollingCaptureActive() == true ? "Save" : "Capture"
        
        drawText(label, in: buttonRect)
    }
    
    /// Draw the Cancel button inside the menu rectangle
    private func drawCancelButton(for menuRect: NSRect) {
        let cancelRect = getCancelButtonRect(for: menuRect)
        
        drawVerticalBorder(at: cancelRect.maxX, minY: cancelRect.minY, maxY: cancelRect.maxY)
        
        if let cancelIcon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) {
            drawSymbol(cancelIcon, in: cancelRect)
        }
    }
    
    /// Draw the Options button inside the menu rectangle
    private func drawOptionsButton(for menuRect: NSRect) {
        let buttonRect = getOptionsButtonRect(for: menuRect)
        drawVerticalBorder(at: buttonRect.maxX, minY: buttonRect.minY, maxY: buttonRect.maxY)
        drawTextWithSymbol("Options ", symbol: "chevron.down", in: buttonRect)
    }
    
    /// Draws the drag button inside the menu rectangle.
    private func drawDragButton(for menuRect: NSRect) {
        let buttonRect = getDragButtonRect(for: menuRect)
        
        drawVerticalBorder(at: buttonRect.maxX, minY: buttonRect.minY, maxY: buttonRect.maxY)
        
        if let dragSymbol = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: nil) {
            drawSymbol(dragSymbol, in: buttonRect, size: 12)
        }
    }
    
    /// Draws text centered within a rectangle.
    private func drawText(_ text: String, in rect: NSRect) {
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.Menu.Button.textColor,
            .paragraphStyle: textStyle,
            .font: Constants.Menu.Button.textFont
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    /// Draws text with an SF Symbol attached, centered within a rectangle.
    private func drawTextWithSymbol(_ text: String, symbol: String, in rect: NSRect) {
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.Menu.Button.textColor,
            .paragraphStyle: textStyle,
            .font: Constants.Menu.Button.textFont
        ]
        
        let optionsText = NSAttributedString(string: text, attributes: attributes)
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageAttachment.bounds = CGRect(x: 0, y: 0, width: 12, height: 8)
        
        let imageAttributedString = NSAttributedString(attachment: imageAttachment)
        
        let finalString = NSMutableAttributedString()
        finalString.append(optionsText)
        finalString.append(imageAttributedString)
        
        let textSize = finalString.size()
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        finalString.draw(in: textRect)
    }
    
    /// Draws an SF Symbol centered within a rectangle.
    private func drawSymbol(_ symbol: NSImage, in rect: NSRect, size: CGFloat = 24) {
        symbol.isTemplate = true
        let iconSize = NSSize(width: size, height: size)
        let iconRect = NSRect(
            x: rect.midX - iconSize.width / 2,
            y: rect.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        symbol.draw(in: iconRect)
    }
    
    /// Draws a vertical border at the specified X coordinate within the given Y range.
    private func drawVerticalBorder(at x: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: x, y: minY))
        borderPath.line(to: NSPoint(x: x, y: maxY))
        Constants.Menu.borderColor.setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
    
    // MARK: - Menu Button Rectangles
    
    private func getDragButtonRect(for menuRect: NSRect) -> NSRect {
        return NSRect(
            x: menuRect.minX,
            y: menuRect.minY,
            width: Constants.Menu.Button.dragWidth,
            height: menuRect.height
        )
    }
    
    private func getCancelButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = Constants.Menu.Button.dragWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: Constants.Menu.Button.cancelWidth,
            height: menuRect.height
        )
    }
    
    private func getOptionsButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = Constants.Menu.Button.dragWidth + Constants.Menu.Button.cancelWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: Constants.Menu.Button.optionsWidth,
            height: menuRect.height
        )
    }
    
    private func getCaptureButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = Constants.Menu.Button.dragWidth + Constants.Menu.Button.cancelWidth + Constants.Menu.Button.optionsWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: Constants.Menu.Button.captureWidth,
            height: menuRect.height
        )
    }
    
    // MARK: - Menu Interaction Handling
    
    /// Handles mouse down events within the menu rectangle.
    private func handleMenuMouseDown(at point: NSPoint, in menuRect: NSRect) {
        let buttonRect = getCaptureButtonRect(for: menuRect)
        let cancelRect = getCancelButtonRect(for: menuRect)
        let optionsRect = getOptionsButtonRect(for: menuRect)
        
        if buttonRect.contains(point) || cancelRect.contains(point) {
            return // Prevent dragging menu if button clicked
        }
        
        if optionsRect.contains(point) {
            let localOptionsRect = NSRect(
                x: optionsRect.minX - screenFrame.origin.x,
                y: optionsRect.minY - screenFrame.origin.y,
                width: optionsRect.width,
                height: optionsRect.height
            )
            showOptionsMenu(localOptionsRect)
            return
        }
        
        manager?.handleMouseDown(at: point) // Handle dragging the menu
    }
    
    /// Handles mouse up events within the menu rectangle.
    private func handleMenuMouseUp(at point: NSPoint, in menuRect: NSRect) {
        let buttonRect = getCaptureButtonRect(for: menuRect)
        if buttonRect.contains(point) {
            guard let manager = manager else { return }
            manager.captureScreenshot()
            return
        }
        
        let cancelRect = getCancelButtonRect(for: menuRect)
        if cancelRect.contains(point) {
            NSApplication.shared.terminate(self)
            return
        }
    }
    
    // MARK: - Options Menu
    
    private func createOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        
        let saveToItem = NSMenuItem(title: "Save to", action: nil, keyEquivalent: "")
        saveToItem.isEnabled = false
        menu.addItem(saveToItem)
        
        let selectedOption = UserDefaults.standard.string(forKey: Constants.Menu.Options.selectedDestinationKey) ?? Constants.Menu.Options.defaultDestination
        let destinations = Constants.Menu.Options.destinations
        
        for destination in destinations {
            let item = NSMenuItem(title: destination, action: #selector(selectDestination(_:)), keyEquivalent: "")
            item.target = self
            if destination == selectedOption {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        return menu
    }
    
    @objc private func showOptionsMenu(_ optionsRect: CGRect) {
        let menu = createOptionsMenu()
        overlayView?.showOptionsMenu(menu, at: NSPoint(x: optionsRect.minX, y: optionsRect.minY))
    }
    
    @objc private func selectDestination(_ sender: NSMenuItem) {
        for item in sender.menu?.items ?? [] {
            item.state = .off
        }
        sender.state = .on
        
        UserDefaults.standard.set(sender.title, forKey: Constants.Menu.Options.selectedDestinationKey)
    }
}
