//
//  ServicePortsAdapters.swift
//  epac
//

import Foundation

extension LiveParliamentService: LiveParliamentStatusFetching {}
extension OnThisDayService: @unchecked Sendable, OnThisDayFetching {}
