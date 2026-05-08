//
//  ServicePortsAdapters.swift
//  epac
//

import Foundation

extension LiveParliamentService: @unchecked Sendable, LiveParliamentStatusFetching {}
extension OnThisDayService: @unchecked Sendable, OnThisDayFetching {}
