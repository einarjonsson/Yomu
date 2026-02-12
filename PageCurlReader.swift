import SwiftUI
import UIKit

struct PageCurlReader: UIViewControllerRepresentable {

    enum ReadingDirection { case ltr, rtl }
    enum TapZone { case left, middle, right }

    let pages: [UIImage]
    @Binding var currentIndex: Int
    @Binding var chromeHidden: Bool

    /// Manga default = RTL
    var direction: ReadingDirection = .rtl

    /// In landscape, show the cover as a “single” page by pairing it with a blank side.
    var useSingleCoverInLandscape: Bool = true

    /// Double-tap zoom target
    var doubleTapZoomScale: CGFloat = 2.0

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )

        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false // ✅ one VC per turn (stable)

        context.coordinator.parent = self

        if !pages.isEmpty {
            let idx = clamp(currentIndex)
            pvc.setViewControllers(
                [context.coordinator.makeCurrentVC(for: pvc, pageIndex: idx)],
                direction: .forward,
                animated: false
            )
        }

        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard !pages.isEmpty else { return }

        let clamped = clamp(currentIndex)
        if clamped != currentIndex {
            DispatchQueue.main.async { self.currentIndex = clamped }
            return
        }

        // Swap VC type when orientation changes (single <-> spread)
        let desired = context.coordinator.makeCurrentVC(for: uiViewController, pageIndex: clamped)
        let visible = uiViewController.viewControllers?.first

        if let v = visible as? SinglePageVC, let d = desired as? SinglePageVC, v.index == d.index { return }
        if let v = visible as? SpreadPageVC, let d = desired as? SpreadPageVC, v.spreadIndex == d.spreadIndex { return }

        uiViewController.setViewControllers([desired], direction: .forward, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func clamp(_ i: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(i, 0), pages.count - 1)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlReader

        init(parent: PageCurlReader) { self.parent = parent }

        // MARK: Tap handling

        private func zone(for point: CGPoint, in bounds: CGRect) -> TapZone {
            let x = point.x / max(bounds.width, 1)
            if x < 0.33 { return .left }
            if x > 0.66 { return .right }
            return .middle
        }

        private func handleTap(pvc: UIPageViewController, point: CGPoint) {
            let z = zone(for: point, in: pvc.view.bounds)

            switch z {
            case .middle:
                DispatchQueue.main.async { self.parent.chromeHidden.toggle() }

            case .left:
                // Manga RTL: left tap = go backward (lower index)
                if parent.direction == .rtl { goPrev(pvc: pvc) } else { goNext(pvc: pvc) }

            case .right:
                // Manga RTL: right tap = go forward (higher index)
                if parent.direction == .rtl { goNext(pvc: pvc) } else { goPrev(pvc: pvc) }
            }
        }

        private func isLandscape(_ pvc: UIPageViewController) -> Bool {
            pvc.view.bounds.width > pvc.view.bounds.height
        }

        private func goNext(pvc: UIPageViewController) {
            guard let current = pvc.viewControllers?.first else { return }
            guard let nextVC = pageViewController(pvc, viewControllerAfter: current) else { return }

            // Landscape spreads: keep forward (stable)
            if isLandscape(pvc) {
                pvc.setViewControllers([nextVC], direction: .forward, animated: true)
                return
            }

            // Portrait: make curl feel correct for RTL
            let dir: UIPageViewController.NavigationDirection =
                (parent.direction == .rtl) ? .reverse : .forward

            pvc.setViewControllers([nextVC], direction: dir, animated: true)
        }

        private func goPrev(pvc: UIPageViewController) {
            guard let current = pvc.viewControllers?.first else { return }
            guard let prevVC = pageViewController(pvc, viewControllerBefore: current) else { return }

            if isLandscape(pvc) {
                pvc.setViewControllers([prevVC], direction: .reverse, animated: true)
                return
            }

            let dir: UIPageViewController.NavigationDirection =
                (parent.direction == .rtl) ? .forward : .reverse

            pvc.setViewControllers([prevVC], direction: dir, animated: true)
        }

        // MARK: VC selection

        func makeCurrentVC(for pvc: UIPageViewController, pageIndex: Int) -> UIViewController {
            let landscape = pvc.view.bounds.width > pvc.view.bounds.height
            if landscape {
                let s = spreadIndex(forPageIndex: pageIndex)
                return makeSpreadVC(spread: s, pvc: pvc)
            } else {
                return makeSingleVC(index: pageIndex, pvc: pvc)
            }
        }

        // MARK: DataSource

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {

            let landscape = pageViewController.view.bounds.width > pageViewController.view.bounds.height

            if landscape {
                guard let vc = viewController as? SpreadPageVC else { return nil }
                let target = (parent.direction == .rtl) ? (vc.spreadIndex + 1) : (vc.spreadIndex - 1)
                return makeSpreadVCIfValid(spread: target, pvc: pageViewController)
            } else {
                guard let vc = viewController as? SinglePageVC else { return nil }
                let i = vc.index

                if parent.direction == .rtl {
                    let next = i + 1
                    guard next < parent.pages.count else { return nil }
                    return makeSingleVC(index: next, pvc: pageViewController)
                } else {
                    let prev = i - 1
                    guard prev >= 0 else { return nil }
                    return makeSingleVC(index: prev, pvc: pageViewController)
                }
            }
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {

            let landscape = pageViewController.view.bounds.width > pageViewController.view.bounds.height

            if landscape {
                guard let vc = viewController as? SpreadPageVC else { return nil }
                let target = (parent.direction == .rtl) ? (vc.spreadIndex - 1) : (vc.spreadIndex + 1)
                return makeSpreadVCIfValid(spread: target, pvc: pageViewController)
            } else {
                guard let vc = viewController as? SinglePageVC else { return nil }
                let i = vc.index

                if parent.direction == .rtl {
                    let prev = i - 1
                    guard prev >= 0 else { return nil }
                    return makeSingleVC(index: prev, pvc: pageViewController)
                } else {
                    let next = i + 1
                    guard next < parent.pages.count else { return nil }
                    return makeSingleVC(index: next, pvc: pageViewController)
                }
            }
        }

        // MARK: Delegate (update binding)

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed else { return }

            let landscape = pageViewController.view.bounds.width > pageViewController.view.bounds.height

            if landscape, let vc = pageViewController.viewControllers?.first as? SpreadPageVC {
                // Keep currentIndex in sync:
                // RTL => use right page index; LTR => use left page index
                let idx = (parent.direction == .rtl) ? (vc.rightIndex ?? 0) : (vc.leftIndex ?? 0)
                parent.currentIndex = clampIndex(idx)
                if let resettable = pageViewController.viewControllers?.first as? ZoomResettable {
                    resettable.resetZoom(animated: true)
                }
            } else if let vc = pageViewController.viewControllers?.first as? SinglePageVC {
                parent.currentIndex = clampIndex(vc.index)
                if let resettable = pageViewController.viewControllers?.first as? ZoomResettable {
                    resettable.resetZoom(animated: true)
                }
            }
        }

        // MARK: Index helpers

        private func clampIndex(_ i: Int) -> Int {
            guard !parent.pages.isEmpty else { return 0 }
            return min(max(i, 0), parent.pages.count - 1)
        }

        // MARK: VC builders

        private func makeSingleVC(index: Int, pvc: UIPageViewController) -> SinglePageVC {
            let i = clampIndex(index)
            return SinglePageVC(image: parent.pages[i], index: i, doubleTapZoomScale: parent.doubleTapZoomScale) { [weak self, weak pvc] point in
                guard let self, let pvc else { return }
                self.handleTap(pvc: pvc, point: point)
            }
        }

        private func makeSpreadVCIfValid(spread s: Int, pvc: UIPageViewController) -> SpreadPageVC? {
            guard s >= 0, s <= maxSpreadIndex() else { return nil }
            return makeSpreadVC(spread: s, pvc: pvc)
        }

        private func makeSpreadVC(spread s: Int, pvc: UIPageViewController) -> SpreadPageVC {
            let (leftIdx, rightIdx) = spreadIndices(forSpread: s)

            let leftImage  = (leftIdx  != nil) ? parent.pages[leftIdx!]  : nil
            let rightImage = (rightIdx != nil) ? parent.pages[rightIdx!] : nil

            return SpreadPageVC(
                left: leftImage,
                right: rightImage,
                spreadIndex: s,
                leftIndex: leftIdx,
                rightIndex: rightIdx,
                doubleTapZoomScale: parent.doubleTapZoomScale
            ) { [weak self, weak pvc] point in
                guard let self, let pvc else { return }
                self.handleTap(pvc: pvc, point: point)
            }
        }

        // MARK: Spread math (no skipping)

        private func spreadIndex(forPageIndex i: Int) -> Int {
            if parent.useSingleCoverInLandscape {
                if i <= 0 { return 0 }
                return (i + 1) / 2
            } else {
                return i / 2
            }
        }

        private func maxSpreadIndex() -> Int {
            guard !parent.pages.isEmpty else { return 0 }
            return spreadIndex(forPageIndex: parent.pages.count - 1)
        }

        private func spreadIndices(forSpread s: Int) -> (left: Int?, right: Int?) {
            let n = parent.pages.count
            guard n > 0 else { return (nil, nil) }

            if parent.useSingleCoverInLandscape {
                if s == 0 {
                    if parent.direction == .rtl { return (left: nil, right: 0) }
                    else { return (left: 0, right: nil) }
                }

                let a = 2 * s - 1
                let b = 2 * s

                if parent.direction == .rtl {
                    let right = (a < n) ? a : nil
                    let left  = (b < n) ? b : nil
                    return (left: left, right: right)
                } else {
                    let left  = (a < n) ? a : nil
                    let right = (b < n) ? b : nil
                    return (left: left, right: right)
                }
            } else {
                let first = 2 * s
                let second = first + 1

                if parent.direction == .rtl {
                    let right = (first < n) ? first : nil
                    let left  = (second < n) ? second : nil
                    return (left: left, right: right)
                } else {
                    let left  = (first < n) ? first : nil
                    let right = (second < n) ? second : nil
                    return (left: left, right: right)
                }
            }
        }
    }
}

protocol ZoomResettable: AnyObject {
    func resetZoom(animated: Bool)
}

// MARK: - Portrait single page VC

final class SinglePageVC: UIViewController, UIScrollViewDelegate, ZoomResettable {
    let index: Int
    private let image: UIImage
    private let onTap: (CGPoint) -> Void
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let doubleTapZoomScale: CGFloat

    init(image: UIImage, index: Int, doubleTapZoomScale: CGFloat, onTap: @escaping (CGPoint) -> Void) {
        self.image = image
        self.index = index
        self.onTap = onTap
        self.doubleTapZoomScale = doubleTapZoomScale
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.05, alpha: 1.0)

        // Configure scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Configure image view
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false

        // Ensure single tap waits for potential double tap
        singleTap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)

        // Initial centering
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centerContent(in: self.scrollView, contentView: self.imageView)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    private func centerContent(in scrollView: UIScrollView, contentView: UIView) {
        let boundsSize = scrollView.bounds.size
        let contentSize = contentView.frame.size

        let horizontalInset = max(0, (boundsSize.width - contentSize.width) * 0.5)
        let verticalInset = max(0, (boundsSize.height - contentSize.height) * 0.5)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent(in: scrollView, contentView: imageView)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        centerContent(in: scrollView, contentView: imageView)
    }

    @objc private func didTap(_ gr: UITapGestureRecognizer) {
        onTap(gr.location(in: view))
    }

    @objc private func didDoubleTap(_ gr: UITapGestureRecognizer) {
        let targetZoom: CGFloat = (scrollView.zoomScale < doubleTapZoomScale) ? doubleTapZoomScale : 1.0
        let pointInView = gr.location(in: imageView)

        let scrollViewSize = scrollView.bounds.size
        let w = scrollViewSize.width / targetZoom
        let h = scrollViewSize.height / targetZoom
        let x = pointInView.x - (w / 2.0)
        let y = pointInView.y - (h / 2.0)
        let zoomRect = CGRect(x: x, y: y, width: w, height: h)

        scrollView.zoom(to: zoomRect, animated: true)
    }

    func resetZoom(animated: Bool) {
        let actions = {
            self.scrollView.setZoomScale(1.0, animated: animated)
            self.centerContent(in: self.scrollView, contentView: self.imageView)
        }
        if animated {
            actions()
        } else {
            actions()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.scrollView.setZoomScale(1.0, animated: false)
        }, completion: { _ in
            self.centerContent(in: self.scrollView, contentView: self.imageView)
        })
    }
}

// MARK: - Landscape spread VC (no gutter, no shadow)

final class SpreadPageVC: UIViewController, UIScrollViewDelegate, ZoomResettable {
    let spreadIndex: Int
    let leftIndex: Int?
    let rightIndex: Int?
    private let leftImage: UIImage?
    private let rightImage: UIImage?
    private let doubleTapZoomScale: CGFloat

    private let leftScrollView = UIScrollView()
    private let rightScrollView = UIScrollView()
    private let leftView = UIImageView()
    private let rightView = UIImageView()

    // Premium seam shadow (no line)
    private let seamView = UIView()
    private let seamGradient = CAGradientLayer()

    private let onTap: (CGPoint) -> Void

    init(left: UIImage?, right: UIImage?, spreadIndex: Int, leftIndex: Int?, rightIndex: Int?, doubleTapZoomScale: CGFloat, onTap: @escaping (CGPoint) -> Void) {
        self.leftImage = left
        self.rightImage = right
        self.spreadIndex = spreadIndex
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.onTap = onTap
        self.doubleTapZoomScale = doubleTapZoomScale
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.05, alpha: 1.0)

        // Configure scroll views
        [leftScrollView, rightScrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.delegate = self
            $0.minimumZoomScale = 1.0
            $0.maximumZoomScale = 4.0
            $0.bouncesZoom = true
            $0.bounces = true
            $0.decelerationRate = .fast
            $0.alwaysBounceVertical = false
            $0.alwaysBounceHorizontal = false
            $0.showsHorizontalScrollIndicator = false
            $0.showsVerticalScrollIndicator = false
            view.addSubview($0)
        }

        // Configure image views
        [leftView, rightView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.contentMode = .scaleAspectFit
            $0.backgroundColor = .clear
        }
        leftView.image = leftImage
        rightView.image = rightImage

        leftScrollView.addSubview(leftView)
        rightScrollView.addSubview(rightView)

        // Layout scroll views side by side
        NSLayoutConstraint.activate([
            leftScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            leftScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftScrollView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

            rightScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rightScrollView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5)
        ])

        // Pin images to their scroll view content
        NSLayoutConstraint.activate([
            leftView.leadingAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.leadingAnchor),
            leftView.trailingAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.trailingAnchor),
            leftView.topAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.topAnchor),
            leftView.bottomAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.bottomAnchor),
            leftView.widthAnchor.constraint(equalTo: leftScrollView.frameLayoutGuide.widthAnchor),
            leftView.heightAnchor.constraint(equalTo: leftScrollView.frameLayoutGuide.heightAnchor),

            rightView.leadingAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.leadingAnchor),
            rightView.trailingAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.trailingAnchor),
            rightView.topAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.topAnchor),
            rightView.bottomAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.bottomAnchor),
            rightView.widthAnchor.constraint(equalTo: rightScrollView.frameLayoutGuide.widthAnchor),
            rightView.heightAnchor.constraint(equalTo: rightScrollView.frameLayoutGuide.heightAnchor)
        ])

        // ✅ Seam overlay (very subtle depth, no visible gutter)
        seamView.translatesAutoresizingMaskIntoConstraints = false
        seamView.isUserInteractionEnabled = false
        seamView.backgroundColor = .clear
        view.addSubview(seamView)

        NSLayoutConstraint.activate([
            seamView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            seamView.topAnchor.constraint(equalTo: view.topAnchor),
            seamView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            seamView.widthAnchor.constraint(equalToConstant: 40) // shadow "band" width
        ])

        seamGradient.startPoint = CGPoint(x: 0.0, y: 0.5)
        seamGradient.endPoint   = CGPoint(x: 1.0, y: 0.5)
        seamGradient.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.18).cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor
        ]
        seamGradient.locations = [0.0, 0.5, 1.0]
        seamView.layer.addSublayer(seamGradient)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false

        let leftDoubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapLeft(_:)))
        leftDoubleTap.numberOfTapsRequired = 2
        leftDoubleTap.cancelsTouchesInView = false

        let rightDoubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapRight(_:)))
        rightDoubleTap.numberOfTapsRequired = 2
        rightDoubleTap.cancelsTouchesInView = false

        // Single tap should wait for double taps on either side
        singleTap.require(toFail: leftDoubleTap)
        singleTap.require(toFail: rightDoubleTap)

        view.addGestureRecognizer(singleTap)
        leftScrollView.addGestureRecognizer(leftDoubleTap)
        rightScrollView.addGestureRecognizer(rightDoubleTap)

        // Initial centering for both sides
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centerContent(in: self.leftScrollView, contentView: self.leftView)
            self.centerContent(in: self.rightScrollView, contentView: self.rightView)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        seamGradient.frame = seamView.bounds
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if scrollView === leftScrollView { return leftView }
        if scrollView === rightScrollView { return rightView }
        return nil
    }

    private func centerContent(in scrollView: UIScrollView, contentView: UIView) {
        let boundsSize = scrollView.bounds.size
        let contentSize = contentView.frame.size

        let horizontalInset = max(0, (boundsSize.width - contentSize.width) * 0.5)
        let verticalInset = max(0, (boundsSize.height - contentSize.height) * 0.5)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if scrollView === leftScrollView { centerContent(in: scrollView, contentView: leftView) }
        else if scrollView === rightScrollView { centerContent(in: scrollView, contentView: rightView) }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scrollView === leftScrollView { centerContent(in: scrollView, contentView: leftView) }
        else if scrollView === rightScrollView { centerContent(in: scrollView, contentView: rightView) }
    }

    @objc private func didTap(_ gr: UITapGestureRecognizer) {
        onTap(gr.location(in: view))
    }

    @objc private func didDoubleTapLeft(_ gr: UITapGestureRecognizer) {
        handleDoubleTap(in: leftScrollView, contentView: leftView, recognizer: gr)
    }

    @objc private func didDoubleTapRight(_ gr: UITapGestureRecognizer) {
        handleDoubleTap(in: rightScrollView, contentView: rightView, recognizer: gr)
    }

    private func handleDoubleTap(in scrollView: UIScrollView, contentView: UIView, recognizer: UITapGestureRecognizer) {
        let targetZoom: CGFloat = (scrollView.zoomScale < doubleTapZoomScale) ? doubleTapZoomScale : 1.0
        let pointInView = recognizer.location(in: contentView)

        let scrollViewSize = scrollView.bounds.size
        let w = scrollViewSize.width / targetZoom
        let h = scrollViewSize.height / targetZoom
        let x = pointInView.x - (w / 2.0)
        let y = pointInView.y - (h / 2.0)
        let zoomRect = CGRect(x: x, y: y, width: w, height: h)

        scrollView.zoom(to: zoomRect, animated: true)
    }

    func resetZoom(animated: Bool) {
        [leftScrollView, rightScrollView].forEach { sv in
            sv.setZoomScale(1.0, animated: animated)
        }
        centerContent(in: leftScrollView, contentView: leftView)
        centerContent(in: rightScrollView, contentView: rightView)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.leftScrollView.setZoomScale(1.0, animated: false)
            self.rightScrollView.setZoomScale(1.0, animated: false)
        }, completion: { _ in
            self.centerContent(in: self.leftScrollView, contentView: self.leftView)
            self.centerContent(in: self.rightScrollView, contentView: self.rightView)
        })
    }
}

