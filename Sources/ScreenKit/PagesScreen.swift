#if canImport(UIKit)
import UIKit

/// A fixed sequence of pages with native horizontal swipe navigation.
/// An empty sequence is allowed with initialIndex zero; other indices must exist.
@MainActor
public struct PagesScreen: ScreenRepresentable {
    private let pages: [AnyScreen]
    private let initialIndex: Int

    public init(_ pages: [AnyScreen], initialIndex: Int = 0) {
        precondition(
            pages.isEmpty ? initialIndex == 0 : pages.indices.contains(initialIndex),
            "Initial page index must exist, or be zero for an empty sequence"
        )
        self.pages = pages
        self.initialIndex = initialIndex
    }

    public func makeViewController() -> UIPageViewController {
        PagesViewController(controllers: pages.map { $0.makeViewController() }, initialIndex: initialIndex)
    }
}

@MainActor
private final class PagesViewController: UIPageViewController {
    // UIKit's dataSource property is weak. Keep its owner for this controller's lifetime.
    private let pagesOwner: PagesDataSource

    init(controllers: [UIViewController], initialIndex: Int) {
        pagesOwner = PagesDataSource(controllers: controllers)
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        dataSource = pagesOwner
        if !controllers.isEmpty {
            setViewControllers([controllers[initialIndex]], direction: .forward, animated: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use PagesScreen.makeViewController()")
    }
}

@MainActor
private final class PagesDataSource: NSObject, UIPageViewControllerDataSource {
    private let controllers: [UIViewController]

    init(controllers: [UIViewController]) {
        self.controllers = controllers
        super.init()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = controllers.firstIndex(where: { $0 === viewController }), index > 0 else { return nil }
        return controllers[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = controllers.firstIndex(where: { $0 === viewController }), index + 1 < controllers.count else { return nil }
        return controllers[index + 1]
    }
}
#endif
