import UIKit

enum ShareScoreService {
    static func present(
        score: Int,
        bestScore: Int,
        modeTitle: String,
        accent: UIColor,
        background: UIColor
    ) {
        Task { @MainActor in
            guard let presenter = AppPresenter.topViewController() else { return }

            let image = makeCard(
                score: score,
                bestScore: bestScore,
                modeTitle: modeTitle,
                accent: accent,
                background: background
            )

            let message = modeTitle == "DAILY ORBIT"
                ? "Fiz \(score) pontos no Daily Orbit. Consegue bater?"
                : "Fiz \(score) pontos no Orbit. Consegue bater?"

            let controller = UIActivityViewController(
                activityItems: [message, image],
                applicationActivities: nil
            )

            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
            }

            presenter.present(controller, animated: true)
        }
    }

    @MainActor
    private static func makeCard(
        score: Int,
        bestScore: Int,
        modeTitle: String,
        accent: UIColor,
        background: UIColor
    ) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cg = context.cgContext
            background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let center = CGPoint(x: size.width / 2, y: 575)
            let outerRadius: CGFloat = 285
            let innerRadius: CGFloat = 165

            cg.setLineWidth(7)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            cg.strokeEllipse(in: CGRect(
                x: center.x - outerRadius,
                y: center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            ))
            cg.strokeEllipse(in: CGRect(
                x: center.x - innerRadius,
                y: center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ))

            cg.setStrokeColor(accent.cgColor)
            cg.setLineCap(.round)
            cg.setLineWidth(26)
            cg.addArc(
                center: center,
                radius: outerRadius,
                startAngle: -.pi * 0.43,
                endAngle: -.pi * 0.16,
                clockwise: false
            )
            cg.strokePath()
            cg.addArc(
                center: center,
                radius: outerRadius,
                startAngle: .pi * 0.43,
                endAngle: .pi * 0.69,
                clockwise: false
            )
            cg.strokePath()

            let playerAngle: CGFloat = .pi * 1.18
            let playerPoint = CGPoint(
                x: center.x + cos(playerAngle) * outerRadius,
                y: center.y + sin(playerAngle) * outerRadius
            )
            UIColor.white.withAlphaComponent(0.18).setFill()
            cg.fillEllipse(in: CGRect(x: playerPoint.x - 40, y: playerPoint.y - 40, width: 80, height: 80))
            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: playerPoint.x - 24, y: playerPoint.y - 24, width: 48, height: 48))

            drawCentered(
                "ORBIT",
                y: 115,
                font: .systemFont(ofSize: 82, weight: .black),
                color: .white,
                canvasWidth: size.width
            )
            drawCentered(
                modeTitle,
                y: 225,
                font: .systemFont(ofSize: 30, weight: .semibold),
                color: UIColor.white.withAlphaComponent(0.58),
                canvasWidth: size.width
            )
            drawCentered(
                "\(score)",
                y: 460,
                font: .monospacedDigitSystemFont(ofSize: 190, weight: .bold),
                color: .white,
                canvasWidth: size.width
            )

            drawCentered(
                "MELHOR  \(bestScore)",
                y: 920,
                font: .monospacedDigitSystemFont(ofSize: 34, weight: .semibold),
                color: UIColor.white.withAlphaComponent(0.62),
                canvasWidth: size.width
            )
            drawCentered(
                "CONSEGUE BATER?",
                y: 1080,
                font: .systemFont(ofSize: 52, weight: .bold),
                color: .white,
                canvasWidth: size.width
            )
            drawCentered(
                "Um toque. Duas órbitas.",
                y: 1160,
                font: .systemFont(ofSize: 31, weight: .medium),
                color: UIColor.white.withAlphaComponent(0.48),
                canvasWidth: size.width
            )

            accent.setFill()
            cg.fillEllipse(in: CGRect(x: size.width / 2 - 8, y: 1270, width: 16, height: 16))
        }
    }

    @MainActor
    private static func drawCentered(
        _ text: String,
        y: CGFloat,
        font: UIFont,
        color: UIColor,
        canvasWidth: CGFloat
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: text).draw(
            in: CGRect(x: 50, y: y, width: canvasWidth - 100, height: font.lineHeight * 1.25),
            withAttributes: attributes
        )
    }
}
