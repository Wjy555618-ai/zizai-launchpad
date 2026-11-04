import AppKit
import QuartzCore
import SwiftUI

/// Keeps edit-mode motion on Core Animation's compositor. SwiftUI receives
/// only management-state changes; it never publishes a value on every frame.
struct ApplicationManagementJiggleIcon: NSViewRepresentable {
    let image: NSImage
    let renderedSize: CGFloat
    let identifier: String
    let isJiggling: Bool

    func makeNSView(context: Context) -> ApplicationManagementJiggleImageView {
        ApplicationManagementJiggleImageView()
    }

    func updateNSView(
        _ nsView: ApplicationManagementJiggleImageView,
        context: Context
    ) {
        nsView.configure(
            image: image,
            renderedSize: renderedSize,
            identifier: identifier,
            isJiggling: isJiggling
        )
    }
}

@MainActor
final class ApplicationManagementJiggleImageView: NSView {
    static let animationKey = "zizai.application-management.jiggle"

    private let imageView = NSImageView()
    private var renderedSize: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.unregisterDraggedTypes()
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: renderedSize, height: renderedSize)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    func configure(
        image: NSImage,
        renderedSize: CGFloat,
        identifier: String,
        isJiggling: Bool
    ) {
        if imageView.image !== image { imageView.image = image }
        if self.renderedSize != renderedSize {
            self.renderedSize = renderedSize
            invalidateIntrinsicContentSize()
        }
        configureShadow(for: renderedSize)
        synchronizeJiggle(isJiggling, identifier: identifier)
    }

    var installedJiggleAnimation: CAAnimation? {
        imageView.layer?.animation(forKey: Self.animationKey)
    }

    private func configureShadow(for size: CGFloat) {
        guard let layer = imageView.layer else { return }
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = Float(ZizaiShadow.iconOpacity)
        layer.shadowRadius = size * ZizaiShadow.iconRadiusScale
        layer.shadowOffset = CGSize(width: 0, height: -size * ZizaiShadow.iconYScale)
    }

    private func synchronizeJiggle(_ active: Bool, identifier: String) {
        guard let layer = imageView.layer else { return }
        guard active else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard layer.animation(forKey: Self.animationKey) == nil else { return }

        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = ApplicationManagementMotion.jiggleRotationValues

        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        translation.values = ApplicationManagementMotion.jiggleTranslationValues

        let animation = CAAnimationGroup()
        animation.animations = [rotation, translation]
        animation.duration = ApplicationManagementMotion.jiggleDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime =
            layer.convertTime(CACurrentMediaTime(), from: nil)
            - ApplicationManagementMotion.jigglePhase(for: identifier)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.animationKey)
    }
}
