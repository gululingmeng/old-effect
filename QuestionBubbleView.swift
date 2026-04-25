import UIKit

final class QuestionBubbleView: UIView {

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let textLabel = UILabel()
    private let borderLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()

    private let cornerRadius: CGFloat = 22
    private let tailSize = CGSize(width: 24, height: 14)
    private let contentInsets = UIEdgeInsets(top: 16, left: 18, bottom: 28, right: 18)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        isOpaque = false
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.textColor = .white
        textLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        textLabel.textAlignment = .left
        blurView.contentView.addSubview(textLabel)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        borderLayer.lineWidth = 1.0
        layer.addSublayer(borderLayer)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: contentInsets.left),
            textLabel.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -contentInsets.right),
            textLabel.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: contentInsets.top),
            textLabel.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -contentInsets.bottom)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        textLabel.preferredMaxLayoutWidth = max(0, bounds.width - contentInsets.left - contentInsets.right)

        let path = bubblePath(in: bounds)
        maskLayer.path = path.cgPath
        blurView.layer.mask = maskLayer
        borderLayer.path = path.cgPath
        borderLayer.frame = bounds
        layer.shadowPath = path.cgPath
    }

    func setText(_ text: String) {
        textLabel.text = text
        accessibilityLabel = text
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
    }

    override var intrinsicContentSize: CGSize {
        let maxWidth = bounds.width > 0 ? bounds.width : min(UIScreen.main.bounds.width * 1, 420)
        let targetTextWidth = max(144, maxWidth - contentInsets.left - contentInsets.right)
        let textSize = textLabel.sizeThatFits(CGSize(width: targetTextWidth, height: CGFloat.greatestFiniteMagnitude))
        let width = min(maxWidth, max(340, ceil(textSize.width) + contentInsets.left + contentInsets.right))
        let height = ceil(textSize.height) + contentInsets.top + contentInsets.bottom + tailSize.height
        return CGSize(width: width, height: max(74, height))
    }

    private func bubblePath(in rect: CGRect) -> UIBezierPath {
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(0, rect.height - tailSize.height)
        )

        let tailTipX = min(max(bubbleRect.maxX - 34, bubbleRect.minX + cornerRadius + tailSize.width), bubbleRect.maxX - cornerRadius)
        let tailStartX = tailTipX - tailSize.width
        let tailEndX = tailTipX - 4

        let path = UIBezierPath()
        path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
        path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
        path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY + cornerRadius),
                    radius: cornerRadius,
                    startAngle: -.pi / 2,
                    endAngle: 0,
                    clockwise: true)
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
        path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: true)

        path.addLine(to: CGPoint(x: tailEndX, y: bubbleRect.maxY))
        path.addQuadCurve(to: CGPoint(x: tailTipX, y: bubbleRect.maxY + tailSize.height),
                          controlPoint: CGPoint(x: tailTipX - 3, y: bubbleRect.maxY + tailSize.height * 0.22))
        path.addQuadCurve(to: CGPoint(x: tailStartX, y: bubbleRect.maxY),
                          controlPoint: CGPoint(x: tailTipX - tailSize.width * 0.72, y: bubbleRect.maxY + tailSize.height * 0.42))

        path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
        path.addArc(withCenter: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .pi / 2,
                    endAngle: .pi,
                    clockwise: true)
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
        path.addArc(withCenter: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY + cornerRadius),
                    radius: cornerRadius,
                    startAngle: .pi,
                    endAngle: -.pi / 2,
                    clockwise: true)
        path.close()
        return path
    }
}
