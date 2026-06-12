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
    private var isOptionsPopupVisible = false
    private var hoveredMenuControl: MenuControl?
    private var hoveredOptionsPopupTarget: OptionsPopupTarget?

    private enum MenuControl {
        case drag
        case cancel
        case options
        case capture
    }

    private enum OptionsPopupTarget: Equatable {
        case destination(SaveDestination)
        case reset
    }

    private enum OptionsPopupLayout {
        static let margin: CGFloat = 8
        static let gap: CGFloat = 6
        static let padding: CGFloat = 6
        static let headingHeight: CGFloat = 20
        static let rowHeight: CGFloat = 28
        static let separatorHeight: CGFloat = 9
        static let resetHeight: CGFloat = 30
        static let cornerRadius: CGFloat = 8
        static let checkmarkWidth: CGFloat = 24
    }
    
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
        drawOptionsPopupIfNeeded(for: menuRect)
    }
    
    func handleMouseDown(at globalPoint: NSPoint) {
        guard let manager = manager else { return }
        let menuRect = manager.getMenuRectangle()
        handleMenuMouseDown(at: globalPoint, in: menuRect)
    }

    func handleOpenPopupMouseDown(at globalPoint: NSPoint) -> Bool {
        guard isOptionsPopupVisible, let manager = manager else { return false }

        let menuRect = manager.getMenuRectangle()
        if handleOptionsPopupMouseDown(at: globalPoint, menuRect: menuRect) {
            return true
        }

        if menuRect.contains(globalPoint) {
            return false
        }

        hideOptionsPopup()
        return true
    }

    func handleMouseMoved(at globalPoint: NSPoint) {
        guard let manager = manager else { return }

        let menuRect = manager.getMenuRectangle()
        let nextHoveredMenuControl = getMenuControl(at: globalPoint, in: menuRect)
        let nextPopupTarget: OptionsPopupTarget?

        if isOptionsPopupVisible {
            let popupRect = getOptionsPopupRect(for: menuRect)
            nextPopupTarget = popupRect.contains(globalPoint)
                ? getOptionsPopupTarget(at: globalPoint, in: popupRect)
                : nil
        } else {
            nextPopupTarget = nil
        }

        updateHoverState(
            menuControl: nextHoveredMenuControl,
            popupTarget: nextPopupTarget
        )
    }

    func clearHoverState() {
        updateHoverState(menuControl: nil, popupTarget: nil)
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
        let label = manager?.getIsScrollingCaptureActive() == true ? AppText.save : AppText.capture
        if hoveredMenuControl == .capture {
            drawMenuButtonHoverBackground(in: buttonRect)
        }
        drawTextWithSymbol(label, symbol: "return", in: buttonRect)
    }
    
    /// Draw the Cancel button inside the menu rectangle
    private func drawCancelButton(for menuRect: NSRect) {
        let cancelRect = getCancelButtonRect(for: menuRect)
        
        drawVerticalBorder(at: cancelRect.maxX, minY: cancelRect.minY, maxY: cancelRect.maxY)
        if hoveredMenuControl == .cancel {
            drawMenuButtonHoverBackground(in: cancelRect)
        }
        
        if let cancelIcon = configuredSymbol("xmark", accessibilityDescription: AppText.cancelAccessibility) {
            drawSymbol(cancelIcon, in: cancelRect, size: 15)
        }
    }
    
    /// Draw the Options button inside the menu rectangle
    private func drawOptionsButton(for menuRect: NSRect) {
        let buttonRect = getOptionsButtonRect(for: menuRect)
        drawVerticalBorder(at: buttonRect.maxX, minY: buttonRect.minY, maxY: buttonRect.maxY)
        if hoveredMenuControl == .options || isOptionsPopupVisible {
            drawMenuButtonHoverBackground(in: buttonRect)
        }
        drawTextWithSymbol(AppText.options, symbol: "chevron.down", in: buttonRect)
    }
    
    /// Draws the drag button inside the menu rectangle.
    private func drawDragButton(for menuRect: NSRect) {
        let buttonRect = getDragButtonRect(for: menuRect)
        
        drawVerticalBorder(at: buttonRect.maxX, minY: buttonRect.minY, maxY: buttonRect.maxY)
        if hoveredMenuControl == .drag {
            drawMenuButtonHoverBackground(in: buttonRect)
        }
        
        if let dragSymbol = configuredSymbol("arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: AppText.moveAccessibility) {
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
        let finalString = MenuBarLayout.attributedLabel(text, symbol: symbol)
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

    private func configuredSymbol(_ symbolName: String, accessibilityDescription: String?) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        return symbol?.withSymbolConfiguration(configuration) ?? symbol
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

    private func drawMenuButtonHoverBackground(in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        rect.fill()
    }
    
    // MARK: - Menu Button Rectangles
    
    private func getDragButtonRect(for menuRect: NSRect) -> NSRect {
        return NSRect(
            x: menuRect.minX,
            y: menuRect.minY,
            width: MenuBarLayout.dragWidth,
            height: menuRect.height
        )
    }
    
    private func getCancelButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = MenuBarLayout.dragWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: MenuBarLayout.cancelWidth,
            height: menuRect.height
        )
    }
    
    private func getOptionsButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: MenuBarLayout.optionsWidth,
            height: menuRect.height
        )
    }
    
    private func getCaptureButtonRect(for menuRect: NSRect) -> NSRect {
        let startX = MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth + MenuBarLayout.optionsWidth
        return NSRect(
            x: menuRect.minX + startX,
            y: menuRect.minY,
            width: MenuBarLayout.captureWidth,
            height: menuRect.height
        )
    }

    private func getMenuControl(at point: NSPoint, in menuRect: NSRect) -> MenuControl? {
        if getDragButtonRect(for: menuRect).contains(point) {
            return .drag
        }
        if getCancelButtonRect(for: menuRect).contains(point) {
            return .cancel
        }
        if getOptionsButtonRect(for: menuRect).contains(point) {
            return .options
        }
        if getCaptureButtonRect(for: menuRect).contains(point) {
            return .capture
        }
        return nil
    }
    
    // MARK: - Menu Interaction Handling
    
    /// Handles mouse down events within the menu rectangle.
    private func handleMenuMouseDown(at point: NSPoint, in menuRect: NSRect) {
        let buttonRect = getCaptureButtonRect(for: menuRect)
        let cancelRect = getCancelButtonRect(for: menuRect)
        let optionsRect = getOptionsButtonRect(for: menuRect)
        
        if buttonRect.contains(point) || cancelRect.contains(point) {
            hideOptionsPopup()
            return // Prevent dragging menu if button clicked
        }
        
        if optionsRect.contains(point) {
            toggleOptionsPopup()
            return
        }

        if isOptionsPopupVisible {
            hideOptionsPopup()
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
    
    // MARK: - Options Popup

    private func toggleOptionsPopup() {
        isOptionsPopupVisible.toggle()
        if !isOptionsPopupVisible {
            hoveredOptionsPopupTarget = nil
        }
        invalidateOverlay()
    }

    private func hideOptionsPopup() {
        guard isOptionsPopupVisible else { return }
        isOptionsPopupVisible = false
        hoveredOptionsPopupTarget = nil
        invalidateOverlay()
    }

    private func drawOptionsPopupIfNeeded(for menuRect: NSRect) {
        guard isOptionsPopupVisible else { return }

        let popupRect = getOptionsPopupRect(for: menuRect)
        let localPopupRect = popupRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        let popupPath = NSBezierPath(
            roundedRect: localPopupRect,
            xRadius: OptionsPopupLayout.cornerRadius,
            yRadius: OptionsPopupLayout.cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 10
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.set()
        Constants.Menu.backgroundColor.setFill()
        popupPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        Constants.Menu.borderColor.withAlphaComponent(0.35).setStroke()
        popupPath.lineWidth = 1
        popupPath.stroke()

        drawOptionsPopupRows(in: popupRect)
    }

    private func drawOptionsPopupRows(in popupRect: NSRect) {
        drawOptionsPopupText(
            AppText.saveTo,
            in: getOptionsPopupHeadingRect(in: popupRect),
            color: NSColor.black.withAlphaComponent(0.62),
            font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        )

        let selectedDestination = SaveDestination.current()
        for destination in SaveDestination.allCases {
            let target = OptionsPopupTarget.destination(destination)
            guard let rowRect = getOptionsPopupRect(for: target, in: popupRect) else { continue }
            if target == hoveredOptionsPopupTarget {
                drawHoveredOptionsPopupRow(rowRect)
            } else if destination == selectedDestination {
                drawSelectedOptionsPopupRow(rowRect)
            }
            if destination == selectedDestination {
                drawCheckmark(in: rowRect)
            }
            drawOptionsPopupText(destination.localizedTitle, in: rowRect)
        }

        if let fileDestinationSeparatorRect = getOptionsPopupFileDestinationSeparatorRect(in: popupRect) {
            drawOptionsPopupSeparator(in: fileDestinationSeparatorRect)
        }
        drawOptionsPopupSeparator(in: getOptionsPopupSeparatorRect(in: popupRect))

        let resetTarget = OptionsPopupTarget.reset
        if let resetRect = getOptionsPopupRect(for: resetTarget, in: popupRect) {
            if resetTarget == hoveredOptionsPopupTarget {
                drawHoveredOptionsPopupRow(resetRect)
            }
            drawOptionsPopupText(AppText.resetSelectionAndMenuPositions, in: resetRect)
        }
    }

    private func drawHoveredOptionsPopupRow(_ globalRect: NSRect) {
        drawOptionsPopupRowBackground(globalRect, alpha: 0.12)
    }

    private func drawSelectedOptionsPopupRow(_ globalRect: NSRect) {
        drawOptionsPopupRowBackground(globalRect, alpha: 0.08)
    }

    private func drawOptionsPopupRowBackground(_ globalRect: NSRect, alpha: CGFloat) {
        let localRect = globalRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: localRect.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
    }

    private func drawCheckmark(in globalRect: NSRect) {
        guard let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) else { return }

        checkmark.isTemplate = true
        Constants.Menu.Button.textColor.set()
        let iconSize = NSSize(width: 12, height: 12)
        let localRect = globalRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        let iconRect = NSRect(
            x: localRect.minX + OptionsPopupLayout.padding + 4,
            y: localRect.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        checkmark.draw(in: iconRect)
    }

    private func drawOptionsPopupSeparator(in globalRect: NSRect) {
        let localRect = globalRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        let lineY = localRect.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: localRect.minX + OptionsPopupLayout.padding, y: lineY))
        path.line(to: NSPoint(x: localRect.maxX - OptionsPopupLayout.padding, y: lineY))
        Constants.Menu.borderColor.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawOptionsPopupText(
        _ text: String,
        in globalRect: NSRect,
        color: NSColor = Constants.Menu.Button.textColor,
        font: NSFont = Constants.Menu.Button.textFont
    ) {
        let localRect = globalRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: localRect.minX + OptionsPopupLayout.padding + OptionsPopupLayout.checkmarkWidth,
            y: localRect.midY - textSize.height / 2,
            width: localRect.width - OptionsPopupLayout.padding * 2 - OptionsPopupLayout.checkmarkWidth,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func handleOptionsPopupMouseDown(at point: NSPoint, menuRect: NSRect) -> Bool {
        let popupRect = getOptionsPopupRect(for: menuRect)
        guard popupRect.contains(point) else { return false }

        if let target = getOptionsPopupTarget(at: point, in: popupRect) {
            switch target {
            case .destination(let destination):
                destination.persist()
            case .reset:
                manager?.resetPositions()
            }
            hideOptionsPopup()
        }

        return true
    }

    private func getOptionsPopupTarget(at point: NSPoint, in popupRect: NSRect) -> OptionsPopupTarget? {
        for destination in SaveDestination.allCases {
            if let rowRect = getOptionsPopupRect(for: .destination(destination), in: popupRect),
               rowRect.contains(point) {
                return .destination(destination)
            }
        }

        if let resetRect = getOptionsPopupRect(for: .reset, in: popupRect),
           resetRect.contains(point) {
            return .reset
        }

        return nil
    }

    private func getOptionsPopupRect(for menuRect: NSRect) -> NSRect {
        let optionsRect = getOptionsButtonRect(for: menuRect)
        let width = getOptionsPopupWidth()
        let height = getOptionsPopupHeight()
        let x = min(
            max(optionsRect.minX, screenFrame.minX + OptionsPopupLayout.margin),
            screenFrame.maxX - OptionsPopupLayout.margin - width
        )
        var y = optionsRect.minY - OptionsPopupLayout.gap - height

        if y < screenFrame.minY + OptionsPopupLayout.margin {
            y = optionsRect.maxY + OptionsPopupLayout.gap
        }

        y = min(
            max(y, screenFrame.minY + OptionsPopupLayout.margin),
            screenFrame.maxY - OptionsPopupLayout.margin - height
        )

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func getOptionsPopupHeight() -> CGFloat {
        OptionsPopupLayout.padding * 2
            + OptionsPopupLayout.headingHeight
            + CGFloat(SaveDestination.allCases.count) * OptionsPopupLayout.rowHeight
            + OptionsPopupLayout.separatorHeight
            + OptionsPopupLayout.separatorHeight
            + OptionsPopupLayout.resetHeight
    }

    private func getOptionsPopupWidth() -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: Constants.Menu.Button.textFont]
        let titles = SaveDestination.allCases.map(\.localizedTitle) + [AppText.resetSelectionAndMenuPositions]
        let textWidth = titles.map { $0.size(withAttributes: attributes).width }.max() ?? 0
        let preferredWidth = textWidth + OptionsPopupLayout.padding * 2 + OptionsPopupLayout.checkmarkWidth + 24
        return min(max(220, preferredWidth), screenFrame.width - OptionsPopupLayout.margin * 2)
    }

    private func getOptionsPopupHeadingRect(in popupRect: NSRect) -> NSRect {
        NSRect(
            x: popupRect.minX,
            y: popupRect.maxY - OptionsPopupLayout.padding - OptionsPopupLayout.headingHeight,
            width: popupRect.width,
            height: OptionsPopupLayout.headingHeight
        )
    }

    private func getOptionsPopupFileDestinationSeparatorRect(in popupRect: NSRect) -> NSRect? {
        guard let downloadsIndex = SaveDestination.allCases.firstIndex(of: .downloads) else {
            return nil
        }

        let y = popupRect.maxY
            - OptionsPopupLayout.padding
            - OptionsPopupLayout.headingHeight
            - CGFloat(downloadsIndex + 1) * OptionsPopupLayout.rowHeight
            - OptionsPopupLayout.separatorHeight
        return NSRect(x: popupRect.minX, y: y, width: popupRect.width, height: OptionsPopupLayout.separatorHeight)
    }

    private func getOptionsPopupSeparatorRect(in popupRect: NSRect) -> NSRect {
        let y = popupRect.maxY
            - OptionsPopupLayout.padding
            - OptionsPopupLayout.headingHeight
            - CGFloat(SaveDestination.allCases.count) * OptionsPopupLayout.rowHeight
            - OptionsPopupLayout.separatorHeight
            - OptionsPopupLayout.separatorHeight
        return NSRect(x: popupRect.minX, y: y, width: popupRect.width, height: OptionsPopupLayout.separatorHeight)
    }

    private func getOptionsPopupRect(for target: OptionsPopupTarget, in popupRect: NSRect) -> NSRect? {
        let firstRowMaxY = popupRect.maxY - OptionsPopupLayout.padding - OptionsPopupLayout.headingHeight

        switch target {
        case .destination(let destination):
            guard let index = SaveDestination.allCases.firstIndex(of: destination) else { return nil }
            let separatorOffset = index > (SaveDestination.allCases.firstIndex(of: .downloads) ?? .max)
                ? OptionsPopupLayout.separatorHeight
                : 0
            return NSRect(
                x: popupRect.minX,
                y: firstRowMaxY - CGFloat(index + 1) * OptionsPopupLayout.rowHeight - separatorOffset,
                width: popupRect.width,
                height: OptionsPopupLayout.rowHeight
            )
        case .reset:
            return NSRect(
                x: popupRect.minX,
                y: popupRect.minY + OptionsPopupLayout.padding,
                width: popupRect.width,
                height: OptionsPopupLayout.resetHeight
            )
        }
    }

    private func invalidateOverlay() {
        guard let overlayView else { return }
        overlayView.setNeedsDisplay(overlayView.bounds)
    }

    private func updateHoverState(menuControl: MenuControl?, popupTarget: OptionsPopupTarget?) {
        guard hoveredMenuControl != menuControl || hoveredOptionsPopupTarget != popupTarget else { return }

        hoveredMenuControl = menuControl
        hoveredOptionsPopupTarget = popupTarget
        invalidateOverlay()
    }
}
