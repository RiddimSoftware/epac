# EPAC clean-architecture reference slice

EPAC-1742 introduces the first explicit application-layer slice for the iOS app.

## Use cases in this slice

- `SearchHansard`: framework-free search logic over cached Hansard subject snapshots. The use case depends on a `HansardSearchStore` port; `SwiftDataHansardSearchStore` is the outer adapter.
- `FollowTopic`: onboarding/UI follows topics through an inward use case instead of mutating `TopicFollowStore` directly. The use case persists through a store port and triggers device registration through a separate port.
- `RegisterDevice`: composes the backend registration payload from push-token + follow-state ports and sends it through a `DeviceRegistrationGateway` port.

## Boundary rule

Views and view models may compose adapters, but business orchestration lives here. Future EPAC slices should copy this pattern: define a framework-free use case + port in `Application/`, then implement outer adapters in `Infrastructure/` or existing store/service files.
