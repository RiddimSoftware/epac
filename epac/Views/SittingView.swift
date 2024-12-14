//
//  SittingView.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftUI

struct SittingView: View {
	let hansard: Hansard
	var body: some View {
		List {
			ForEach(hansard.orders.filter { !$0.subjects.isEmpty }) { order in
				Section {
					ForEach(order.subjects) { subject in
						VStack {
							Text(subject.title)
						}
					}
				} header: {
					VStack {
						Text(order.catchline)
							.font(.system(size: 25, weight: .bold))
					}
				}
			}
		}
		.listStyle(.plain)
		.listSectionSpacing(20)
//		List(hansard.orders.filter { !$0.subjects.isEmpty }) { order in
//			ForEach(hansard.orders) { order in

//			}
//		}
	}
}
