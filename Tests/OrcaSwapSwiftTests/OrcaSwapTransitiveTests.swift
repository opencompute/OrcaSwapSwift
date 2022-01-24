//
//  File.swift
//
//
//  Created by Chung Tran on 18/10/2021.
//

import Foundation
import XCTest
@testable import SolanaSwift

class OrcaSwapTransitiveTests: OrcaSwapSwapTests {
//    // MARK: - Transitive SOL to SPL
//    func testTransitiveSwapSOLToCreatedSPL() throws {
//        let swapSimulation = try fillPoolsBalancesAndSwap(
//            fromWalletPubkey: solPubkey,
//            toWalletPubkey: kuroPubkey,
//            bestPoolsPair: [
//                .init(name: "SOL/USDC[aquafarm]"),
//                .init(name: "KURO/USDC[aquafarm]", reversed: true)
//            ],
//            amount: 0.001,
//            slippage: 0.5,
//            isSimulation: true
//        )
//        
//        XCTAssertNoThrow(try swapSimulation.toBlocking().first())
//    }
//    
//    func testTransitiveSwapSOLToUncreatedSPL() throws {
//        let swapSimulation = try fillPoolsBalancesAndSwap(
//            fromWalletPubkey: solPubkey,
//            toWalletPubkey: nil,
//            bestPoolsPair: [
//                .init(name: "SOL/USDC[aquafarm]"),
//                .init(name: "ABR/USDC[aquafarm]", reversed: true)
//            ],
//            amount: 0.001,
//            slippage: 0.5,
//            isSimulation: true
//        )
//
//        XCTAssertNoThrow(try swapSimulation.toBlocking().first())
//    }
//    
//    // MARK: - Transitive SPL to SOL
//    func testTransitiveSwapSPLToSOL() throws {
//        let swapSimulation = try fillPoolsBalancesAndSwap(
//            fromWalletPubkey: kuroPubkey,
//            toWalletPubkey: solPubkey,
//            bestPoolsPair: [
//                .init(name: "KURO/USDC[aquafarm]"),
//                .init(name: "SOL/USDC[aquafarm]", reversed: true)
//            ],
//            amount: 1,
//            slippage: 0.05,
//            isSimulation: false
//        )
//        
//        XCTAssertNoThrow(try swapSimulation.toBlocking().first())
//    }
//    
//    // MARK: - Transitive SPL to SPL
//    func testTransitiveSwapSPLToCreatedSPL() throws {
//        let swapSimulation = try fillPoolsBalancesAndSwap(
//            fromWalletPubkey: slimPubkey,
//            toWalletPubkey: kuroPubkey,
//            bestPoolsPair: [
//                .init(name: "SLIM/USDC[aquafarm]"),
//                .init(name: "KURO/USDC[aquafarm]", reversed: true)
//            ],
//            amount: 0.01,
//            slippage: 0.5,
//            isSimulation: true
//        )
//        
//        XCTAssertNoThrow(try swapSimulation.toBlocking().first())
//    }
//    
//    func testTransitiveSwapSPLToUncreatedSPL() throws {
//        let swapSimulation = try fillPoolsBalancesAndSwap(
//            fromWalletPubkey: slimPubkey,
//            toWalletPubkey: nil,
//            bestPoolsPair: [
//                .init(name: "SLIM/USDC[aquafarm]"),
//                .init(name: "ABR/USDC[aquafarm]", reversed: true)
//            ],
//            amount: 0.01,
//            slippage: 0.05,
//            isSimulation: false
//        )
//        
//        XCTAssertNoThrow(try swapSimulation.toBlocking().first())
//    }
}
