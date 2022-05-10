import Foundation
import XCTest
@testable import SolanaSwift
@testable import OrcaSwapSwift

final class SwapTests: XCTestCase {
    // MARK: - Properties
    fileprivate var orcaSwap: OrcaSwap<MockSolanaAPIClient2, BlockchainClient<MockSolanaAPIClient2>>!
    
    // MARK: - Setup
    override func setUp() async throws {
//        poolsRepository = getMockConfigs(network: "mainnet").pools
    }
    
    override func tearDown() async throws {
        orcaSwap = nil
    }
    
    // MARK: - Direct swap
    func testDirectSwapSOLToCreatedSPL() async throws {
        try await doTest(testJSONFile: "direct-swap-tests", testName: "solToCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSOLToNonCreatedSPL() async throws {
        try await doTest(testJSONFile: "direct-swap-tests", testName: "solToNonCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSPLToSOL() async throws {
        try await doTest(testJSONFile: "direct-swap-tests", testName: "splToSol", isSimulation: true)
    }
    
    func testDirectSwapSPLToCreatedSPL() async throws {
        try await doTest(testJSONFile: "direct-swap-tests", testName: "splToCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSPLToNonCreatedSPL() async throws {
        try await doTest(testJSONFile: "direct-swap-tests", testName: "splToNonCreatedSpl", isSimulation: true)
    }
    
    // MARK: - Transitive swap
    func testTransitiveSwapSOLToCreatedSPL() async throws {
        try await doTest(testJSONFile: "transitive-swap-tests", testName: "solToCreatedSpl", isSimulation: true)
    }
    
    func testTransitiveSwapSOLToNonCreatedSPL() async throws {
        let test = try await doTest(testJSONFile: "transitive-swap-tests", testName: "solToNonCreatedSpl", isSimulation: true)
        
        try closeAssociatedToken(mint: test.toMint)
    }

    func testTransitiveSwapSPLToSOL() async throws {
        try await doTest(testJSONFile: "transitive-swap-tests", testName: "splToSol", isSimulation: true)
    }
    
    func testTransitiveSwapSPLToCreatedSPL() async throws {
        try await doTest(testJSONFile: "transitive-swap-tests", testName: "splToCreatedSpl", isSimulation: true)
    }
    
    func testTransitiveSwapSPLToNonCreatedSPL() async throws {
        let test = try await doTest(testJSONFile: "transitive-swap-tests", testName: "splToNonCreatedSpl", isSimulation: true)
        
        try closeAssociatedToken(mint: test.toMint)
    }
    
    
    // MARK: - Helpers
    @discardableResult
    func doTest(testJSONFile: String, testName: String, isSimulation: Bool) async throws -> SwapTest {
        let test = try getDataFromJSONTestResourceFile(fileName: testJSONFile, decodedTo: [String: SwapTest].self)[testName]!
        
        let network = Network.mainnetBeta
        let orcaSwapNetwork = network == .mainnetBeta ? "mainnet": network.cluster
        
        let solanaAPIClient = MockSolanaAPIClient2(endpoint: .init(address: test.endpoint, network: network, additionalQuery: test.endpointAdditionalQuery))
        let blockchainClient = BlockchainClient(apiClient: solanaAPIClient)
        orcaSwap = OrcaSwap(
            apiClient: APIClient(configsProvider: MockConfigsProvider()),
            solanaClient: solanaAPIClient,
            blockchainClient: blockchainClient,
            accountStorage: MockAccountStorage(
                _account: try await Account(
                    phrase: test.seedPhrase.components(separatedBy: " "),
                    network: network
                )
            )
        )
        try await orcaSwap.load()
        
        let _ = try await fillPoolsBalancesAndSwap(
            fromWalletPubkey: test.sourceAddress,
            toWalletPubkey: test.destinationAddress,
            bestPoolsPair: test.poolsPair,
            amount: test.inputAmount,
            slippage: test.slippage,
            isSimulation: isSimulation
        )
        
        return test
    }
    
    func closeAssociatedToken(mint: String) throws {
        let associatedTokenAddress = try PublicKey.associatedTokenAddress(
            walletAddress: orcaSwap.accountStorage.account!.publicKey,
            tokenMintAddress: try PublicKey(string: mint)
        )
        
//        let _ = try orcaSwap.solanaClient.closeTokenAccount(
//            tokenPubkey: associatedTokenAddress.base58EncodedString
//        )
//            .retry { errors in
//                errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
//                    let error = error as! SolanaError
//                    switch error {
//                    case .invalidResponse(let error) where error.data?.logs?.contains("Program log: Error: InvalidAccountData") == true:
//                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
//                    default:
//                        break
//                    }
//                    return .error(error)
//                }
//            }
//            .timeout(.seconds(60), scheduler: MainScheduler.instance)
//            .toBlocking().first()
    }
    
    // MARK: - Helper
    func fillPoolsBalancesAndSwap(
        fromWalletPubkey: String,
        toWalletPubkey: String?,
        bestPoolsPair: [RawPool],
        amount: Double,
        slippage: Double,
        isSimulation: Bool
    ) async throws -> SwapResponse {
        let poolsFromAPI = try await orcaSwap.apiClient.getPools()
        var pools = [OrcaSwapSwift.Pool]()
        for rawPool in bestPoolsPair {
            var pool = poolsFromAPI[rawPool.name]!
            if rawPool.reversed {
                pool = pool.reversed
            }
            pool = try await pool.filledWithUpdatedBalances(apiClient: orcaSwap.solanaClient)
            pools.append(pool)
        }
        
        return try await orcaSwap.swap(
            fromWalletPubkey: fromWalletPubkey,
            toWalletPubkey: toWalletPubkey,
            bestPoolsPair: pools,
            amount: amount,
            slippage: 0.5,
            isSimulation: isSimulation
        )
    }
}

private extension OrcaSwapSwift.Pool {
    func filledWithUpdatedBalances<APIClient: SolanaAPIClient>(apiClient: APIClient) async throws -> OrcaSwapSwift.Pool {
        let (tokenABalance, tokenBBalance) = try await (
            apiClient.getTokenAccountBalance(pubkey: tokenAccountA, commitment: nil),
            apiClient.getTokenAccountBalance(pubkey: tokenAccountB, commitment: nil)
        )
        var pool = self
        pool.tokenABalance = tokenABalance
        pool.tokenBBalance = tokenBBalance
        return pool
    }
}

private struct MockAccountStorage: SolanaAccountStorage {
    let _account: Account
    var account: Account? {
        get throws {
            _account
        }
    }
    
    func save(_ account: Account) throws {
        // do nothing
    }
}

public class MockSolanaAPIClient2: SolanaAPIClient {
    init(endpoint: APIEndPoint) {
        self.endpoint = endpoint
    }
    
    public var endpoint: APIEndPoint
    
    public func request<Entity>(with request: JSONRPCAPIClientRequest<AnyDecodable>) async throws -> AnyResponse<Entity> where Entity : Decodable {
        fatalError()
    }
    
    public func request(with requests: [JSONRPCAPIClientRequest<AnyDecodable>]) async throws -> [AnyResponse<AnyDecodable>] {
        fatalError()
    }
    
    public typealias ResponseDecoder = JSONRPCResponseDecoder
    public typealias RequestEncoder = JSONRPCRequestEncoder
    
}

public extension MockSolanaAPIClient2 {
    func getTokenAccountBalance(pubkey: String, commitment: Commitment?) async throws -> TokenAccountBalance {
        switch pubkey {
        case "FdiTt7XQ94fGkgorywN1GuXqQzmURHCDgYtUutWRcy4q":
            return TokenAccountBalance(amount: 389.627856679, decimals: 9)
        case "7VcwKUtdKnvcgNhZt5BQHsbPrXLxhdVomsgrr7k2N5P5":
            return TokenAccountBalance(amount: 27053.369728, decimals: 6)
        default:
            fatalError()
        }
    }
    
    func getMinimumBalanceForRentExemption(dataLength: UInt64, commitment: Commitment? = "recent") async throws -> UInt64 {
        2039280
    }
    
    func getMinimumBalanceForRentExemption(span: UInt64) async throws -> UInt64 {
        2039280
    }
    
    func getFees(commitment: Commitment? = nil) async throws -> Fee {
        .init(feeCalculator: .init(lamportsPerSignature: 5000), feeRateGovernor: nil, blockhash: "ADZgUVaAfUx5ehFXivdaUSHucpNdk4VqGSdN4TjttWgr", lastValidSlot: 133257026)
    }
    
    func getRecentBlockhash(commitment: Commitment? = nil) async throws -> String {
        "NS37crgkUQQwwFjdEdWNQFCyatLGN68F55FG2Hv4FFS"
    }
}
