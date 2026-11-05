import TapAskCore
import XCTest

final class PageLoadStateTests: XCTestCase {
    private let timeout = PageLoadFailure(domain: "NSURLErrorDomain", code: -1001)

    private var states: [PageLoadState] { [.idle, .loading, .loaded, .failed(timeout)] }

    func testFirstLoadTimeoutShowsNetworkTimeout() {
        let loading = nextPageLoadState(from: .idle, on: .start)
        let failed = nextPageLoadState(from: loading, on: .fail(domain: "NSURLErrorDomain", code: -1001))
        XCTAssertEqual(loading, .loading)
        XCTAssertEqual(failed, .failed(timeout))
        XCTAssertEqual(timeout.reason, "网络超时")
    }

    func testStartPreservesOnlyACommittedDocument() {
        for state in states {
            XCTAssertEqual(nextPageLoadState(from: state, on: .start), state == .loaded ? .loaded : .loading)
        }
    }

    func testCommitAlwaysMarksDocumentLoaded() {
        for state in states {
            XCTAssertEqual(nextPageLoadState(from: state, on: .commit), .loaded)
        }
    }

    func testCancellationPolicyInterruptionAndPluginHandlingLeaveEveryStateUnchanged() {
        let ignored: [PageLoadEvent] = [
            .fail(domain: "NSURLErrorDomain", code: -999),
            .fail(domain: "WebKitErrorDomain", code: 102),
            .fail(domain: "WebKitErrorDomain", code: 204),
        ]
        for state in states {
            for event in ignored {
                XCTAssertEqual(nextPageLoadState(from: state, on: event), state, "\(state), \(event)")
            }
        }
    }

    func testIgnoredCodesAreScopedToTheirErrorDomains() {
        for (domain, code) in [("WebKitErrorDomain", -999), ("NSURLErrorDomain", 102),
                               ("NSURLErrorDomain", 204)] {
            XCTAssertEqual(nextPageLoadState(from: .loading, on: .fail(domain: domain, code: code)),
                           .failed(PageLoadFailure(domain: domain, code: code)))
        }
    }

    func testFailuresPreserveTheCommittedPageAndReplaceOtherStates() {
        let failure = PageLoadFailure(domain: "NSURLErrorDomain", code: -1009)
        for state in states {
            XCTAssertEqual(nextPageLoadState(from: state, on: .fail(domain: failure.domain, code: failure.code)),
                           state == .loaded ? .loaded : .failed(failure))
        }
    }

    func testRetryFromFailureCanCommit() {
        let loading = nextPageLoadState(from: .failed(timeout), on: .start)
        XCTAssertEqual(loading, .loading)
        XCTAssertEqual(nextPageLoadState(from: loading, on: .commit), .loaded)
    }

    func testProcessTerminationStartsLoadingEvenAfterCommit() {
        for state in states {
            XCTAssertEqual(nextPageLoadState(from: state, on: .processTerminated), .loading)
        }
    }

    func testFailureReasonsAreShortAndUnknownCodesRemainVisible() {
        XCTAssertEqual(PageLoadFailure(domain: "NSURLErrorDomain", code: -1009).reason, "没有网络连接")
        for code in [-1003, -1004, -1005, -1200] {
            XCTAssertEqual(PageLoadFailure(domain: "NSURLErrorDomain", code: code).reason, "连不上服务器")
        }
        for (domain, code) in [("NSURLErrorDomain", -12345), ("CustomDomain", -1001)] {
            let reason = PageLoadFailure(domain: domain, code: code).reason
            XCTAssertTrue(reason.contains("加载失败"))
            XCTAssertTrue(reason.contains(String(code)))
        }
    }
}
