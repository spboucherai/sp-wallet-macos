// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Tests/FormattingTests.swift
// Description: Unit tests of the app-side logic that must never distort a figure: exact amount rendering, CSV escaping, review lines built from an intent, error texts.
import Testing
import Foundation
import SPWalletCore
@testable import SPWallet

@Suite struct FormattingTests {
    @Test func amountsAreGroupedNeverRounded() {
        let sep = Locale.current.decimalSeparator ?? ","
        #expect(Fmt.amount("1234567.890000000000000001") == "1\u{202F}234\u{202F}567\(sep)890000000000000001")
        #expect(Fmt.amount("0.1") == "0\(sep)1")
        #expect(Fmt.amount("1000") == "1\u{202F}000")
        #expect(Fmt.amount(nil) == "—")
        // a shortened display says it is shortened, and truncates (never rounds up)
        #expect(Fmt.amount("0.123456789999", maxFraction: 8) == "0\(sep)12345678…")
        #expect(Fmt.amount("-5.5") == "−5\(sep)5")
    }
    @Test func fiatIsAlwaysMarkedAsEstimate() {
        #expect(Fmt.fiat(12.5, .cad).hasPrefix("≈ "))
        #expect(Fmt.fiat(nil, .usd) == "—")
    }
    @Test func addressesAreChunkedWithoutLoss() {
        let a = "0xA2dd4254339C03485579a47f198AD57032dac650"
        #expect(Fmt.chunked(a).replacingOccurrences(of: " ", with: "") == a)
        #expect(Fmt.short(a) == "0xA2dd42…dac650")
    }
    @Test func csvCellsCannotInjectFormulas() {
        #expect(ActivityExport.cell("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(ActivityExport.cell("+1") == "\"'+1\"")
        #expect(ActivityExport.cell("@cmd") == "\"'@cmd\"")
        #expect(ActivityExport.cell("normal, \"quoted\"") == "\"normal, \"\"quoted\"\"\"")
    }
    @Test func onlyFinalizedIsSuccess() {
        for s in ProposalState.allCases where s != .finalized { #expect(!s.isSuccess) }
        #expect(ErrorText.state(.broadcast).contains("non confirmée"))
        #expect(ErrorText.state(.notBroadcast).contains("NON diffusée"))
        #expect(ErrorText.activityState("some_future_state") == "some_future_state")
    }
    @Test func approvalRefusalsSayNothingWasSigned() {
        for e in [ApprovalError.challengeMismatch, .wrongRelyingParty("evil.example"), .userVerificationNotRequired, .unsupported("x"), .inconsistent("amount")] {
            #expect(ErrorText.approval(e).contains("Rien n’a été signé"))
        }
    }
}

@Suite struct IntentReviewTests {
    static func intent(_ extra: String = "", to: String = "0x903B11a2b7C0c2d5A1cB0B2f2c5C9e3fA682367C") throws -> Intent {
        let json = """
        {"v":1,"proposalId":"11111111-1111-4111-8111-111111111111","keyId":"spw-test-key","network":"base","chainRef":"eip155:8453","asset":"native","symbol":"ETH","decimals":18,
         "amount":"1000000000000000","from":"0xA2dd4254339C03485579a47f198AD57032dac650","to":"\(to)","maxFee":"90000000000000",
         "createdAt":1794950000,"expiresAt":1794950120,"policyVersion":4,"evm":{"nonce":7,"gasLimit":"21000","maxFeePerGas":"1000000000","maxPriorityFeePerGas":"1000000"}\(extra)}
        """
        return try Intent(served: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }
    @Test func reviewShowsFullAddressExactAmountFeeAndTotal() throws {
        let i = try Self.intent()
        let lines = IntentReview.lines(i, network: nil, ownAddresses: [:])
        let text = lines.map { "\($0.label)|\($0.value)" }.joined(separator: "\n")
        #expect(text.contains("0x903B11a2b7C0c2d5A1cB0B2f2c5C9e3fA682367C"))       // never abbreviated
        #expect(text.contains("1000000000000000 unités de base"))
        #expect(text.contains("Frais de réseau maximum"))
        let sep = Locale.current.decimalSeparator ?? ","
        #expect(text.contains("Total maximum débité|0\(sep)00109 ETH"))               // amount + fee ceiling, exact
        #expect(text.contains("spw-test-key"))
    }
    @Test func swapReviewNamesRouterMinimumAndSpendApproval() throws {
        let i = try Self.intent(#","swap":{"provider":"kyberswap","toAsset":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","minOut":"2400000","router":"0x6131B5fae19EA4f9D964eAc0408E4408b66337b5","dataHash":"\#(String(repeating: "ab", count: 32))","approveGas":"60000"}"#, to: "0xA2dd4254339C03485579a47f198AD57032dac650")
        let text = IntentReview.lines(i, network: nil, ownAddresses: [:]).map(\.value).joined(separator: "\n")
        #expect(text.contains("0x6131B5fae19EA4f9D964eAc0408E4408b66337b5"))
        #expect(text.contains("2400000"))
        #expect(text.contains("approbation ERC-20"))
    }
}
